import SwiftUI

/// A compact, Zen-style floating navigation bar positioned above the web card.
/// Provides visible Back / Forward / Reload controls, an address capsule showing the domain,
/// and quick action buttons (Split View, Reader Mode, Extensions).
struct ZenTopBar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    static let height: CGFloat = 34

    @State private var capsuleHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Navigation Cluster
            navigationControls

            Spacer(minLength: 0)

            // Address Capsule
            addressCapsule

            Spacer(minLength: 0)

            // Action Cluster
            actionControls
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
        }
    }

    // MARK: - Address Capsule

    @ViewBuilder
    private var addressCapsule: some View {
        if let tab = browser.active {
            Button {
                Haptics.tap()
                browser.edit()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: tab.address?.scheme == "https" ? "lock.fill" : "globe")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(tab.address?.scheme == "https" ? Palette.safe : Palette.muted)

                    Text(displayDomain(for: tab))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .frame(minWidth: 200, maxWidth: 380, maxHeight: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(capsuleHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(capsuleHovered ? 0.18 : 0.08), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .onHover { capsuleHovered = $0 }
            .help("Click to edit URL or search   ⌘L")
        }
    }

    private func displayDomain(for tab: Tab) -> String {
        if let host = tab.address?.host, !host.isEmpty {
            return host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        }
        return tab.title.isEmpty ? "Search or enter address" : tab.title
    }

    // MARK: - Action Controls

    @ViewBuilder
    private var actionControls: some View {
        HStack(spacing: 4) {
            // Split View Toggle
            Button {
                Haptics.click()
                browser.splitKey()
            } label: {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(browser.prefs.splitView ? Palette.accent : Palette.ink)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .help("Split View   ⌥⌘N")

            // Reader Mode (if available)
            if let tab = browser.active, tab.readerAvailable {
                Button {
                    Haptics.tap()
                    browser.toggleReader()
                } label: {
                    Image(systemName: tab.reading ? "doc.plaintext.fill" : "doc.plaintext")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tab.reading ? Palette.accent : Palette.ink)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .help("Toggle Reader Mode   ⇧⌘R")
            }

            // Extension Slot
            ExtensionSlot(browser: browser, edge: .bottom, room: 0)
        }
    }
}
