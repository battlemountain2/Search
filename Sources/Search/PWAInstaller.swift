import AppKit
import UniformTypeIdentifiers

/// Configuration written to `PWA.json` inside the installed app bundle.
struct PWAConfig: Codable {
    let name: String
    let host: String
    let startURL: URL
    let themeColorHex: String?
}

/// Structured cookie representation for cross-process session persistence.
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

/// Generates and installs first-class native macOS `.app` bundles for Progressive Web Apps.
/// Installs to `~/Applications/<AppName>.app`, registering with LaunchServices so the app
/// immediately appears in Spotlight, Raycast, Launcher, and the macOS Dock.
@MainActor
enum PWAInstaller {
    /// Installs the active tab's web app as a native macOS application bundle.
    @discardableResult
    static func install(for tab: Tab, browser: Browser? = nil) -> URL? {
        guard let pwa = tab.pwa ?? makeFallbackPWA(for: tab) else { return nil }

        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let userAppsDir = home.appendingPathComponent("Applications", isDirectory: true)

        try? fileManager.createDirectory(at: userAppsDir, withIntermediateDirectories: true)

        let safeName = sanitizeFilename(pwa.name)
        let appBundleURL = userAppsDir.appendingPathComponent("\(safeName).app", isDirectory: true)

        let contentsURL = appBundleURL.appendingPathComponent("Contents", isDirectory: true)
        let macosURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        do {
            if fileManager.fileExists(atPath: appBundleURL.path) {
                try fileManager.removeItem(at: appBundleURL)
            }

            try fileManager.createDirectory(at: macosURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

            // 1. Locate PWARunner executable
            guard let runnerSource = findPWARunnerSource() else {
                NSLog("[PWAInstaller] Could not locate PWARunner binary.")
                return nil
            }

            let destinationBinary = macosURL.appendingPathComponent(safeName)
            try fileManager.copyItem(at: runnerSource, to: destinationBinary)

            // Set executable permissions
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationBinary.path)

            // 2. Write PWA.json
            let pwaConfig = PWAConfig(
                name: pwa.name,
                host: pwa.host,
                startURL: pwa.startURL,
                themeColorHex: pwa.themeColorHex
            )
            let configData = try JSONEncoder().encode(pwaConfig)
            try configData.write(to: contentsURL.appendingPathComponent("PWA.json"))

            // 3. Write Info.plist
            let cleanHost = pwa.host.filter { $0.isLetter || $0.isNumber || $0 == "." }
            let bundleID = "com.battlemountain2.search.pwa.\(cleanHost)"
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>CFBundleName</key><string>\(pwa.name)</string>
                <key>CFBundleDisplayName</key><string>\(pwa.name)</string>
                <key>CFBundleIdentifier</key><string>\(bundleID)</string>
                <key>CFBundleVersion</key><string>1.0</string>
                <key>CFBundleShortVersionString</key><string>1.0</string>
                <key>CFBundlePackageType</key><string>APPL</string>
                <key>CFBundleExecutable</key><string>\(safeName)</string>
                <key>CFBundleIconFile</key><string>AppIcon</string>
                <key>LSMinimumSystemVersion</key><string>14.0</string>
                <key>NSHighResolutionCapable</key><true/>
                <key>PWAStartURL</key><string>\(pwa.startURL.absoluteString)</string>
                <key>PWAHost</key><string>\(pwa.host)</string>
                <key>PWAThemeColor</key><string>\(pwa.themeColorHex ?? "")</string>
            </dict>
            </plist>
            """
            try plistContent.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

            // 4. Generate AppIcon.icns
            let iconImage = Favicons.shared.cached(for: tab.address) ?? generateSquircleIcon(name: pwa.name, hex: pwa.themeColorHex)
            createIconFile(from: iconImage, at: resourcesURL.appendingPathComponent("AppIcon.icns"))

            // 5. Seed initial session data and cookies from Search
            let spaceID = Spaces.owner(of: tab.store) ?? browser?.space.id ?? Spaces.current
            seedSessionData(for: bundleID, spaceID: spaceID)

            // Asynchronously sync live cookies from the space, then sign and launch
            syncCookies(for: tab, appURL: appBundleURL, writeToBundle: true) {
                // 6. Ad-hoc codesign
                let signProcess = Process()
                signProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
                signProcess.arguments = ["--force", "--deep", "--sign", "-", appBundleURL.path]
                try? signProcess.run()
                signProcess.waitUntilExit()

                // 7. Register with LaunchServices
                let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
                if fileManager.fileExists(atPath: lsregisterPath) {
                    let lsProcess = Process()
                    lsProcess.executableURL = URL(fileURLWithPath: lsregisterPath)
                    lsProcess.arguments = ["-f", appBundleURL.path]
                    try? lsProcess.run()
                    lsProcess.waitUntilExit()
                }

                // 8. Launch newly installed app
                NSWorkspace.shared.openApplication(at: appBundleURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error {
                        NSLog("[PWAInstaller] Failed to launch installed app: \(error)")
                    }
                }

                // Notify UI once bundle is signed & registered
                tab.objectWillChange.send()
            }

            return appBundleURL
        } catch {
            NSLog("[PWAInstaller] Installation error: \(error)")
            return nil
        }
    }

    // MARK: - Installed Detection & Launching

    /// Checks if a dedicated desktop app is installed for the given tab or host.
    static func isInstalled(for tab: Tab) -> Bool {
        installedAppURL(for: tab) != nil
    }

    /// Resolves the installed app bundle URL on local disk if present.
    static func installedAppURL(for tab: Tab) -> URL? {
        guard let pwa = tab.pwa ?? makeFallbackPWA(for: tab) else { return nil }
        return installedAppURL(for: pwa)
    }

    /// Resolves the installed app bundle URL for a PWAInfo.
    static func installedAppURL(for pwa: PWAInfo) -> URL? {
        let fileManager = FileManager.default
        let safeName = sanitizeFilename(pwa.name)

        // 1. Check user ~/Applications directory
        let userApp = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/\(safeName).app")
        if fileManager.fileExists(atPath: userApp.path) {
            return userApp
        }

        // 2. Check system /Applications directory
        let sysApp = URL(fileURLWithPath: "/Applications/\(safeName).app")
        if fileManager.fileExists(atPath: sysApp.path) {
            return sysApp
        }

        // 3. Check LaunchServices for registered bundle ID
        let cleanHost = pwa.host.filter { $0.isLetter || $0.isNumber || $0 == "." }
        let bundleID = "com.battlemountain2.search.pwa.\(cleanHost)"
        if let registeredURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           fileManager.fileExists(atPath: registeredURL.path) {
            return registeredURL
        }

        return nil
    }

    /// Launches the installed desktop app, navigating to the current tab address if applicable.
    static func launch(for tab: Tab) {
        guard let appURL = installedAppURL(for: tab) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let currentURL = tab.address {
            config.arguments = [currentURL.absoluteString]
        }
        syncCookies(for: tab, appURL: appURL) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
                if let error {
                    NSLog("[PWAInstaller] Failed to launch application: \(error)")
                }
            }
        }
    }

    // MARK: - Cookie Synchronization

    /// Determines whether an HTTPCookie is relevant to a given host (including identity/SSO providers).
    static func isCookie(_ cookie: HTTPCookie, relevantTo host: String) -> Bool {
        let cookieDomain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let targetHost = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))

        // Direct subdomain or parent domain match
        if targetHost == cookieDomain || targetHost.hasSuffix("." + cookieDomain) || cookieDomain.hasSuffix("." + targetHost) {
            return true
        }

        // Match root domain (guarding against two-label ccTLDs like .co.uk, .com.au)
        let hostParts = targetHost.split(separator: ".")
        if hostParts.count >= 2 {
            let secondLevelSLDs: Set<Substring> = ["co", "com", "org", "net", "edu", "gov", "ac"]
            let isTwoPartTLD = hostParts.count >= 3
                && hostParts[hostParts.count - 1].count == 2
                && secondLevelSLDs.contains(hostParts[hostParts.count - 2])
            let labelCount = isTwoPartTLD ? 3 : 2
            let rootDomain = hostParts.suffix(labelCount).joined(separator: ".")
            if cookieDomain == rootDomain || cookieDomain.hasSuffix("." + rootDomain) {
                return true
            }
        }

        // Shared Google / YouTube Identity SSO
        if targetHost.contains("youtube.com") || targetHost.contains("google.com") {
            if cookieDomain.contains("youtube.com") || cookieDomain.contains("google.com") || cookieDomain.contains("googleusercontent.com") {
                return true
            }
        }

        // Microsoft / Outlook / Office SSO
        if targetHost.contains("outlook") || targetHost.contains("microsoft") || targetHost.contains("office") {
            if cookieDomain.contains("microsoft.com") || cookieDomain.contains("live.com") ||
               cookieDomain.contains("office.com") || cookieDomain.contains("office365.com") ||
               cookieDomain.contains("microsoftonline.com") || cookieDomain.contains("windowsazure.com") ||
               cookieDomain.contains("msftauth.net") || cookieDomain.contains("live.net") {
                return true
            }
        }

        // Canvas & Higher-Ed SSO
        if targetHost.contains("canvas") || targetHost.contains("instructure.com") {
            if cookieDomain.contains("instructure.com") || cookieDomain.contains("unm.edu") {
                return true
            }
        }

        // SoundCloud
        if targetHost.contains("soundcloud.com") && cookieDomain.contains("soundcloud.com") {
            return true
        }

        // Instagram / Meta SSO
        if targetHost.contains("instagram.com") {
            if cookieDomain.contains("instagram.com") || cookieDomain.contains("facebook.com") {
                return true
            }
        }

        return false
    }

    /// Asynchronously extracts relevant cookies from the tab's space store and writes them to the PWA app.
    static func syncCookies(for tab: Tab, appURL: URL? = nil, writeToBundle: Bool = false, completion: @escaping @MainActor () -> Void) {
        guard let host = tab.address?.host() ?? tab.pwa?.host else {
            completion()
            return
        }

        let cleanHost = host.filter { $0.isLetter || $0.isNumber || $0 == "." }
        let bundleID = "com.battlemountain2.search.pwa.\(cleanHost)"

        tab.store.httpCookieStore.getAllCookies { cookies in
            MainActor.assumeIsolated {
                let relevant = cookies.filter { isCookie($0, relevantTo: host) }
                let pwaCookies = relevant.map { PWACookie(cookie: $0) }

                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                encoder.dateEncodingStrategy = .iso8601

                if let data = try? encoder.encode(pwaCookies) {
                    let fileManager = FileManager.default

                    // 1. Write to Application Support/Search/PWA/<bundleID>/Cookies.json
                    let appSupportDir = fileManager.homeDirectoryForCurrentUser
                        .appendingPathComponent("Library/Application Support/Search/PWA/\(bundleID)", isDirectory: true)
                    try? fileManager.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
                    let appSupportFile = appSupportDir.appendingPathComponent("Cookies.json")
                    try? data.write(to: appSupportFile, options: .atomic)

                    // 2. Only write inside the .app bundle during install (before codesigning),
                    // so launching an existing app never invalidates its bundle signature.
                    if writeToBundle, let appURL = appURL ?? installedAppURL(for: tab) {
                        let resDir = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
                        try? fileManager.createDirectory(at: resDir, withIntermediateDirectories: true)
                        let resFile = resDir.appendingPathComponent("Cookies.json")
                        try? data.write(to: resFile, options: .atomic)
                    }
                }

                completion()
            }
        }
    }

    // MARK: - Session Seeding

    private static func seedSessionData(for bundleID: String, spaceID: UUID? = nil) {
        let fileManager = FileManager.default
        let library = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)

        let targetCookies = library.appendingPathComponent("HTTPStorages/\(bundleID).binarycookies")
        let targetData = library.appendingPathComponent("WebKit/\(bundleID)/WebsiteData")
        try? fileManager.createDirectory(at: targetData.appendingPathComponent("Default"), withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: targetData.appendingPathComponent("Origins"), withIntermediateDirectories: true)

        // Determine if the tab's space has its own dedicated data store (e.g. School space)
        var sourceCookies: URL?
        var sourceOrigins: URL?

        if let spaceID = spaceID {
            let spaceStoreDir = library.appendingPathComponent("WebKit/com.officecommun.search/WebsiteDataStore/\(spaceID.uuidString.lowercased())")
            let spaceCookieFile = spaceStoreDir.appendingPathComponent("Cookies/Cookies.binarycookies")
            if fileManager.fileExists(atPath: spaceCookieFile.path) {
                sourceCookies = spaceCookieFile
                sourceOrigins = spaceStoreDir.appendingPathComponent("Origins")
            }
        }

        // Fallback to default Personal space
        if sourceCookies == nil {
            let defaultCookieFile = library.appendingPathComponent("HTTPStorages/com.officecommun.search.binarycookies")
            if fileManager.fileExists(atPath: defaultCookieFile.path) {
                sourceCookies = defaultCookieFile
                sourceOrigins = library.appendingPathComponent("WebKit/com.officecommun.search/WebsiteData/Default")
            }
        }

        if let sourceCookies {
            try? fileManager.removeItem(at: targetCookies)
            try? fileManager.copyItem(at: sourceCookies, to: targetCookies)
        }

        if let sourceOrigins, fileManager.fileExists(atPath: sourceOrigins.path) {
            if let origins = try? fileManager.contentsOfDirectory(at: sourceOrigins, includingPropertiesForKeys: nil) {
                for item in origins {
                    let destDefault = targetData.appendingPathComponent("Default").appendingPathComponent(item.lastPathComponent)
                    let destOrigins = targetData.appendingPathComponent("Origins").appendingPathComponent(item.lastPathComponent)
                    try? fileManager.removeItem(at: destDefault)
                    try? fileManager.copyItem(at: item, to: destDefault)
                    try? fileManager.removeItem(at: destOrigins)
                    try? fileManager.copyItem(at: item, to: destOrigins)
                }
            }
        }
    }

    // MARK: - Binary Locator

    private static func findPWARunnerSource() -> URL? {
        let fileManager = FileManager.default

        // 1. Look inside Search.app/Contents/Resources/PWARunner
        if let inResources = Bundle.main.url(forResource: "PWARunner", withExtension: nil),
           fileManager.fileExists(atPath: inResources.path) {
            return inResources
        }

        // 2. Look relative to the running executable
        if let exec = Bundle.main.executableURL {
            let beside = exec.deletingLastPathComponent().appendingPathComponent("PWARunner")
            if fileManager.fileExists(atPath: beside.path) { return beside }

            let inRes = exec.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/PWARunner")
            if fileManager.fileExists(atPath: inRes.path) { return inRes }
        }

        // 3. Look in build folder (.build/out/Products/Release/PWARunner)
        let localBuild = URL(fileURLWithPath: "/Users/bry/.gemini/antigravity/scratch/Search/.build/out/Products/Release/PWARunner")
        if fileManager.fileExists(atPath: localBuild.path) {
            return localBuild
        }

        return nil
    }

    // MARK: - Fallback PWA Generator

    private static func makeFallbackPWA(for tab: Tab) -> PWAInfo? {
        guard let url = tab.address, let host = url.host() else { return nil }
        let known = PWA.knownApp(for: url)
        let name = known ?? (tab.title.isEmpty ? host : tab.title)
        let hex = PWA.knownThemeColor(for: url)
        let color = PWA.parseColor(hex: hex)
        return PWAInfo(
            name: name,
            host: host,
            startURL: url,
            themeColorHex: hex,
            themeColor: color,
            hasManifest: false,
            isKnownApp: known != nil
        )
    }

    private static func sanitizeFilename(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_()"))
        let cleaned = name.components(separatedBy: allowed.inverted).joined()
        return cleaned.isEmpty ? "Web App" : cleaned
    }

    // MARK: - Icon Generation

    private static func generateSquircleIcon(name: String, hex: String?) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()

        let bounds = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 24, dy: 24), xRadius: 104, yRadius: 104)

        let bg = hex.flatMap(PWA.parseColor(hex:)) ?? NSColor(srgbRed: 0.15, green: 0.15, blue: 0.18, alpha: 1.0)
        bg.setFill()
        path.fill()

        let letter = String(name.prefix(1)).uppercased()
        let font = NSFont.systemFont(ofSize: 240, weight: .bold)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: letter, attributes: textAttrs)
        let strSize = str.size()
        let textRect = NSRect(
            x: (size.width - strSize.width) / 2.0,
            y: (size.height - strSize.height) / 2.0 - 12,
            width: strSize.width,
            height: strSize.height
        )
        str.draw(in: textRect)

        image.unlockFocus()
        return image
    }

    private static func createIconFile(from image: NSImage, at destination: URL) {
        guard let tiffData = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData),
              let pngData = rep.representation(using: .png, properties: [:]) else { return }

        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let iconsetDir = tempDir.appendingPathComponent("AppIcon.iconset")

        try? fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let sizes: [(Int, Int, String)] = [
            (16, 1, "icon_16x16.png"),
            (16, 2, "icon_16x16@2x.png"),
            (32, 1, "icon_32x32.png"),
            (32, 2, "icon_32x32@2x.png"),
            (128, 1, "icon_128x128.png"),
            (128, 2, "icon_128x128@2x.png"),
            (256, 1, "icon_256x256.png"),
            (256, 2, "icon_256x256@2x.png"),
            (512, 1, "icon_512x512.png"),
            (512, 2, "icon_512x512@2x.png")
        ]

        for (pt, scale, filename) in sizes {
            let px = pt * scale
            let resized = NSImage(size: NSSize(width: px, height: px))
            resized.lockFocus()
            image.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .copy, fraction: 1.0)
            resized.unlockFocus()

            if let rTiff = resized.tiffRepresentation,
               let rRep = NSBitmapImageRep(data: rTiff),
               let rPng = rRep.representation(using: .png, properties: [:]) {
                try? rPng.write(to: iconsetDir.appendingPathComponent(filename))
            }
        }

        // Convert iconset to icns using iconutil
        let iconutil = Process()
        iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", destination.path]
        try? iconutil.run()
        iconutil.waitUntilExit()

        // Fallback: if iconutil fails in sandbox, write png representation directly
        if !fileManager.fileExists(atPath: destination.path) {
            try? pngData.write(to: destination)
        }
    }
}
