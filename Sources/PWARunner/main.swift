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

// MARK: - Action Router

final class PWAActionRouter: NSObject {
    static let shared = PWAActionRouter()
    weak var model: PWAWebViewModel?
}

// MARK: - Color Parser

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

        // Seamless solid background to prevent awkward translucent seams
        if let hex = config.themeColorHex, let color = parseHexColor(hex) {
            window.backgroundColor = color
            window.isOpaque = true
        } else {
            window.backgroundColor = .windowBackgroundColor
            window.isOpaque = true
        }

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
                    .foregroundStyle(model.canGoBack ? Color.white : Color.white.opacity(0.35))
                    .frame(width: 22, height: 22)
                    .background(hoveringBack && model.canGoBack ? Color.white.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
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
                    .foregroundStyle(model.canGoForward ? Color.white : Color.white.opacity(0.35))
                    .frame(width: 22, height: 22)
                    .background(hoveringForward && model.canGoForward ? Color.white.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
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
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 22, height: 22)
                    .background(hoveringReload ? Color.white.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .onHover { hoveringReload = $0 }
            .help("Reload (⌘R)")

            Spacer(minLength: 0)

            // Title in center (App Name: "Outlook")
            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.75))
                Text(config.name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.12), in: Capsule())

            Spacer(minLength: 0)

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
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24, height: 24)
            .help("App Options")
            .padding(.trailing, 10)
        }
        .padding(.horizontal, 4)
        .background {
            if let hex = config.themeColorHex, let color = parseHexColor(hex) {
                Color(nsColor: color)
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
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

    weak var webView: WKWebView?

    init() {
        PWAActionRouter.shared.model = self
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func reloadFromOrigin() { webView?.reloadFromOrigin() }
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
        config.websiteDataStore = .default()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        model.webView = webView

        var request = URLRequest(url: startURL)
        request.timeoutInterval = 30
        webView.load(request)
        return webView
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
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.isLoading = true
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
