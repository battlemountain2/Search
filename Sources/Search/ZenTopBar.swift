import SwiftUI

/// A compact, Zen-style floating navigation bar positioned above the web card.
/// Provides visible Back / Forward / Reload controls, an address capsule showing the domain,
/// and an integrated Page Actions & Settings toolbox popover (Reader Mode, Split View, Cinema Mode, Extensions).
struct ZenTopBar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    static let height: CGFloat = 34

    @State private var capsuleHovered = false
    @State private var showToolbox = false
    @State private var showSiteCard = false

    var body: some View {
        HStack(spacing: 8) {
            // Navigation Cluster (Back, Forward, Reload)
            navigationControls

            Spacer(minLength: 0)

            // Seamless Arc/Zen style Address Capsule with integrated URL toolbox
            addressCapsule

            Spacer(minLength: 0)

            // Pinned Extensions cluster aligned to the right (like Zen)
            pinnedExtensionsCluster
        }
        .padding(.horizontal, 8)
        .frame(height: ZenTopBar.height)
        .background(
            ZStack {
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                (prefs.cards ? Palette.frame : Palette.ground).opacity(prefs.zenDarkGlass ? 0.28 : 0.18)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            Group {
                if !prefs.zenBorderless {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                }
            }
        )
    }

    // MARK: - Navigation Controls

    @ViewBuilder
    private var navigationControls: some View {
        if let tab = browser.active {
            let back = !tab.isBlank && tab.canGoBack
            let forward = !tab.isBlank && tab.canGoForward

            HStack(spacing: 2) {
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
            Color.clear.frame(width: 80, height: 26)
        }
    }

    // MARK: - Address Capsule (Clean Arc / Zen Company Style)

    @ViewBuilder
    private var addressCapsule: some View {
        if let tab = browser.active {
            HStack(spacing: 6) {
                // Security / Scheme Icon & Site Permissions Popover (Like Zen & Safari)
                Button {
                    Haptics.tap()
                    showSiteCard.toggle()
                } label: {
                    Image(systemName: tab.address?.scheme == "https" ? "lock.fill" : "globe")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(tab.address?.scheme == "https" ? Palette.safe : Palette.muted)
                        .frame(width: 18, height: 18)
                        .background(showSiteCard ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .help("View site security, certificate & permissions")
                .popover(isPresented: $showSiteCard, arrowEdge: .bottom) {
                    SiteCard(browser: browser, tab: tab) {
                        showSiteCard = false
                    }
                    .padding(4)
                }

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

                // Zen-style Page Actions & Settings button (triggers URL toolbox popover)
                Button {
                    Haptics.tap()
                    showToolbox.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(showToolbox ? Color.accentColor : Palette.muted)
                        .frame(width: 22, height: 22)
                        .background(showToolbox ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .help("Page Actions & Site Settings")
                .popover(isPresented: $showToolbox, arrowEdge: .bottom) {
                    UrlToolboxView(browser: browser, tab: tab) {
                        showToolbox = false
                    }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .frame(minWidth: 220, maxWidth: 380, maxHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(capsuleHovered || showToolbox ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
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

    // MARK: - Pinned Extensions Cluster (Top Right)

    @ViewBuilder
    private var pinnedExtensionsCluster: some View {
        HStack(spacing: 2) {
            ExtensionSlot(browser: browser, edge: .bottom, room: 4, showDoor: false)
        }
        .frame(minWidth: 80, alignment: .trailing)
    }
}

// MARK: - Zen URL Toolbox Popover (Ardia / Zen Style)

struct UrlToolboxView: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    let onDismiss: () -> Void

    @State private var copiedLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Top Quick Action Buttons Row (Share, Capture, Pin, Bookmark)
            HStack(spacing: 6) {
                // Share / Copy Link
                ToolboxPillButton(
                    icon: copiedLink ? "checkmark" : "square.and.arrow.up",
                    label: copiedLink ? "Copied" : "Share",
                    iconColor: copiedLink ? Palette.safe : nil
                ) {
                    if let url = tab.address {
                        CleanLink.copy(url)
                        copiedLink = true
                        Haptics.tap()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedLink = false }
                    }
                }

                // Screenshot / Capture
                ToolboxPillButton(
                    icon: "camera",
                    label: "Capture"
                ) {
                    Haptics.click()
                    browser.toggleSnap()
                    onDismiss()
                }

                // Pin / Unpin
                ToolboxPillButton(
                    icon: tab.pin != nil ? "pin.fill" : "pin",
                    label: tab.pin != nil ? "Unpin" : "Pin",
                    iconColor: tab.pin != nil ? Color.accentColor : nil
                ) {
                    Haptics.tap()
                    browser.pins.toggle(tab)
                }

                // Bookmark
                let bookmarked = tab.address.map { browser.bookmarks.contains($0) } ?? false
                ToolboxPillButton(
                    icon: bookmarked ? "bookmark.fill" : "bookmark",
                    label: bookmarked ? "Saved" : "Save",
                    iconColor: bookmarked ? Color.yellow : nil
                ) {
                    Haptics.tap()
                    browser.bookmarks.toggle(tab)
                }
            }

            Divider().opacity(0.3)

            // 2. Extensions Section
            if #available(macOS 15.4, *) {
                let extensions = Extensions.shared
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Extensions")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                        Spacer()
                    }

                    if extensions.installed.isEmpty {
                        Text("No extensions installed")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted.opacity(0.6))
                            .padding(.vertical, 2)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(extensions.buttons) { button in
                                    Button {
                                        Haptics.tap()
                                        extensions.press(button.id, in: browser)
                                        onDismiss()
                                    } label: {
                                        VStack(spacing: 3) {
                                            ExtensionIcon(button: button, size: 16)
                                                .frame(width: 30, height: 30)
                                                .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                            Text(button.name)
                                                .font(.system(size: 9))
                                                .foregroundStyle(Palette.ink)
                                                .lineLimit(1)
                                                .frame(width: 46)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .focusable(false)
                                    .focusEffectDisabled()
                                }

                                // Manage Extensions (+) button
                                Button {
                                    Haptics.tap()
                                    browser.tuning = true
                                    onDismiss()
                                } label: {
                                    VStack(spacing: 3) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Palette.muted)
                                            .frame(width: 30, height: 30)
                                            .background(Palette.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        Text("Manage")
                                            .font(.system(size: 9))
                                            .foregroundStyle(Palette.muted)
                                            .frame(width: 46)
                                    }
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .focusEffectDisabled()
                            }
                        }
                    }
                }

                Divider().opacity(0.3)
            }

            // 3. Settings / Site Controls Section
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.muted)

                // Reader Mode Row
                ToolboxSettingRow(
                    icon: "doc.plaintext",
                    title: "Reader View",
                    subtitle: "Distraction-free article reader",
                    actionTitle: "Toggle"
                ) {
                    Haptics.tap()
                    browser.toggleReader()
                    onDismiss()
                }

                // Split View Row
                ToolboxSettingRow(
                    icon: "rectangle.split.2x1",
                    title: "Split View",
                    subtitle: browser.prefs.splitView ? "Active side-by-side" : "Browse two tabs together",
                    actionTitle: browser.prefs.splitView ? "Close" : "Split",
                    isActive: browser.prefs.splitView
                ) {
                    Haptics.click()
                    browser.splitKey()
                    onDismiss()
                }

                // Cinema Mode Row
                ToolboxSettingRow(
                    icon: "film",
                    title: "Cinema Mode",
                    subtitle: "Spotlight video & dim distractions",
                    actionTitle: "Toggle"
                ) {
                    Haptics.tap()
                    browser.toggleCinema()
                    onDismiss()
                }
            }

            Divider().opacity(0.3)

            // 4. Bottom Security & More Bar
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: tab.address?.scheme == "https" ? "lock.fill" : "globe")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(tab.address?.scheme == "https" ? Palette.safe : Palette.muted)
                    Text(tab.address?.scheme == "https" ? "Secure Connection" : "Insecure")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.muted)
                }

                Spacer()

                Button {
                    Haptics.tap()
                    browser.copyAddress()
                    copiedLink = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedLink = false }
                } label: {
                    Text(copiedLink ? "Copied" : "Copy URL")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
            }
        }
        .padding(12)
        .frame(width: 295)
        .background(
            ZStack {
                VisualEffectView(material: .popover, blendingMode: .withinWindow)
                Palette.ground.opacity(0.92)
            }
        )
    }
}

private struct ToolboxPillButton: View {
    let icon: String
    let label: String
    var iconColor: Color? = nil
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor ?? Palette.ink)
                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovered ? Palette.ink.opacity(0.08) : Palette.ink.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .onHover { hovered = $0 }
    }
}

private struct ToolboxSettingRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let actionTitle: String
    var isActive: Bool = false
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isActive ? Color.accentColor : Palette.ink)
                    .frame(width: 22, height: 22)
                    .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text(actionTitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isActive ? Color.accentColor : Palette.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(isActive ? Color.accentColor.opacity(0.12) : Palette.ink.opacity(0.04), in: Capsule())
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(hovered ? Palette.ink.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .onHover { hovered = $0 }
    }
}
