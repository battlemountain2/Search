import SwiftUI
import AppKit
import SecurityInterface

/// A compact, Zen-style floating navigation bar positioned above the web card.
/// Provides visible Back / Forward / Reload controls, an address capsule showing the domain,
/// and an integrated Page Actions & Settings toolbox popover (Zoom, Reader Mode, Split View, Extensions).
struct ZenTopBar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    var ground = RowGround.own

    static let height: CGFloat = 30

    @State private var capsuleHovered = false
    @State private var showToolbox = false
    @State private var showSiteCard = false
    @State private var capsuleFrame: CGRect = .zero
    @State private var inlineClicks: Any?
    @State private var navWidth: CGFloat = 76
    @State private var extWidth: CGFloat = 76

    var body: some View {
        ZStack {
            HStack(spacing: 6) {
                navigationControls
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { navWidth = $0 }
                Spacer(minLength: 0)
                pinnedExtensionsCluster
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { extWidth = $0 }
            }

            addressCapsule
                .padding(.horizontal, max(navWidth, extWidth) + 10)
        }
        .padding(.horizontal, ground == .card ? 8 : 6)
        .frame(height: ZenTopBar.height)
        .background(WindowDragBar())
        .background {
            if ground == .own, !browser.glassy {
                ZStack(alignment: .bottom) {
                    Palette.ground
                    SpaceWash(look: browser.wash)
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                }
            }
        }
        .animation(Motion.glide, value: browser.editingInline)
    }

    // MARK: - Navigation Controls

    @ViewBuilder
    private var navigationControls: some View {
        HStack(spacing: 2) {
            if browser.folded {
                ZenToolbarButton(
                    icon: prefs.sidePosition == .right ? "sidebar.right" : "sidebar.left",
                    help: "Show Sidebar   ⌘S"
                ) {
                    browser.toggleFold()
                }
            }

            if let tab = browser.active {
                let back = !tab.isBlank && tab.canGoBack
                let forward = !tab.isBlank && tab.canGoForward

                ZenToolbarButton(icon: "chevron.backward", disabled: !back, help: "Back   ⌘[") {
                    browser.back()
                }
                ZenToolbarButton(icon: "chevron.forward", disabled: !forward, help: "Forward   ⌘]") {
                    browser.forward()
                }
                ZenToolbarButton(
                    icon: tab.loading ? "xmark" : "arrow.clockwise",
                    help: tab.loading ? "Stop Loading   esc" : "Reload Page   ⌘R"
                ) {
                    if tab.loading {
                        tab.stop()
                    } else {
                        tab.reload()
                    }
                }
            } else {
                Color.clear.frame(width: 76, height: 24)
            }
        }
    }

    // MARK: - Address Capsule (Clean Office Commun / Zen Style)

    @ViewBuilder
    private var addressCapsule: some View {
        if let tab = browser.active {
            HStack(spacing: 6) {
                securityButton(for: tab)

                if tab.burner {
                    Text("BURNER")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.30))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.24), in: RoundedRectangle(cornerRadius: 3.5))
                } else if tab.shy {
                    Text("PRIVATE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.purple.opacity(0.95))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.18), in: RoundedRectangle(cornerRadius: 3.5))
                }

                // Domain text / inline address editor
                if browser.editingInline {
                    AddressField(browser: browser, size: 12)
                        .frame(maxWidth: .infinity)
                } else {
                    Button {
                        Haptics.tap()
                        if !browser.editing {
                            browser.edit()
                            browser.inlineEdit = true
                        }
                    } label: {
                        Text(displayDomain(for: tab))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(tab.isBlank ? Palette.muted : Palette.ink)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()
                    .help("Click to edit URL or search inline   ⌘L for floating")
                }

                if let pwa = tab.pwa {
                    pwaButton(for: tab, pwa: pwa)
                }

                // Zen-style Page Actions & Settings button (triggers URL toolbox popover)
                Button {
                    Haptics.tap()
                    showToolbox.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(showToolbox ? Color.accentColor : Palette.muted)
                        .frame(width: 19, height: 19)
                        .background(showToolbox ? Palette.ink.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
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
            .frame(minWidth: 180, maxWidth: browser.editingInline ? 460 : 380, maxHeight: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(capsuleFill(for: tab))
            )
            .overlay(alignment: .bottom) {
                if tab.loading {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.75))
                        .frame(height: 1.5)
                        .padding(.horizontal, 8)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(capsuleStroke(for: tab), lineWidth: 0.5)
            )
            .overlay {
                if !tab.shy && !tab.burner && !browser.editingInline {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            Palette.hairline.opacity(capsuleHovered || showToolbox ? 0.95 : 0.65),
                            lineWidth: 0.5
                        )
                        .allowsHitTesting(false)
                }
            }
            .animation(Motion.quick, value: capsuleHovered)
            .animation(Motion.quick, value: showToolbox)
            .animation(Motion.quick, value: tab.loading)
            .overlay(alignment: .topLeading) {
                if browser.editingInline {
                    Omnibox(browser: browser, over: false, listOnly: max(capsuleFrame.width, 360))
                        .offset(y: 28)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { capsuleFrame = $0 }
            .onChange(of: browser.editingInline, initial: true) { _, on in watchInlineClicks(on) }
            .onDisappear { watchInlineClicks(false) }
            .onHover { capsuleHovered = $0 }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 15, height: 15)

                if browser.editingInline {
                    AddressField(browser: browser, size: 12)
                        .frame(maxWidth: .infinity)
                } else {
                    Button {
                        Haptics.tap()
                        if !browser.editing {
                            browser.edit()
                            browser.inlineEdit = true
                        }
                    } label: {
                        Text("Search or enter address")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()
                    .help("Click to search inline   ⌘L for floating")
                }
            }
            .padding(.leading, 7)
            .padding(.trailing, 3)
            .frame(minWidth: 180, maxWidth: browser.editingInline ? 460 : 380, maxHeight: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(capsuleHovered || browser.editingInline ? Palette.ink.opacity(0.085) : Palette.ink.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        browser.editingInline ? Color.accentColor.opacity(0.45) : Palette.hairline.opacity(capsuleHovered ? 0.95 : 0.65),
                        lineWidth: 0.5
                    )
                    .allowsHitTesting(false)
            )
            .animation(Motion.quick, value: capsuleHovered)
            .overlay(alignment: .topLeading) {
                if browser.editingInline {
                    Omnibox(browser: browser, over: false, listOnly: max(capsuleFrame.width, 360))
                        .offset(y: 28)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { capsuleFrame = $0 }
            .onChange(of: browser.editingInline, initial: true) { _, on in watchInlineClicks(on) }
            .onDisappear { watchInlineClicks(false) }
            .onHover { capsuleHovered = $0 }
        }
    }

    private func displayDomain(for tab: Tab) -> String {
        if let host = tab.address?.host, !host.isEmpty {
            return host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        }
        return tab.title.isEmpty ? "Search or enter address" : tab.title
    }

    private func capsuleFill(for tab: Tab) -> Color {
        if tab.burner { return Color.orange.opacity(0.12) }
        if tab.shy { return Color.purple.opacity(0.12) }
        return (capsuleHovered || showToolbox || browser.editingInline) ? Palette.ink.opacity(0.085) : Palette.ink.opacity(0.045)
    }

    private func capsuleStroke(for tab: Tab) -> Color {
        if browser.editingInline { return Color.accentColor.opacity(0.45) }
        if tab.burner { return Color(red: 1.0, green: 0.62, blue: 0.16).opacity(0.36) }
        if tab.shy { return Color(red: 0.78, green: 0.65, blue: 1.0).opacity(0.32) }
        return .clear
    }

    private func watchInlineClicks(_ on: Bool) {
        if let inlineClicks { NSEvent.removeMonitor(inlineClicks) }
        inlineClicks = nil
        guard on else { return }
        inlineClicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            MainActor.assumeIsolated {
                guard browser.editingInline, let view = event.window?.contentView else { return }
                let at = event.locationInWindow
                let point = CGPoint(x: at.x, y: view.bounds.height - at.y)
                let below = browser.offers.isEmpty ? 0 : CGFloat(browser.offers.count) * 44 + 20
                let w = max(capsuleFrame.width, 340)
                let room = CGRect(x: capsuleFrame.minX, y: capsuleFrame.minY, width: w, height: capsuleFrame.height + below)
                guard !room.contains(point) else { return }
                browser.dismiss()
            }
            return event
        }
    }

    @ViewBuilder
    private func securityButton(for tab: Tab) -> some View {
        Button {
            Haptics.tap()
            showSiteCard.toggle()
        } label: {
            if tab.burner {
                Image(systemName: "flame.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.16))
                    .frame(width: 15, height: 15)
                    .background(showSiteCard ? Color.orange.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 3.5))
            } else if tab.shy {
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
                    .background(showSiteCard ? Palette.ink.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 3.5))
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .help(tab.burner ? "Burner Tab: isolated session inside this Space; wiped when closed"
              : (tab.shy ? "Private Browsing Session: no history, cookies, or cache are saved"
                 : "View site security, certificate & permissions"))
        .popover(isPresented: $showSiteCard, arrowEdge: .bottom) {
            SiteSecurityPopoverView(browser: browser, tab: tab) {
                showSiteCard = false
            }
        }
    }

    @ViewBuilder
    private func pwaButton(for tab: Tab, pwa: PWAInfo) -> some View {
        let isInstalled = PWAInstaller.isInstalled(for: tab)
        Button {
            Haptics.tap()
            if isInstalled {
                PWAInstaller.launch(for: tab)
            } else {
                PWAInstaller.install(for: tab, browser: browser)
            }
        } label: {
            Image(systemName: isInstalled ? "arrow.up.forward.app.fill" : "arrow.down.app")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(isInstalled ? Palette.ink.opacity(0.8) : Palette.muted)
                .frame(width: 17, height: 17)
                .background(Palette.ink.opacity(isInstalled ? 0.08 : 0.05), in: RoundedRectangle(cornerRadius: 3.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 3.5)
                        .strokeBorder(isInstalled ? Palette.hairline.opacity(0.75) : Color.clear, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .help(isInstalled ? "Open in \(pwa.name) (Desktop App)" : "Install \(pwa.name) as Desktop App")
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
        VStack(alignment: .leading, spacing: 0) {
            // 1. Quick Actions Row
            HStack(spacing: 4) {
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

                ToolboxPillButton(icon: "camera", label: "Capture") {
                    Haptics.click()
                    browser.toggleSnap()
                    onDismiss()
                }

                ToolboxPillButton(
                    icon: browser.veiling ? "eye.slash.fill" : "eye.slash",
                    label: "Hide",
                    isActive: browser.veiling
                ) {
                    Haptics.tap()
                    onDismiss()
                    DispatchQueue.main.async { browser.toggleHiding() }
                }

                let bookmarked = tab.address.map { browser.bookmarks.contains($0) } ?? false
                ToolboxPillButton(
                    icon: bookmarked ? "bookmark.fill" : "bookmark",
                    label: bookmarked ? "Saved" : "Save",
                    isActive: bookmarked
                ) {
                    Haptics.tap()
                    browser.bookmarks.toggle(tab)
                }
            }
            .padding(.horizontal, MenuMetrics.text - MenuMetrics.inset)
            .padding(.top, 6)
            .padding(.bottom, 6)

            // 2. Extensions Strip
            if #available(macOS 15.4, *) {
                let extensions = Extensions.shared
                if !extensions.installed.isEmpty {
                    PopoverSeparator()

                    PopoverSectionHeader(title: "Extensions")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(extensions.buttons) { button in
                                Button {
                                    Haptics.tap()
                                    extensions.press(button.id, in: browser)
                                    onDismiss()
                                } label: {
                                    VStack(spacing: 3) {
                                        ExtensionIcon(button: button, size: 16)
                                            .frame(width: 30, height: 30)
                                            .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        Text(button.name)
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color(nsColor: .labelColor))
                                            .lineLimit(1)
                                            .frame(width: 46)
                                    }
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .focusEffectDisabled()
                            }

                            Button {
                                Haptics.tap()
                                browser.lead(to: InternalPage(.settings, "extensions"))
                                onDismiss()
                            } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                                        .frame(width: 30, height: 30)
                                        .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    Text("Manage")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                                        .frame(width: 46)
                                }
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .focusEffectDisabled()
                        }
                        .padding(.horizontal, MenuMetrics.text)
                    }
                    .padding(.vertical, 4)
                }
            }

            PopoverSeparator()

            // 3. Page Controls (Office Commun MenuMetrics rows)
            PopoverZoomRow(browser: browser, tab: tab)

            PopoverMenuRow(
                title: tab.reader ? "Exit Reader View" : "Reader View",
                trailing: tab.reader ? "On" : nil
            ) {
                Haptics.tap()
                browser.toggleReader()
                onDismiss()
            }

            PopoverMenuRow(
                title: browser.prefs.splitView ? "Close Split View" : "Split View",
                trailing: browser.prefs.splitView ? "On" : nil
            ) {
                Haptics.click()
                browser.splitKey()
                onDismiss()
            }

            let isInstalled = PWAInstaller.isInstalled(for: tab)
            let pwaName = tab.pwa?.name ?? "Desktop App"
            PopoverMenuRow(
                title: isInstalled ? "Open in \(pwaName)" : "Install as Desktop App…",
                trailing: isInstalled ? "App" : nil
            ) {
                Haptics.tap()
                if isInstalled {
                    PWAInstaller.launch(for: tab)
                } else {
                    PWAInstaller.install(for: tab, browser: browser)
                }
                onDismiss()
            }

            if isInstalled {
                PopoverMenuRow(title: "Reinstall Desktop App…") {
                    Haptics.tap()
                    PWAInstaller.install(for: tab, browser: browser)
                    onDismiss()
                }
            }

            if !PWAInstaller.installedApps().isEmpty {
                PopoverMenuRow(title: "Refresh All Installed Apps") {
                    Haptics.tap()
                    let count = PWAInstaller.refreshInstalledApps()
                    browser.announce(count > 0 ? "Refreshed \(count) web app\(count == 1 ? "" : "s")" : "No installed web apps found")
                    onDismiss()
                }
            }

            PopoverSeparator()

            PopoverMenuRow(
                title: copiedLink ? "Copied Address" : "Copy Clean Address",
                trailing: "⌘L"
            ) {
                Haptics.tap()
                if let url = tab.address {
                    CleanLink.copy(url)
                } else {
                    browser.copyAddress()
                }
                copiedLink = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedLink = false }
            }
        }
        .padding(.vertical, MenuMetrics.pad)
        .frame(width: 268)
        .popoverGround()
    }
}

private struct ZenToolbarButton: View {
    let icon: String
    var disabled = false
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(disabled ? Palette.muted.opacity(0.35) : Palette.ink)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(!disabled && hovering ? Palette.ink.opacity(0.08) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .help(help)
    }
}

private struct ToolboxPillButton: View {
    let icon: String
    let label: String
    var iconColor: Color? = nil
    var isActive: Bool = false
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(iconColor ?? (isActive ? Color(nsColor: .labelColor) : Color(nsColor: .labelColor).opacity(0.85)))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(
                RoundedRectangle(cornerRadius: MenuMetrics.highlight, style: .continuous)
                    .fill(hovered ? Palette.ink.opacity(0.08) : (isActive ? Palette.ink.opacity(0.06) : Palette.ink.opacity(0.03)))
            )
            .animation(Motion.quick, value: hovered)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .onHover { hovered = $0 }
    }
}

private struct PopoverSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .lineLimit(1)
            .padding(.leading, MenuMetrics.text)
            .padding(.trailing, MenuMetrics.trailing)
            .frame(height: 20, alignment: .leading)
    }
}

private struct PopoverSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .padding(.horizontal, MenuMetrics.rule)
            .frame(height: MenuMetrics.separator)
    }
}

private struct PopoverMenuRow: View {
    let title: String
    var trailing: String? = nil
    var destructive: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(MenuMetrics.font)
                .foregroundStyle(hovering ? Color.white : (destructive ? Palette.unsafe : Color(nsColor: .labelColor)))
                .lineLimit(1)
            Spacer(minLength: 16)
            if let trailing {
                Text(trailing)
                    .font(MenuMetrics.font)
                    .foregroundStyle(hovering ? Color.white : Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
            }
        }
        .padding(.leading, MenuMetrics.text - MenuMetrics.inset)
        .padding(.trailing, MenuMetrics.trailing - MenuMetrics.inset)
        .frame(height: MenuMetrics.row)
        .background(
            RoundedRectangle(cornerRadius: MenuMetrics.highlight, style: .continuous)
                .fill(hovering ? MenuMetrics.selection : .clear)
        )
        .padding(.horizontal, MenuMetrics.inset)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
    }
}

private struct PopoverZoomRow: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab

    var body: some View {
        HStack(spacing: 0) {
            Text("Zoom")
                .font(MenuMetrics.font)
                .foregroundStyle(Color(nsColor: .labelColor))
            Spacer(minLength: 20)
            ZoomStepButton(symbol: "minus", help: "Zoom Out") {
                let snapped = ((tab.zoom * 10).rounded() / 10) - 0.1
                tab.magnify(to: max(0.4, snapped))
            }
            Button {
                Haptics.tap()
                browser.resetZoom()
            } label: {
                Text("\(Int((tab.zoom * 100).rounded()))%")
                    .font(MenuMetrics.font)
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(width: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .help("Actual Size")
            ZoomStepButton(symbol: "plus", help: "Zoom In") {
                let snapped = ((tab.zoom * 10).rounded() / 10) + 0.1
                tab.magnify(to: min(3.0, snapped))
            }
        }
        .padding(.leading, MenuMetrics.text)
        .padding(.trailing, MenuMetrics.inset + 4)
        .frame(height: MenuMetrics.row)
    }
}

private struct ZoomStepButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? Color.white : Color(nsColor: .labelColor))
                .frame(width: 22, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? MenuMetrics.selection : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .help(help)
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

// MARK: - Site Security & Permissions Popover (Office Commun Menu Style)

struct SiteSecurityPopoverView: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    let close: () -> Void

    @State private var copiedAddress = false

    private var hostTitle: String {
        if let host = tab.address?.host(), !host.isEmpty { return host }
        return tab.title.isEmpty ? "This Page" : tab.title
    }

    private var isSecure: Bool {
        tab.address?.scheme == "https"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopoverSectionHeader(title: hostTitle)

            // Connection Status
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: tab.shy ? "eye.slash" : (isSecure ? "lock" : "lock.open"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tab.shy ? Color.purple : (isSecure ? Palette.safe : Palette.unsafe))
                    .frame(width: 14, alignment: .center)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.shy ? "Private tab" : (isSecure ? "Connection is secure" : "Connection is not secure"))
                        .font(MenuMetrics.font)
                        .foregroundStyle(Color(nsColor: .labelColor))
                    Text(tab.shy
                         ? "History, cookies, and site data aren't saved once closed."
                         : (isSecure
                            ? "Your passwords and messages are private when sent to this site."
                            : "Don't enter passwords or sensitive info on this site."))
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, MenuMetrics.text)
            .padding(.trailing, MenuMetrics.trailing)
            .padding(.vertical, 6)

            if let trust = tab.built?.serverTrust {
                PopoverMenuRow(title: "Certificate Details…") {
                    close()
                    DispatchQueue.main.async {
                        if let window = Links.window {
                            SFCertificatePanel.shared().beginSheet(
                                for: window, modalDelegate: nil, didEnd: nil, contextInfo: nil, trust: trust, showGroup: false
                            )
                        }
                    }
                }
            }

            PopoverSeparator()

            if let url = tab.pageAddress, let host = browser.curtain.host(of: url) {
                HStack {
                    Text("Block Ads & Trackers")
                        .font(MenuMetrics.font)
                        .foregroundStyle(Color(nsColor: .labelColor))
                    Spacer(minLength: 20)
                    Switch(on: Binding(
                        get: { !Shield.shared.isPaused(on: host) },
                        set: { on in
                            Shield.shared.pause(host, !on)
                            tab.reload()
                        }
                    ))
                }
                .padding(.leading, MenuMetrics.text)
                .padding(.trailing, MenuMetrics.trailing)
                .frame(height: MenuMetrics.row)
            }

            if browser.canDusk(tab) {
                HStack {
                    Text("Darken This Site")
                        .font(MenuMetrics.font)
                        .foregroundStyle(Color(nsColor: .labelColor))
                    Spacer(minLength: 20)
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
                .padding(.leading, MenuMetrics.text)
                .padding(.trailing, MenuMetrics.trailing)
                .frame(height: MenuMetrics.row)
            }

            if tab.pageAddress?.host() != nil {
                HStack {
                    Text("Chrome Mask")
                        .font(MenuMetrics.font)
                        .foregroundStyle(Color(nsColor: .labelColor))
                    Spacer(minLength: 20)
                    Switch(on: Binding(
                        get: { ChromeMask.shared.isMasked(url: tab.pageAddress) },
                        set: { _ in
                            let nowMasked = ChromeMask.shared.toggle(for: tab.pageAddress)
                            tab.built?.customUserAgent = nowMasked ? ChromeMask.chromeUserAgent : nil
                            tab.reload(fromOrigin: true)
                        }
                    ))
                }
                .padding(.leading, MenuMetrics.text)
                .padding(.trailing, MenuMetrics.trailing)
                .frame(height: MenuMetrics.row)
            }

            if let url = tab.pageAddress, let scheme = url.scheme, let host = url.host() {
                let origin = Browser.origin(scheme, host, url.port ?? 0)
                PopoverSeparator()
                PopoverSectionHeader(title: "Permissions")
                permissionRow(title: "Camera", kind: .camera, origin: origin)
                permissionRow(title: "Microphone", kind: .microphone, origin: origin)
                permissionRow(title: "Location", kind: .location, origin: origin)
                permissionRow(title: "Notifications", kind: .notifications, origin: origin)
            }

            PopoverSeparator()

            PopoverMenuRow(title: copiedAddress ? "Copied Address" : "Copy Clean Address") {
                Haptics.tap()
                if let url = tab.address {
                    CleanLink.copy(url)
                    copiedAddress = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedAddress = false }
                }
            }

            if tab.pageAddress?.host()?.isEmpty == false {
                PopoverMenuRow(title: "Clear Cookies & Site Data", destructive: true) {
                    Haptics.click()
                    browser.clearSiteData(for: tab)
                    close()
                }
            }
        }
        .padding(.vertical, MenuMetrics.pad)
        .frame(width: 268)
        .popoverGround()
        .focusable(false)
        .focusEffectDisabled()
        .onAppear(perform: certify)
    }

    private func permissionRow(title: String, kind: CaptureChoices.Kind, origin: String) -> some View {
        HStack {
            Text(title)
                .font(MenuMetrics.font)
                .foregroundStyle(Color(nsColor: .labelColor))
            Spacer(minLength: 20)
            Menu {
                Button("Ask") { browser.setSitePermission(nil, kind: kind, origin: origin) }
                Button("Allow") { browser.setSitePermission(true, kind: kind, origin: origin) }
                    .disabled(kind == .notifications && !browser.prefs.siteNotifications)
                Button("Refuse") { browser.setSitePermission(false, kind: kind, origin: origin) }
            } label: {
                Text(CaptureChoices.choice(kind, origin: origin).title)
                    .font(MenuMetrics.font)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .focusable(false)
            .focusEffectDisabled()
        }
        .padding(.leading, MenuMetrics.text)
        .padding(.trailing, MenuMetrics.trailing)
        .frame(height: MenuMetrics.row)
    }

    private func certify() {
        guard let trust = tab.built?.serverTrust else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = SecTrustEvaluateWithError(trust, nil)
        }
    }
}
