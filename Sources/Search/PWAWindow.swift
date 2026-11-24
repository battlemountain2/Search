import AppKit
import SwiftUI
import WebKit

/// A dedicated, frameless standalone window for Progressive Web Apps.
/// Features dynamic `theme_color` glass header tinting, inset traffic lights,
/// smart external link trapping, and standard desktop keyboard shortcuts.
@MainActor
final class PWAWindow: NSObject, NSWindowDelegate, ObservableObject {
    /// Open PWA windows, newest last.
    private(set) static var open: [PWAWindow] = []

    let tab: Tab
    let pwa: PWAInfo
    private weak var browser: Browser?
    let window: NSWindow
    private var keyMonitor: Any?

    private static let smallest = NSSize(width: 500, height: 400)

    /// Finds an open PWA window holding the given tab.
    static func holding(_ id: Tab.ID) -> PWAWindow? {
        open.first { $0.tab.id == id }
    }

    /// Finds the PWA window matching an NSWindow.
    static func owning(_ window: NSWindow?) -> PWAWindow? {
        guard let window else { return nil }
        return open.first { $0.window === window }
    }

    /// Opens or lifts a tab into a dedicated standalone PWA window.
    static func show(for tab: Tab, browser: Browser, space: UUID? = nil) {
        if let existing = holding(tab.id) {
            existing.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Lift tab out of the browser row if present
        if browser.tabs.contains(where: { $0.id == tab.id }) {
            browser.detachForPWA(tab)
        }

        let pwaInfo = tab.pwa ?? PWAInfo(
            name: tab.title.isEmpty ? (tab.address.flatMap(PWA.knownApp(for:)) ?? "Web App") : tab.title,
            host: tab.address?.host() ?? "",
            startURL: tab.address ?? URL(string: "https://about:blank")!,
            themeColorHex: nil,
            themeColor: tab.built?.themeColor,
            hasManifest: false,
            isKnownApp: tab.address.map { PWA.knownApp(for: $0) != nil } ?? false
        )

        let pwaWindow = PWAWindow(tab: tab, pwa: pwaInfo, browser: browser)
        open.append(pwaWindow)

        pwaWindow.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(tab: Tab, pwa: PWAInfo, browser: Browser) {
        self.tab = tab
        self.pwa = pwa
        self.browser = browser

        let defaultRect = NSRect(x: 0, y: 0, width: 1060, height: 740)
        window = NSWindow(
            contentRect: defaultRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = Self.smallest

        let host = pwa.host.isEmpty ? "default" : pwa.host
        if let savedFrame = Self.remembered(for: host) {
            window.setFrame(savedFrame, display: false)
        } else {
            window.center()
        }

        window.delegate = self

        window.contentView = NSHostingView(rootView: PWAView(
            tab: tab,
            pwa: pwa,
            openInBrowser: { [weak self] in self?.openInSearchBrowser() },
            closeWindow: { [weak self] in self?.window.performClose(nil) }
        ))

        installKeyMonitor()
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if self.handleKey(event) {
                return nil
            }
            return event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags == .command {
            switch chars {
            case "r":
                tab.reload(fromOrigin: false)
                return true
            case "w":
                window.performClose(nil)
                return true
            case "o":
                openInSearchBrowser()
                return true
            case "[":
                if tab.canGoBack { tab.back() }
                return true
            case "]":
                if tab.canGoForward { tab.forward() }
                return true
            case "=", "+":
                tab.magnify(to: tab.zoom * 1.1)
                return true
            case "-":
                tab.magnify(to: tab.zoom / 1.1)
                return true
            case "0":
                tab.resetZoom()
                return true
            default:
                break
            }
        } else if flags == [.command, .shift] {
            if chars == "c", let url = tab.address {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                return true
            } else if chars == "r" {
                tab.reload(fromOrigin: true)
                return true
            }
        }

        return false
    }

    /// Restores the tab back into a main Search browser window.
    func openInSearchBrowser() {
        let targetBrowser = browser ?? Browsers.front ?? Browsers.all.first
        guard let target = targetBrowser else { return }

        // Remove from PWA open list
        PWAWindow.open.removeAll { $0 === self }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }

        // Re-attach tab into the browser
        target.receive(tab)

        window.close()
        target.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Handles external out-of-scope links clicked inside the PWA window.
    func routeExternalLink(_ url: URL) {
        let target = browser ?? Browsers.front ?? Browsers.all.first
        target?.open(url, foreground: true)
        target?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Frame Preservation

    private static func remembered(for host: String) -> NSRect? {
        guard let text = Store.settings.string(forKey: "pwa.frame." + host) else { return nil }
        let frame = NSRectFromString(text)
        guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite),
              frame.width >= smallest.width, frame.height >= smallest.height else { return nil }
        return NSScreen.screens.contains {
            let seen = $0.visibleFrame.intersection(frame)
            return !seen.isNull && seen.width * seen.height > 0.5 * frame.width * frame.height
        } ? frame : nil
    }

    private func rememberFrame() {
        guard !window.styleMask.contains(.fullScreen) else { return }
        let host = pwa.host.isEmpty ? "default" : pwa.host
        Store.settings.set(NSStringFromRect(window.frame), forKey: "pwa.frame." + host)
    }

    func windowDidMove(_ notification: Notification) {
        guard window.isVisible else { return }
        rememberFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        rememberFrame()
    }

    func windowWillClose(_ notification: Notification) {
        rememberFrame()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        PWAWindow.open.removeAll { $0 === self }
        tab.close()
    }
}

// MARK: - Standalone PWA View

struct PWAView: View {
    @ObservedObject var tab: Tab
    let pwa: PWAInfo
    let openInBrowser: () -> Void
    let closeWindow: () -> Void

    @State private var hoveringBack = false
    @State private var hoveringForward = false
    @State private var hoveringReload = false
    @State private var showMenu = false

    var body: some View {
        VStack(spacing: 0) {
            // Dynamic theme_color glass header
            headerBar
                .frame(height: 32)
                .background(WindowDragBar())

            // Edge-to-edge Web App Canvas
            ZStack {
                WebStage(page: tab.built ?? tab.web)

                if let failure = tab.failure {
                    Trouble(message: failure) { tab.reload() }
                        .transition(.opacity)
                }
            }
            .animation(Motion.quick, value: tab.failure)
        }
        .background(Palette.ground)
        .ignoresSafeArea()
    }

    // MARK: - Header Bar

    @ViewBuilder
    private var headerBar: some View {
        HStack(spacing: 6) {
            // Space for native macOS traffic lights (red, yellow, green)
            Spacer().frame(width: 68)

            // Back button
            Button {
                Haptics.tap()
                if tab.canGoBack { tab.back() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(tab.canGoBack ? Palette.ink : Palette.muted.opacity(0.4))
                    .frame(width: 20, height: 20)
                    .background(hoveringBack && tab.canGoBack ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .disabled(!tab.canGoBack)
            .onHover { hoveringBack = $0 }
            .help("Back   ⌘[")

            // Forward button
            Button {
                Haptics.tap()
                if tab.canGoForward { tab.forward() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(tab.canGoForward ? Palette.ink : Palette.muted.opacity(0.4))
                    .frame(width: 20, height: 20)
                    .background(hoveringForward && tab.canGoForward ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .disabled(!tab.canGoForward)
            .onHover { hoveringForward = $0 }
            .help("Forward   ⌘]")

            // Reload button
            Button {
                Haptics.tap()
                tab.reload()
            } label: {
                Image(systemName: tab.loading ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.ink.opacity(0.75))
                    .frame(width: 20, height: 20)
                    .background(hoveringReload ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .onHover { hoveringReload = $0 }
            .help("Reload   ⌘R")

            Spacer(minLength: 0)

            // Center Title & Domain Cluster
            HStack(spacing: 5) {
                Mark(icon: Favicons.shared.cached(for: tab.address),
                     letter: String((pwa.name.isEmpty ? "A" : pwa.name).prefix(1)).uppercased(),
                     size: 13)

                Text(pwa.name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)

                // Optional unread count badge
                if let unreadCount = tab.unread {
                    Text(unreadCount)
                        .font(.system(size: 8.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color(red: 0.93, green: 0.24, blue: 0.21)))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.04), in: Capsule())

            Spacer(minLength: 0)

            // Right Actions Menu Button
            Menu {
                Button("Copy Address") {
                    if let url = tab.address {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                }
                Button("Open in Main Browser (⌘O)") {
                    openInBrowser()
                }
                Divider()
                Button("Reload Page (⌘R)") {
                    tab.reload()
                }
                Button("Clear Site Cache & Reload") {
                    tab.reload(fromOrigin: true)
                }
                Divider()
                Button("Close Window (⌘W)") {
                    closeWindow()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24, height: 24)
            .help("App Options")
            .padding(.trailing, 8)
        }
        .padding(.horizontal, 4)
        .background {
            // Dynamic Tinting: Uses WebKit themeColor or falls back to frosted glass
            ZStack {
                VisualEffectView(material: .headerView, blendingMode: .behindWindow)

                if let themeColor = tab.built?.themeColor ?? pwa.themeColor {
                    Color(nsColor: themeColor)
                        .opacity(0.60)
                } else {
                    Palette.ground.opacity(0.20)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5)
        }
    }
}
