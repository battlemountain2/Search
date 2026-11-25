import AppKit
import SwiftUI
import WebKit

// MARK: - PWA Configuration

struct PWAConfig: Codable {
    let name: String
    let host: String
    let startURL: URL
    let themeColorHex: String?
}

// MARK: - PWA Cookie Representation

struct PWACookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let isSecure: Bool
    let isHTTPOnly: Bool
    let expiresDate: Date?
    let sameSitePolicy: String?

    init(cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.isSecure = cookie.isSecure
        self.isHTTPOnly = cookie.isHTTPOnly
        self.expiresDate = cookie.expiresDate
        if #available(macOS 10.15, *) {
            self.sameSitePolicy = cookie.sameSitePolicy?.rawValue
        } else {
            self.sameSitePolicy = nil
        }
    }

    var httpCookie: HTTPCookie? {
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path.isEmpty ? "/" : path
        ]
        if isSecure { props[.secure] = "TRUE" }
        if isHTTPOnly { props[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let expiresDate = expiresDate { props[.expires] = expiresDate }
        if #available(macOS 10.15, *), let sameSitePolicy = sameSitePolicy {
            props[.sameSitePolicy] = HTTPCookieStringPolicy(rawValue: sameSitePolicy)
        }
        return HTTPCookie(properties: props)
    }
}

// MARK: - Action Router

final class PWAActionRouter: NSObject {
    static let shared = PWAActionRouter()
    weak var model: PWAWebViewModel?
}

// MARK: - Color Parsers

func parseHexColor(_ hex: String) -> NSColor? {
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

func parseCSSColor(_ string: String) -> NSColor? {
    let s = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if s.hasPrefix("#") {
        return parseHexColor(s)
    }
    if s.hasPrefix("rgb") {
        let nums = s.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        if nums.count >= 3,
           let r = Double(nums[0]),
           let g = Double(nums[1]),
           let b = Double(nums[2]) {
            return NSColor(srgbRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: 1.0)
        }
    }
    return nil
}

// MARK: - Main Application Delegate

@main
final class PWARunnerApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = PWARunnerApp()
        app.delegate = delegate
        app.run()
    }

    private var window: NSWindow!
    private var config: PWAConfig!

    private static let smallest = NSSize(width: 500, height: 400)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        loadConfig()
        setupMainMenu()
        buildWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Config Loading

    private func loadConfig() {
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
            let info = bundle.infoDictionary ?? [:]
            let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? "Web App"
            let startString = info["PWAStartURL"] as? String ?? "https://about:blank"
            let startURL = URL(string: startString) ?? URL(string: "https://about:blank")!
            let host = info["PWAHost"] as? String ?? (startURL.host ?? "")
            let color = info["PWAThemeColor"] as? String
            self.config = PWAConfig(name: name, host: host, startURL: startURL, themeColorHex: color)
        }

        // Support passing target URL as launch argument from Search
        if CommandLine.arguments.count > 1,
           let argURL = URL(string: CommandLine.arguments[1]),
           argURL.scheme == "http" || argURL.scheme == "https" {
            self.config = PWAConfig(name: self.config.name, host: self.config.host, startURL: argURL, themeColorHex: self.config.themeColorHex)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let target = urls.first {
            PWAActionRouter.shared.model?.load(url: target)
        }
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
        viewMenu.addItem(withTitle: "Reload", action: #selector(reloadAction), keyEquivalent: "r")
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

    // MARK: - Action Selectors

    @objc func reloadAction() { PWAActionRouter.shared.model?.reload() }
    @objc func forceReloadAction() { PWAActionRouter.shared.model?.reloadFromOrigin() }
    @objc func actualSizeAction() { PWAActionRouter.shared.model?.setZoom(1.0) }
    @objc func zoomInAction() { PWAActionRouter.shared.model?.zoomIn() }
    @objc func zoomOutAction() { PWAActionRouter.shared.model?.zoomOut() }

    // MARK: - Window Construction

    private func buildWindow() {
        let rect = NSRect(x: 0, y: 0, width: 1100, height: 780)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = config.name
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = Self.smallest
        window.delegate = self

        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true

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

        let rootView = PWARunnerRootView(config: config, window: window)
        window.contentView = NSHostingView(rootView: rootView)
        window.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async { [weak self] in
            self?.alignTrafficLights()
        }
    }

    // MARK: - Window Delegate

    func windowDidMove(_ notification: Notification) {
        saveFrame()
        alignTrafficLights()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveFrame()
        alignTrafficLights()
    }

    func windowDidResize(_ notification: Notification) {
        alignTrafficLights()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        alignTrafficLights()
    }

    func alignTrafficLights() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
        guard buttons.count == 3, let bar = buttons[0].superview, let container = bar.superview else { return }

        let targetCenterY: CGFloat = 17
        let height: CGFloat = 34
        var frame = container.frame
        if frame.height != height || frame.maxY != window.frame.height {
            frame.size.height = height
            frame.origin.y = window.frame.height - height
            container.frame = frame
        }

        let spacing: CGFloat = 20
        let startX: CGFloat = 18
        for (index, button) in buttons.enumerated() {
            let size = button.frame.size
            let origin = NSPoint(x: startX + CGFloat(index) * spacing,
                                 y: bar.bounds.height - targetCenterY - size.height / 2)
            button.setFrameOrigin(origin)
        }
    }

    private func saveFrame() {
        guard !window.styleMask.contains(.fullScreen) else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "pwa.frame." + config.host)
    }
}

// MARK: - SwiftUI Root View for Standalone PWA

struct PWARunnerRootView: View {
    let config: PWAConfig
    let window: NSWindow

    @StateObject private var model = PWAWebViewModel()
    @State private var edgeToEdge: Bool = false
    @State private var hoveringBack = false
    @State private var hoveringForward = false
    @State private var hoveringReload = false

    private var activeBackgroundColor: NSColor {
        if let pageColor = model.pageThemeColor {
            return pageColor
        }
        return NSColor.windowBackgroundColor
    }

    private var isDarkHeader: Bool {
        let color = activeBackgroundColor.usingColorSpace(.sRGB) ?? activeBackgroundColor
        let r = color.redComponent
        let g = color.greenComponent
        let b = color.blueComponent
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance < 0.65
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Web App View
            PWAWebViewRepresentable(model: model, startURL: config.startURL, host: config.host)
                .padding(.top, edgeToEdge ? 0 : 34)

            if !edgeToEdge {
                headerBar
                    .frame(height: 34)
            } else {
                floatingControls
            }
        }
        .onAppear {
            let host = config.host.isEmpty ? "default" : config.host
            edgeToEdge = UserDefaults.standard.bool(forKey: "pwa.edgetoedge." + host)
        }
        .onChange(of: model.pageThemeColor) { newColor in
            window.backgroundColor = newColor ?? .windowBackgroundColor
        }
        .ignoresSafeArea()
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            // Space for native macOS traffic lights (red, yellow, green)
            Spacer().frame(width: 76)

            // Back button
            Button {
                model.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(model.canGoBack ? (isDarkHeader ? Color.white : Color.primary) : (isDarkHeader ? Color.white.opacity(0.35) : Color.primary.opacity(0.25)))
                    .frame(width: 22, height: 22)
                    .background(hoveringBack && model.canGoBack ? (isDarkHeader ? Color.white.opacity(0.18) : Color.black.opacity(0.08)) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .disabled(!model.canGoBack)
            .onHover { hoveringBack = $0 }
            .help("Back (⌘[)")

            // Forward button
            Button {
                model.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(model.canGoForward ? (isDarkHeader ? Color.white : Color.primary) : (isDarkHeader ? Color.white.opacity(0.35) : Color.primary.opacity(0.25)))
                    .frame(width: 22, height: 22)
                    .background(hoveringForward && model.canGoForward ? (isDarkHeader ? Color.white.opacity(0.18) : Color.black.opacity(0.08)) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .disabled(!model.canGoForward)
            .onHover { hoveringForward = $0 }
            .help("Forward (⌘])")

            // Reload button
            Button {
                model.reload()
            } label: {
                Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(isDarkHeader ? Color.white.opacity(0.85) : Color.primary.opacity(0.75))
                    .frame(width: 22, height: 22)
                    .background(hoveringReload ? (isDarkHeader ? Color.white.opacity(0.18) : Color.black.opacity(0.08)) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .onHover { hoveringReload = $0 }
            .help("Reload (⌘R)")

            Spacer()

            // Options Menu Button
            Menu {
                Button(edgeToEdge ? "Show Title Bar" : "Full Edge-to-Edge Canvas") {
                    edgeToEdge.toggle()
                    UserDefaults.standard.set(edgeToEdge, forKey: "pwa.edgetoedge." + config.host)
                }
                Divider()
                Button("Copy Address") {
                    if let url = model.currentURL {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                }
                Button("Open in Default Browser (⌘O)") {
                    if let url = model.currentURL ?? config.startURL as URL? {
                        NSWorkspace.shared.open(url)
                    }
                }
                Divider()
                Button("Reload (⌘R)") { model.reload() }
                Button("Clear Site Cache & Reload") { model.reloadFromOrigin() }
                Divider()
                Button("Close Window (⌘W)") { window.performClose(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isDarkHeader ? Color.white.opacity(0.85) : Color.primary.opacity(0.75))
                    .frame(width: 24, height: 24)
                    .background(isDarkHeader ? Color.white.opacity(0.12) : Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24, height: 24)
            .help("App Options")
            .padding(.trailing, 10)
        }
        .padding(.horizontal, 4)
        .overlay(alignment: .center) {
            // True Mathematical Center - Clean title, NO capsule bubble
            Text(config.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isDarkHeader ? Color.white : Color.primary)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            if model.pageThemeColor == nil {
                Divider().opacity(0.35)
            }
        }
        .background(Color(nsColor: activeBackgroundColor))
    }

    // MARK: - Floating Controls (Edge-to-Edge Mode)

    private var floatingControls: some View {
        HStack {
            Spacer()
            Menu {
                Button("Show Title Bar") {
                    edgeToEdge = false
                    UserDefaults.standard.set(false, forKey: "pwa.edgetoedge." + config.host)
                }
                Divider()
                Button("Back (⌘[)") { model.goBack() }.disabled(!model.canGoBack)
                Button("Forward (⌘])") { model.goForward() }.disabled(!model.canGoForward)
                Button("Reload (⌘R)") { model.reload() }
                Divider()
                Button("Open in Default Browser (⌘O)") {
                    if let url = model.currentURL ?? config.startURL as URL? {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Close Window (⌘W)") { window.performClose(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22, height: 22)
            .padding(.trailing, 12)
            .padding(.top, 8)
        }
    }
}

// MARK: - WebViewModel

final class PWAWebViewModel: ObservableObject {
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var currentURL: URL?
    @Published var pageThemeColor: NSColor?

    weak var webView: WKWebView?

    init() {
        PWAActionRouter.shared.model = self
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func reloadFromOrigin() { webView?.reloadFromOrigin() }
    func load(url: URL) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        webView?.load(req)
    }
    func setZoom(_ zoom: Double) { webView?.pageZoom = zoom }
    func zoomIn() { if let z = webView?.pageZoom { webView?.pageZoom = z * 1.1 } }
    func zoomOut() { if let z = webView?.pageZoom { webView?.pageZoom = z / 1.1 } }
}

// MARK: - NSViewRepresentable for WKWebView

struct PWAWebViewRepresentable: NSViewRepresentable {
    @ObservedObject var model: PWAWebViewModel
    let startURL: URL
    let host: String

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, host: host)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let store = WKWebsiteDataStore.default()
        config.websiteDataStore = store
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // Enable 120Hz ProMotion smooth rendering
        Self.enable120HzProMotion(on: config.preferences)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        model.webView = webView

        injectCookiesAndLoad(store: store, webView: webView, startURL: startURL)
        return webView
    }

    private func loadCookiesIfNeeded() -> (cookies: [HTTPCookie], sourceDate: Date, bundleID: String)? {
        let fileManager = FileManager.default
        let cleanHost = host.filter { $0.isLetter || $0.isNumber || $0 == "." }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.battlemountain2.search.pwa.\(cleanHost)"

        var candidateURLs: [URL] = []

        let appSupport = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Search/PWA/\(bundleID)/Cookies.json")
        if fileManager.fileExists(atPath: appSupport.path) {
            candidateURLs.append(appSupport)
        }

        let hostSupport = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Search/PWA/\(cleanHost)/Cookies.json")
        if fileManager.fileExists(atPath: hostSupport.path) {
            candidateURLs.append(hostSupport)
        }

        if let bundleRes = Bundle.main.url(forResource: "Cookies", withExtension: "json") {
            candidateURLs.append(bundleRes)
        }

        guard let bestURL = candidateURLs.max(by: { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return date1 < date2
        }) else {
            return nil
        }

        let bestDate = (try? bestURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let lastImportedKey = "pwa.cookiesImportedAt.\(bundleID)"
        if let lastImported = UserDefaults.standard.object(forKey: lastImportedKey) as? Date,
           bestDate <= lastImported {
            // Already imported this snapshot; preserve newer session cookies inside WebKit's store
            return nil
        }

        guard let data = try? Data(contentsOf: bestURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let pwaCookies = try? decoder.decode([PWACookie].self, from: data) else { return nil }
        let httpCookies = pwaCookies.compactMap { $0.httpCookie }
        guard !httpCookies.isEmpty else { return nil }
        return (httpCookies, bestDate, bundleID)
    }

    private func injectCookiesAndLoad(store: WKWebsiteDataStore, webView: WKWebView, startURL: URL) {
        guard let pending = loadCookiesIfNeeded() else {
            var request = URLRequest(url: startURL)
            request.timeoutInterval = 30
            webView.load(request)
            return
        }

        let cookieStore = store.httpCookieStore
        let group = DispatchGroup()
        for cookie in pending.cookies {
            group.enter()
            cookieStore.setCookie(cookie) {
                group.leave()
            }
        }

        var didLoad = false
        func triggerLoad(markImported: Bool) {
            guard !didLoad else { return }
            didLoad = true
            if markImported {
                UserDefaults.standard.set(pending.sourceDate, forKey: "pwa.cookiesImportedAt.\(pending.bundleID)")
            }
            var request = URLRequest(url: startURL)
            request.timeoutInterval = 30
            webView.load(request)
        }

        group.notify(queue: .main) {
            triggerLoad(markImported: true)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            triggerLoad(markImported: false)
        }
    }

    private static func enable120HzProMotion(on preferences: WKPreferences) {
        let listSel = NSSelectorFromString("_features")
        let type: AnyObject = WKPreferences.self
        guard type.responds(to: listSel),
              let all = type.perform(listSel)?.takeUnretainedValue() as? [NSObject],
              let flag = all.first(where: { ($0.value(forKey: "key") as? String) == "PreferPageRenderingUpdatesNear60FPSEnabled" }) else { return }
        let setSel = NSSelectorFromString("_setEnabled:forFeature:")
        guard preferences.responds(to: setSel) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
        unsafeBitCast(preferences.method(for: setSel), to: Setter.self)(preferences, setSel, false, flag)
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: PWAWebViewModel
        let host: String

        init(model: PWAWebViewModel, host: String) {
            self.model = model
            self.host = host
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.canGoBack = webView.canGoBack
            model.canGoForward = webView.canGoForward
            model.isLoading = false
            model.currentURL = webView.url

            // Dynamic theme color sampling from WebKit
            if #available(macOS 12.0, *), let tc = webView.themeColor {
                model.pageThemeColor = tc
            } else {
                let js = """
                (function() {
                    let meta = document.querySelector('meta[name="theme-color"]');
                    if (meta && meta.content) return meta.content;
                    let header = document.querySelector('header') || document.querySelector('#o365header') || document.querySelector('.ms-Fabric');
                    if (header) {
                        let bg = window.getComputedStyle(header).backgroundColor;
                        if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') return bg;
                    }
                    return null;
                })()
                """
                webView.evaluateJavaScript(js) { [weak model] result, _ in
                    if let str = result as? String, let parsed = parseCSSColor(str) {
                        DispatchQueue.main.async {
                            model?.pageThemeColor = parsed
                        }
                    } else {
                        DispatchQueue.main.async {
                            model?.pageThemeColor = nil
                        }
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.isLoading = true
            if #available(macOS 12.0, *), let tc = webView.themeColor {
                model.pageThemeColor = tc
            } else {
                model.pageThemeColor = nil
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // In-scope stays in PWA; out-of-scope opens in default browser
            if navigationAction.navigationType == .linkActivated, navigationAction.targetFrame?.isMainFrame == true {
                if !inScope(url, host: host) {
                    decisionHandler(.cancel)
                    NSWorkspace.shared.open(url)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                if !inScope(url, host: host) {
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
            // Microsoft & Outlook SSO
            if cleanHost.contains("outlook") || cleanHost.contains("microsoft") {
                if targetHost.contains("login.microsoftonline.com")
                    || targetHost.contains("login.live.com")
                    || targetHost.contains("account.activedirectory.windowsazure.com")
                    || targetHost.contains("login.microsoft.com")
                    || targetHost.contains("mysignins.microsoft.com")
                    || targetHost.contains("microsoftonline.com")
                    || targetHost.contains("unm.edu") {
                    return true
                }
            }
            // Canvas SSO (UNM CAS / Shibboleth)
            if cleanHost.contains("canvas") {
                if targetHost.contains("unm.edu") || targetHost.contains("instructure.com") {
                    return true
                }
            }
            // Google Accounts SSO
            if cleanHost.contains("google.com") || cleanHost.contains("youtube.com") {
                if targetHost.contains("accounts.google.com") || targetHost.contains("google.com") || targetHost.contains("youtube.com") {
                    return true
                }
            }
            // Meta / Instagram SSO
            if cleanHost.contains("instagram.com") {
                if targetHost.contains("facebook.com") || targetHost.contains("instagram.com") {
                    return true
                }
            }
            if cleanHost.contains("github.com") && (targetHost == "github.githubassets.com" || targetHost == "api.github.com") {
                return true
            }
            return false
        }
    }
}
