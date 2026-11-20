import SwiftUI

/// A compact, Zen-style floating navigation bar positioned above the web card.
/// Provides visible Back / Forward / Reload controls, an address capsule showing the domain,
/// and an integrated Page Actions & Settings menu inside the address capsule (Reader Mode, Split View, Extensions).
struct ZenTopBar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    static let height: CGFloat = 34

    @State private var capsuleHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Navigation Cluster (Back, Forward, Reload)
            navigationControls

            Spacer(minLength: 0)

            // Address Capsule with integrated Zen-style actions
            addressCapsule

            Spacer(minLength: 0)

            // Balance spacer matching navigation cluster width
            Color.clear
                .frame(width: 86, height: 26)
        }
        .padding(.horizontal, 10)
        .frame(height: ZenTopBar.height)
        .background(
            ZStack {
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                (prefs.cards ? Palette.frame : Palette.ground).opacity(0.24)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    // MARK: - Navigation Controls

    @ViewBuilder
    private var navigationControls: some View {
        if let tab = browser.active {
            let back = !tab.isBlank && tab.canGoBack
            let forward = !tab.isBlank && tab.canGoForward

            HStack(spacing: 4) {
                // Back Button
                Button {
                    Haptics.tap()
                    browser.back()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(back ? Palette.ink : Palette.muted.opacity(0.35))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!back)
                .help("Back   ⌘[")

                // Forward Button
                Button {
                    Haptics.tap()
                    browser.forward()
                } label: {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(forward ? Palette.ink : Palette.muted.opacity(0.35))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!forward)
                .help("Forward   ⌘]")

                // Reload / Stop Button
                Button {
                    Haptics.tap()
                    if tab.loading {
                        tab.stop()
                    } else {
                        tab.reload()
                    }
                } label: {
                    Image(systemName: tab.loading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tab.loading ? "Stop Loading   esc" : "Reload Page   ⌘R")
            }
        } else {
            Color.clear.frame(width: 86, height: 26)
        }
    }

    // MARK: - Address Capsule

    @ViewBuilder
    private var addressCapsule: some View {
        if let tab = browser.active {
            HStack(spacing: 6) {
                // Security / Scheme Icon
                Image(systemName: tab.address?.scheme == "https" ? "lock.fill" : "globe")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(tab.address?.scheme == "https" ? Palette.safe : Palette.muted)

                // Domain text button (expands to fill capsule center)
                Button {
                    Haptics.tap()
                    browser.edit()
                } label: {
                    Text(displayDomain(for: tab))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .help("Click to edit URL or search   ⌘L")

                // Zen-style Page Actions & Settings inside the capsule
                pageSettingsMenu
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(minWidth: 220, maxWidth: 380, maxHeight: 25)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(capsuleHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(capsuleHovered ? 0.18 : 0.08), lineWidth: 0.5)
            )
            .onHover { capsuleHovered = $0 }
        }
    }

    private func displayDomain(for tab: Tab) -> String {
        if let host = tab.address?.host, !host.isEmpty {
            return host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        }
        return tab.title.isEmpty ? "Search or enter address" : tab.title
    }

    // MARK: - Page Actions Menu inside the Capsule

    @ViewBuilder
    private var pageSettingsMenu: some View {
        Menu {
            // Reader Mode
            Button {
                Haptics.tap()
                browser.toggleReader()
            } label: {
                Label("Toggle Reader Mode", systemImage: "doc.plaintext")
            }

            // Split View
            Button {
                Haptics.click()
                browser.splitKey()
            } label: {
                Label(browser.prefs.splitView ? "Close Split View" : "Split View", systemImage: "rectangle.split.2x1")
            }

            // Extensions Submenu
            if #available(macOS 15.4, *) {
                let extensions = Extensions.shared
                if !extensions.installed.isEmpty {
                    Menu {
                        ForEach(extensions.buttons) { button in
                            Button {
                                extensions.press(button.id, in: browser)
                            } label: {
                                Text(button.name)
                            }
                        }
                    } label: {
                        Label("Extensions", systemImage: "puzzlepiece.extension")
                    }
                }
            }

            Divider()

            // Copy Address
            Button {
                Haptics.tap()
                browser.copyAddress()
            } label: {
                Label("Copy Address", systemImage: "link")
            }

            // Copy Clean Link
            Button {
                Haptics.tap()
                browser.copyCleanLink()
            } label: {
                Label("Copy Clean Link", systemImage: "sparkles")
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 20, height: 20)
        .help("Page Actions & Settings")
    }
}
