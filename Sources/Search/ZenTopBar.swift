import SwiftUI
import AppKit
import SecurityInterface

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
                    SiteSecurityPopoverView(browser: browser, tab: tab) {
                        showSiteCard = false
                    }
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

// MARK: - Modern Site Security & Permissions Popover (Clean Zen / Safari Style)

struct SiteSecurityPopoverView: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Status Badge + Domain + Certificate action
            headerSection

            Divider().opacity(0.3)

            // Permissions Group
            permissionsSection

            Divider().opacity(0.3)

            // Protection & Page Controls Group
            controlsSection
        }
        .padding(14)
        .frame(width: 290)
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
                .frame(width: 28, height: 28)
                .background((isSecure ? Palette.safe : Palette.unsafe).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(isSecure ? "Connection is secure" : "Connection is not secure")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink)

                Text(isSecure
                     ? "Your information (passwords, messages, cards) is private when sent to this site."
                     : "Don't enter sensitive info or passwords on this site.")
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
    private var permissionsSection: some View {
        if let url = tab.pageAddress, let scheme = url.scheme, let host = url.host() {
            let origin = Browser.origin(scheme, host, url.port ?? 0)
            VStack(alignment: .leading, spacing: 6) {
                Text("PERMISSIONS")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Palette.muted)

                VStack(spacing: 5) {
                    permissionRow(title: "Camera", icon: "video", kind: .camera, origin: origin)
                    permissionRow(title: "Microphone", icon: "mic", kind: .microphone, origin: origin)
                    permissionRow(title: "Location", icon: "location", kind: .location, origin: origin)
                    permissionRow(title: "Notifications", icon: "bell", kind: .notifications, origin: origin)
                }
                .padding(8)
                .background(Palette.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func permissionRow(title: String, icon: String, kind: CaptureChoices.Kind, origin: String) -> some View {
        HStack {
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
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.ink)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .focusable(false)
            .focusEffectDisabled()
        }
    }

    @ViewBuilder
    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PROTECTION & CONTROLS")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Palette.muted)

            VStack(spacing: 6) {
                // Shield / Ad blocker toggle
                if let url = tab.pageAddress, let host = browser.curtain.host(of: url) {
                    HStack {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 11))
                            .foregroundStyle(Shield.shared.isPaused(on: host) ? Palette.muted : Palette.safe)
                            .frame(width: 16)
                        Text("Block Ads & Trackers")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { !Shield.shared.isPaused(on: host) },
                            set: { on in
                                Shield.shared.pause(host, !on)
                                tab.reload()
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .scaleEffect(0.7)
                        .focusable(false)
                        .focusEffectDisabled()
                    }
                }

                // Dark mode toggle for this site
                if browser.canDusk(tab) {
                    HStack {
                        Image(systemName: "moon")
                            .font(.system(size: 11))
                            .foregroundStyle(tab.dusked ? Palette.safe : Palette.muted)
                            .frame(width: 16)
                        Text("Darken this site")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { tab.dusked },
                            set: { browser.dusk($0, tab) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .scaleEffect(0.7)
                        .focusable(false)
                        .focusEffectDisabled()
                    }
                }

                // Zoom control row
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 16)
                    Text("Zoom")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    HStack(spacing: 4) {
                        Button {
                            browser.zoom(by: 1 / 1.1)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 20, height: 20)
                                .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .focusEffectDisabled()

                        Button {
                            browser.resetZoom()
                        } label: {
                            Text("\(Int((tab.zoom * 100).rounded()))%")
                                .font(.system(size: 10.5, weight: .medium))
                                .monospacedDigit()
                                .frame(width: 38)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .focusEffectDisabled()

                        Button {
                            browser.zoom(by: 1.1)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 20, height: 20)
                                .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .focusEffectDisabled()
                    }
                }
            }
            .padding(8)
            .background(Palette.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func certify() {
        guard let trust = tab.built?.serverTrust else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = SecTrustEvaluateWithError(trust, nil)
        }
    }
}
