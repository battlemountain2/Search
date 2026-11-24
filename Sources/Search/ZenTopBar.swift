import SwiftUI
import AppKit
import SecurityInterface

/// A compact, Zen-style floating navigation bar positioned above the web card.
/// Provides visible Back / Forward / Reload controls, an address capsule showing the domain,
/// and an integrated Page Actions & Settings toolbox popover (Reader Mode, Split View, Cinema Mode, Extensions).
struct ZenTopBar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    static let height: CGFloat = 28

    @State private var capsuleHovered = false
    @State private var showToolbox = false
    @State private var showSiteCard = false

    var body: some View {
        HStack(spacing: 6) {
            // Navigation Cluster (Back, Forward, Reload)
            navigationControls

            Spacer(minLength: 0)

            // Seamless Arc/Zen style Address Capsule with integrated URL toolbox
            addressCapsule

            Spacer(minLength: 0)

            // Pinned Extensions cluster aligned to the right (like Zen)
            pinnedExtensionsCluster
        }
        .padding(.horizontal, 6)
        .frame(height: ZenTopBar.height)
        .background(WindowDragBar())
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
                        .font(.system(size: 9.75, weight: .semibold))
                        .foregroundStyle(back ? Palette.ink : Palette.muted.opacity(0.35))
                        .frame(width: 21, height: 21)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .disabled(!back)
                .help("Back   ⌘[")

                // Forward Button
                Button {
                    Haptics.tap()
                    browser.forward()
                } label: {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 9.75, weight: .semibold))
                        .foregroundStyle(forward ? Palette.ink : Palette.muted.opacity(0.35))
                        .frame(width: 21, height: 21)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
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
                        .font(.system(size: 9.75, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 21, height: 21)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .help(tab.loading ? "Stop Loading   esc" : "Reload Page   ⌘R")
            }
        } else {
            Color.clear.frame(width: 69, height: 21)
        }
    }

    // MARK: - Address Capsule (Clean Arc / Zen Company Style)

    @ViewBuilder
    private var addressCapsule: some View {
        if let tab = browser.active {
            HStack(spacing: 5) {
                // Security / Scheme Icon & Site Permissions Popover (Like Zen & Safari)
                Button {
                    Haptics.tap()
                    showSiteCard.toggle()
                } label: {
                    if tab.shy {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(Color(red: 0.82, green: 0.70, blue: 1.0))
                            .frame(width: 15, height: 15)
                            .background(showSiteCard ? Color.purple.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 3.5))
                    } else {
                        Image(systemName: tab.address?.scheme == "https" ? "lock.fill" : "globe")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(tab.address?.scheme == "https" ? Palette.safe : Palette.muted)
                            .frame(width: 15, height: 15)
                            .background(showSiteCard ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 3.5))
                    }
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .help(tab.shy ? "Private Browsing Session: no history, cookies, or cache are saved" : "View site security, certificate & permissions")
                .popover(isPresented: $showSiteCard, arrowEdge: .bottom) {
                    SiteSecurityPopoverView(browser: browser, tab: tab) {
                        showSiteCard = false
                    }
                }

                if tab.shy {
                    Text("PRIVATE")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Color(red: 0.88, green: 0.80, blue: 1.0))
                        .padding(.horizontal, 3.5)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.3), in: RoundedRectangle(cornerRadius: 3))
                }

                // Domain text button (expands to fill capsule center)
                Button {
                    Haptics.tap()
                    browser.edit()
                } label: {
                    Text(displayDomain(for: tab))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .help("Click to edit URL or search   ⌘L")

                // Subtle PWA Standalone App Window launcher icon
                if let pwa = tab.pwa {
                    Button {
                        Haptics.tap()
                        PWAInstaller.install(for: tab, browser: browser)
                    } label: {
                        Image(systemName: "arrow.down.app")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 17, height: 17)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 3.5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()
                    .help("Install \(pwa.name) as App")
                }

                // Zen-style Page Actions & Settings button (triggers URL toolbox popover)
                Button {
                    Haptics.tap()
                    showToolbox.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(showToolbox ? Color.accentColor : Palette.muted)
                        .frame(width: 18, height: 18)
                        .background(showToolbox ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
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
            .padding(.leading, 7)
            .padding(.trailing, 3)
            .frame(minWidth: 170, maxWidth: 320, maxHeight: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tab.shy ? Color.purple.opacity(0.12) : (capsuleHovered || showToolbox ? Color.white.opacity(0.08) : Color.white.opacity(0.04)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(tab.shy ? Color(red: 0.78, green: 0.65, blue: 1.0).opacity(0.32) : Color.clear, lineWidth: 0.5)
            )
            .onHover { capsuleHovered = $0 }
        } else {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 15, height: 15)

                Button {
                    Haptics.tap()
                    browser.launch()
                } label: {
                    Text("Search or enter address")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .help("Search or enter address   ⌘L")
            }
            .padding(.leading, 7)
            .padding(.trailing, 3)
            .frame(minWidth: 170, maxWidth: 320, maxHeight: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(capsuleHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
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

// MARK: - Zen URL Toolbox Popover (Column / Zen Style)

struct UrlToolboxView: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    let onDismiss: () -> Void

    @State private var copiedLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1. Quick Actions Section
            VStack(alignment: .leading, spacing: 6) {
                Text("QUICK ACTIONS")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.muted)

                HStack(spacing: 6) {
                    // Share / Clean Copy
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

                    // Pin Tab
                    let isPinnedRow = tab.pin != nil && tab.listed
                    ToolboxPillButton(
                        icon: isPinnedRow ? "pin.fill" : "pin",
                        label: isPinnedRow ? "Pinned" : "Pin",
                        iconColor: isPinnedRow ? Color.accentColor : nil
                    ) {
                        Haptics.tap()
                        if isPinnedRow {
                            browser.unpin(tab)
                        } else {
                            browser.pin(tab, listed: true)
                        }
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
            }

            // 2. Extensions Section
            if #available(macOS 15.4, *) {
                let extensions = Extensions.shared
                if !extensions.installed.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("EXTENSIONS")
                            .font(.system(size: 9.5, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Palette.muted)

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
                                                .frame(width: 32, height: 32)
                                                .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                                                )
                                            Text(button.name)
                                                .font(.system(size: 9))
                                                .foregroundStyle(Palette.ink)
                                                .lineLimit(1)
                                                .frame(width: 48)
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
                                            .frame(width: 32, height: 32)
                                            .background(Palette.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                                            )
                                        Text("Manage")
                                            .font(.system(size: 9))
                                            .foregroundStyle(Palette.muted)
                                            .frame(width: 48)
                                    }
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .focusEffectDisabled()
                            }
                        }
                    }
                }
            }

            // 3. Page Controls Section
            VStack(alignment: .leading, spacing: 6) {
                Text("PAGE CONTROLS")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.muted)

                VStack(spacing: 4) {
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

                    // Standalone App Window Row
                    ToolboxSettingRow(
                        icon: "arrow.down.app",
                        title: "Install as Desktop App",
                        subtitle: "Installs to ~/Applications with shared sign-ins & Dock icon",
                        actionTitle: "Install"
                    ) {
                        Haptics.tap()
                        PWAInstaller.install(for: tab, browser: browser)
                        onDismiss()
                    }
                }
                .padding(6)
                .background(Palette.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
            }

            Divider().opacity(0.25)

            // 4. Bottom Bar: Security & Copy URL
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: tab.address?.scheme == "https" ? "lock.fill" : "globe")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tab.address?.scheme == "https" ? Palette.safe : Palette.muted)
                    Text(tab.address?.scheme == "https" ? "Secure Connection" : "Insecure")
                        .font(.system(size: 10.5, weight: .medium))
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
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
            }
        }
        .padding(12)
        .frame(width: 300)
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor ?? Palette.ink)
                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovered ? Palette.ink.opacity(0.08) : Palette.ink.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .animation(Motion.settle, value: hovered)
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
                    .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .medium))
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
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(isActive ? Color.accentColor.opacity(0.12) : Palette.ink.opacity(0.05), in: Capsule())
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(hovered ? Palette.ink.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .animation(Motion.settle, value: hovered)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .onHover { hovered = $0 }
    }
}

// MARK: - Native macOS Window Drag & Double-Click Zoom

struct WindowDragBar: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView {
        WindowDragNSView()
    }
    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

final class WindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}

// MARK: - Modern Site Security & Permissions Popover (Column / Zen Style)

struct SiteSecurityPopoverView: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    let close: () -> Void

    @State private var copiedAddress = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if tab.shy {
                HStack(spacing: 8) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.78, green: 0.65, blue: 1.0))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Private Browsing Tab")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 0.88, green: 0.80, blue: 1.0))
                        Text("Search won't save your browsing history, cookies, or site data once closed.")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(8)
                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.purple.opacity(0.25), lineWidth: 0.5))

                Divider().opacity(0.25)
            }

            // 1. Hero Connection Status Header
            headerSection

            Divider().opacity(0.25)

            // 2. Protection & Controls Group
            controlsSection

            // 3. Permissions Group
            permissionsSection

            Divider().opacity(0.25)

            // 4. Bottom Action Bar
            bottomSection
        }
        .padding(12)
        .frame(width: 300)
        .background(
            ZStack {
                VisualEffectView(material: .popover, blendingMode: .withinWindow)
                Palette.ground.opacity(0.92)
            }
        )
        .focusable(false)
        .focusEffectDisabled()
        .onAppear(perform: certify)
    }

    private var isSecure: Bool {
        tab.address?.scheme == "https"
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSecure ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSecure ? Palette.safe : Palette.unsafe)
                .frame(width: 30, height: 30)
                .background((isSecure ? Palette.safe : Palette.unsafe).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(isSecure ? "Connection is secure" : "Connection is not secure")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink)

                Text(isSecure
                     ? "Your connection is encrypted. Passwords, messages, and cards stay private."
                     : "This site is not encrypted. Don't enter sensitive info or passwords.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if let trust = tab.built?.serverTrust {
                    Button {
                        close()
                        DispatchQueue.main.async {
                            if let window = Links.window {
                                SFCertificatePanel.shared().beginSheet(
                                    for: window, modalDelegate: nil, didEnd: nil, contextInfo: nil, trust: trust, showGroup: false
                                )
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text("Certificate Details")
                                .font(.system(size: 10.5, weight: .medium))
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 8.5))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()
                    .padding(.top, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PROTECTION & CONTROLS")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.muted)

            VStack(spacing: 7) {
                // Shield / Ad blocker toggle
                if let url = tab.pageAddress, let host = browser.curtain.host(of: url) {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Shield.shared.isPaused(on: host) ? Palette.muted : Palette.safe)
                            .frame(width: 20, height: 20)
                            .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Block Ads & Trackers")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Palette.ink)
                            Text(Shield.shared.isPaused(on: host) ? "Paused for this site" : "Active protection")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Palette.muted)
                        }

                        Spacer()

                        Switch(on: Binding(
                            get: { !Shield.shared.isPaused(on: host) },
                            set: { on in
                                Shield.shared.pause(host, !on)
                                tab.reload()
                            }
                        ))
                    }
                }

                // Dark mode toggle for this site (fixed toggle with instant feedback)
                if browser.canDusk(tab) {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(tab.dusked ? Color.indigo : Palette.muted)
                            .frame(width: 20, height: 20)
                            .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Darken this site")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Palette.ink)
                            Text(tab.dusked ? "Applied dark theme" : "Default light appearance")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Palette.muted)
                        }

                        Spacer()

                        Switch(on: Binding(
                            get: { tab.dusked },
                            set: { on in
                                browser.dusk(on, tab)
                                if !on {
                                    tab.built?.evaluateInSearch("if (window.__officeDusk) { window.__officeDusk.force(false); window.__officeDusk.update({on:false}); }")
                                }
                            }
                        ))
                    }
                }

                // Zoom control row
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 20, height: 20)
                        .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                    Text("Zoom")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.ink)

                    Spacer()

                    HStack(spacing: 2) {
                        Button {
                            Haptics.tap()
                            browser.zoom(by: 1 / 1.1)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .focusEffectDisabled()

                        Button {
                            Haptics.tap()
                            browser.resetZoom()
                        } label: {
                            Text("\(Int((tab.zoom * 100).rounded()))%")
                                .font(.system(size: 10.5, weight: .medium))
                                .monospacedDigit()
                                .frame(width: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .focusEffectDisabled()

                        Button {
                            Haptics.tap()
                            browser.zoom(by: 1.1)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .focusEffectDisabled()
                    }
                    .padding(.horizontal, 2)
                    .background(Palette.ink.opacity(0.06), in: Capsule())
                }
            }
            .padding(8)
            .background(Palette.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
        }
    }

    @ViewBuilder
    private var permissionsSection: some View {
        if let url = tab.pageAddress, let scheme = url.scheme, let host = url.host() {
            let origin = Browser.origin(scheme, host, url.port ?? 0)
            VStack(alignment: .leading, spacing: 6) {
                Text("SITE PERMISSIONS")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.muted)

                VStack(spacing: 5) {
                    permissionRow(title: "Camera", icon: "video", kind: .camera, origin: origin)
                    permissionRow(title: "Microphone", icon: "mic", kind: .microphone, origin: origin)
                    permissionRow(title: "Location", icon: "location", kind: .location, origin: origin)
                    permissionRow(title: "Notifications", icon: "bell", kind: .notifications, origin: origin)
                }
                .padding(8)
                .background(Palette.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
            }
        }
    }

    private func permissionRow(title: String, icon: String, kind: CaptureChoices.Kind, origin: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.ink)
            Spacer()
            Menu {
                Button("Ask") { browser.setSitePermission(nil, kind: kind, origin: origin) }
                Button("Allow") { browser.setSitePermission(true, kind: kind, origin: origin) }
                    .disabled(kind == .notifications && !browser.prefs.siteNotifications)
                Button("Block") { browser.setSitePermission(false, kind: kind, origin: origin) }
            } label: {
                Text(CaptureChoices.choice(kind, origin: origin).title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .focusable(false)
            .focusEffectDisabled()
        }
    }

    private var bottomSection: some View {
        HStack {
            Text(tab.address?.host ?? "")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)

            Spacer()

            Button {
                Haptics.tap()
                if let url = tab.address {
                    CleanLink.copy(url)
                    copiedAddress = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedAddress = false }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: copiedAddress ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9.5))
                    Text(copiedAddress ? "Copied" : "Copy Clean URL")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
        }
    }

    private func certify() {
        guard let trust = tab.built?.serverTrust else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = SecTrustEvaluateWithError(trust, nil)
        }
    }
}
