import Foundation
import IOKit.pwr_mgt

/// Holds a single macOS display-sleep power assertion whenever at least one
/// open tab has "Keep Mac Awake" enabled, releasing it automatically when
/// all awake tabs are closed or toggled off.
@MainActor
enum KeepAwake {
    private static var assertionID: IOPMAssertionID = 0
    private static var active = false

    static func sync(hasAwakeTabs: Bool) {
        if hasAwakeTabs && !active {
            var id: IOPMAssertionID = 0
            let reason = "Search: Keeping Mac Awake for Tab" as CFString
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &id
            )
            if result == kIOReturnSuccess {
                assertionID = id
                active = true
            }
        } else if !hasAwakeTabs && active {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            active = false
        }
    }
}
