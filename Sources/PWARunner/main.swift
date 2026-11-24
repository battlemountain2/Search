import AppKit
import WebKit

// MARK: - PWA Configuration

struct PWAConfig: Codable {
    let name: String
    let host: String
    let startURL: URL
    let themeColorHex: String?
}

// MARK: - Main Application Delegate

@main
final class PWARunnerApp: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = PWARunnerApp()
        app.delegate = delegate
        app.run()
    }

    private var window: NSWindow!
    private var webView: WKWebView!
    private var headerBar: NSView!
    private var titleLabel: NSTextField!
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var reloadButton: NSButton!
    private var config: PWAConfig!
    private var edgeToEdge: Bool = false

    private static let smallest = NSSize(width: 500, height: 400)

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadConfig()
        setupMainMenu()
        buildWindow()
        loadPage()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Config Loading

    private func loadConfig() {
        // Try locating PWA.json next to binary or in bundle resources
        let bundle = Bundle.main
        var data: Data?

        if let url = bundle.url(forResource: "PWA", withExtension: "json") {
            data = try? Data(contentsOf: url)
        } else {
            let execURL = URL(fileURLWithPath: CommandLine.arguments[0])
            let siblingURL = execURL.deletingLastPathComponent().appendingPathComponent("PWA.json")
            let parentURL = execURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PWA.json")
            data = (try? Data(contentsOf: siblingURL)) ?? (try? Data(contentsOf: parentURL))
        }

        if let data, let decoded = try? JSONDecoder().decode(PWAConfig.self, from: data) {
            self.config = decoded
        } else {
            // Fallback from Info.plist
            let info = bundle.infoDictionary ?? [:]
            let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? "Web App"
            let startString = info["PWAStartURL"] as? String ?? "https://about:blank"
            let startURL = URL(string: startString) ?? URL(string: "https://about:blank")!
            let host = info["PWAHost"] as? String ?? (startURL.host ?? "")
            let color = info["PWAThemeColor"] as? String
            self.config = PWAConfig(name: name, host: host, startURL: startURL, themeColorHex: color)
        }

        let savedEdge = UserDefaults.standard.bool(forKey: "pwa.edgetoedge." + config.host)
        self.edgeToEdge = savedEdge
    }

    // MARK: - Menu Setup

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        // App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(config.name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide \(config.name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit \(config.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit Menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // View Menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        let reload = NSMenuItem(title: "Reload", action: #selector(reloadAction), keyEquivalent: "r")
        viewMenu.addItem(reload)
        let hardReload = NSMenuItem(title: "Force Reload", action: #selector(forceReloadAction), keyEquivalent: "r")
        hardReload.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(hardReload)
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(actualSizeAction), keyEquivalent: "0")
        viewMenu.addItem(withTitle: "Zoom In", action: #selector(zoomInAction), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(zoomOutAction), keyEquivalent: "-")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")

        // Window Menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    }

    // MARK: - Window Construction

    private func buildWindow() {
        let rect = NSRect(x: 0, y: 0, width: 1080, height: 750)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = config.name
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.minSize = Self.smallest
        window.delegate = self

        // Restore frame
        if let frameString = UserDefaults.standard.string(forKey: "pwa.frame." + config.host) {
            let savedFrame = NSRectFromString(frameString)
            if savedFrame.width >= Self.smallest.width, savedFrame.height >= Self.smallest.height {
                window.setFrame(savedFrame, display: false)
            } else {
                window.center()
            }
        } else {
            window.center()
        }

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        // Configure WebKit with default persistent data store (shared with Search!)
        let webConfig = WKWebViewConfiguration()
        webConfig.websiteDataStore = .default()
        webConfig.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webConfig.defaultWebpagePreferences.allowsContentJavaScript = true

        let webFrame = NSRect(
            x: 0,
            y: 0,
            width: contentView.bounds.width,
            height: contentView.bounds.height - (edgeToEdge ? 0 : 32)
        )
        webView = WKWebView(frame: webFrame, configuration: webConfig)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        contentView.addSubview(webView)

        // Custom Header Bar (32pt)
        buildHeaderBar(in: contentView)

        updateLayout()
        window.makeKeyAndOrderFront(nil)
    }

    private func buildHeaderBar(in container: NSView) {
        let headerFrame = NSRect(x: 0, y: container.bounds.height - 32, width: container.bounds.width, height: 32)
        headerBar = NSView(frame: headerFrame)
        headerBar.autoresizingMask = [.width, .minYMargin]
        headerBar.wantsLayer = true

        applyHeaderBackground()

        // Space for native traffic lights is 0...72

        // Back button
        backButton = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")!, target: self, action: #selector(backAction))
        backButton.bezelStyle = .regularSquare
        backButton.isBordered = false
        backButton.frame = NSRect(x: 74, y: 6, width: 20, height: 20)
        backButton.toolTip = "Back (⌘[)"
        headerBar.addSubview(backButton)

        // Forward button
        forwardButton = NSButton(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")!, target: self, action: #selector(forwardAction))
        forwardButton.bezelStyle = .regularSquare
        forwardButton.isBordered = false
        forwardButton.frame = NSRect(x: 98, y: 6, width: 20, height: 20)
        forwardButton.toolTip = "Forward (⌘])"
        headerBar.addSubview(forwardButton)

        // Reload button
        reloadButton = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")!, target: self, action: #selector(reloadAction))
        reloadButton.bezelStyle = .regularSquare
        reloadButton.isBordered = false
        reloadButton.frame = NSRect(x: 122, y: 6, width: 20, height: 20)
        reloadButton.toolTip = "Reload (⌘R)"
        headerBar.addSubview(reloadButton)

        // App Title in Center
        titleLabel = NSTextField(labelWithString: config.name)
        titleLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 160, y: 6, width: container.bounds.width - 320, height: 20)
        titleLabel.autoresizingMask = [.width]
        headerBar.addSubview(titleLabel)

        // Options Menu Button on trailing edge
        let optionsButton = NSPopUpButton(frame: NSRect(x: container.bounds.width - 36, y: 6, width: 24, height: 20), pullsDown: true)
        optionsButton.autoresizingMask = [.minXMargin]
        optionsButton.bezelStyle = .regularSquare
        optionsButton.isBordered = false
        optionsButton.menu = makeOptionsMenu()
        headerBar.addSubview(optionsButton)

        container.addSubview(headerBar)
    }

    private func applyHeaderBackground() {
        guard let layer = headerBar.layer else { return }
        if let hex = config.themeColorHex, let color = parseColor(hex: hex) {
            layer.backgroundColor = color.cgColor
        } else {
            layer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
        }
    }

    private func makeOptionsMenu() -> NSMenu {
        let menu = NSMenu()
        let iconItem = NSMenuItem()
        iconItem.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Options")
        menu.addItem(iconItem)

        let edgeItem = NSMenuItem(title: edgeToEdge ? "Show Title Bar" : "Full Edge-to-Edge Canvas", action: #selector(toggleEdgeToEdge), keyEquivalent: "")
        edgeItem.target = self
        menu.addItem(edgeItem)

        menu.addItem(NSMenuItem.separator())

        let copyURLItem = NSMenuItem(title: "Copy Address", action: #selector(copyAddressAction), keyEquivalent: "")
        copyURLItem.target = self
        menu.addItem(copyURLItem)

        let openBrowserItem = NSMenuItem(title: "Open in Default Browser", action: #selector(openInDefaultBrowser), keyEquivalent: "o")
        openBrowserItem.target = self
        menu.addItem(openBrowserItem)

        menu.addItem(NSMenuItem.separator())

        let reloadItem = NSMenuItem(title: "Reload Page", action: #selector(reloadAction), keyEquivalent: "")
        reloadItem.target = self
        menu.addItem(reloadItem)

        let clearReloadItem = NSMenuItem(title: "Clear Cache & Reload", action: #selector(forceReloadAction), keyEquivalent: "")
        clearReloadItem.target = self
        menu.addItem(clearReloadItem)

        menu.addItem(NSMenuItem.separator())

        let closeItem = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "")
        menu.addItem(closeItem)

        return menu
    }

    private func updateLayout() {
        if edgeToEdge {
            headerBar.isHidden = true
            webView.frame = window.contentView!.bounds
        } else {
            headerBar.isHidden = false
            let height = window.contentView!.bounds.height
            let width = window.contentView!.bounds.width
            headerBar.frame = NSRect(x: 0, y: height - 32, width: width, height: 32)
            webView.frame = NSRect(x: 0, y: 0, width: width, height: height - 32)
        }
    }

    @objc private func toggleEdgeToEdge() {
        edgeToEdge.toggle()
        UserDefaults.standard.set(edgeToEdge, forKey: "pwa.edgetoedge." + config.host)
        updateLayout()
    }

    // MARK: - Actions

    @objc private func backAction() { if webView.canGoBack { webView.goBack() } }
    @objc private func forwardAction() { if webView.canGoForward { webView.goForward() } }
    @objc private func reloadAction() { webView.reload() }
    @objc private func forceReloadAction() { webView.reloadFromOrigin() }
    @objc private func actualSizeAction() { webView.pageZoom = 1.0 }
    @objc private func zoomInAction() { webView.pageZoom *= 1.1 }
    @objc private func zoomOutAction() { webView.pageZoom /= 1.1 }

    @objc private func copyAddressAction() {
        if let url = webView.url {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        }
    }

    @objc private func openInDefaultBrowser() {
        if let url = webView.url ?? config.startURL as URL? {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Page Loading

    private func loadPage() {
        var request = URLRequest(url: config.startURL)
        request.timeoutInterval = 30
        webView.load(request)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
        if let title = webView.title, !title.isEmpty {
            titleLabel.stringValue = title
            window.title = title
        }
        // Sample dynamic theme color if available
        if #available(macOS 12.0, *), let color = webView.themeColor {
            headerBar.layer?.backgroundColor = color.cgColor
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // External link trapping: out-of-scope links open in default browser
        if navigationAction.navigationType == .linkActivated, navigationAction.targetFrame?.isMainFrame == true {
            if !inScope(url, host: config.host) {
                decisionHandler(.cancel)
                NSWorkspace.shared.open(url)
                return
            }
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Popups: if external, open in browser; if internal, open in default browser or load in place
        if let url = navigationAction.request.url {
            if !inScope(url, host: config.host) {
                NSWorkspace.shared.open(url)
                return nil
            } else {
                webView.load(navigationAction.request)
                return nil
            }
        }
        return nil
    }

    private func inScope(_ target: URL, host: String) -> Bool {
        guard let targetHost = target.host?.lowercased() else { return false }
        let cleanHost = host.lowercased()
        if targetHost == cleanHost || targetHost.hasSuffix("." + cleanHost) {
            return true
        }
        // Authentication / SSO origins
        if cleanHost.contains("outlook") || cleanHost.contains("microsoft") {
            if targetHost.contains("login.microsoftonline.com") || targetHost.contains("login.live.com") {
                return true
            }
        }
        if cleanHost.contains("github.com") && (targetHost == "github.githubassets.com" || targetHost == "api.github.com") {
            return true
        }
        return false
    }

    // MARK: - Window Delegate

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveFrame()
    }

    private func saveFrame() {
        guard !window.styleMask.contains(.fullScreen) else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "pwa.frame." + config.host)
    }

    // MARK: - Color Helper

    private func parseColor(hex: String) -> NSColor? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        var rgbValue: UInt64 = 0
        guard Scanner(string: text).scanHexInt64(&rgbValue) else { return nil }
        if text.count == 6 {
            let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
            let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
            let b = CGFloat(rgbValue & 0x0000FF) / 255.0
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
        }
        return nil
    }
}
