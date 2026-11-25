import AppKit
import Darwin
import WebKit

// Memory the app has finished with, handed back to the Mac.
//
// An extension's declarativeNetRequest rules are compiled by WebKit inside
// this process: all of them, every time the extension changes any. AdBlock's
// lists come to 150 MB compiled, and building them takes the app from under
// a hundred megabytes to over a gigabyte for a minute — at launch, and again
// each time it fetches a filter update. When it is done, a few dozen
// megabytes are still in use; the rest has been freed, but malloc keeps the
// pages it freed dirty and counted against Search, in Activity Monitor and
// by macOS when it decides what to squeeze. Measured: 1153 MB of footprint
// around 44 MB of live allocations.
//
// When the app goes to the background or a window is minimized, malloc is
// asked to give back what it is holding empty, and WebKit is instructed to
// purge in-memory resource caches across all WebContent helper processes.
enum Trim {
    /// Growth worth a walk. Below this, what comes back isn't worth noticing.
    private static let margin: UInt64 = 64 << 20
    /// Read and written on `queue` only.
    nonisolated(unsafe) private static var after: UInt64 = 0
    private static let queue = DispatchQueue(label: "com.officecommun.search.trim", qos: .utility)

    /// Started once, at launch: background and window minimize are moments to look.
    static func start() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: nil
        ) { _ in
            look()
            DispatchQueue.main.async { purgeWebContent() }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMiniaturizeNotification, object: nil, queue: nil
        ) { _ in
            look()
            DispatchQueue.main.async { purgeWebContent() }
        }
    }

    /// Purges in-memory resource caches across all WebContent processes in all spaces.
    @MainActor
    static func purgeWebContent() {
        let types = Set([WKWebsiteDataTypeMemoryCache])
        for store in Spaces.everyStore {
            store.removeData(ofTypes: types, modifiedSince: .distantPast) { }
        }
    }

    private static var spaceTrimWork: DispatchWorkItem?

    /// Debounced cache purge after a Space switch completes so the slide animation
    /// stays at 120 Hz while background Space memory is reclaimed right after.
    @MainActor
    static func scheduleSpaceTrim() {
        spaceTrimWork?.cancel()
        let work = DispatchWorkItem {
            look()
            purgeWebContent()
        }
        spaceTrimWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// An extension's rules were just built; what building them took can go.
    /// A moment later, for the last of the work WebKit does after answering.
    static func rulesBuilt() {
        queue.asyncAfter(deadline: .now() + 2) { lookNow() }
    }

    private static func look() { queue.async { lookNow() } }

    private static func lookNow() {
        guard footprint() > after + margin else { return }
        malloc_zone_pressure_relief(nil, 0)
        after = footprint()
    }

    /// What Activity Monitor calls Memory for this process.
    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
