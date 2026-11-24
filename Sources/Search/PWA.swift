import AppKit
import SwiftUI
import WebKit

/// Information about a Progressive Web App or standalone site.
struct PWAInfo: Equatable, Identifiable {
    var id: String { host }
    let name: String
    let host: String
    let startURL: URL
    let themeColorHex: String?
    let themeColor: NSColor?
    let hasManifest: Bool
    let isKnownApp: Bool
}

/// Helper methods for PWA detection, capability querying, and color parsing.
@MainActor
enum PWA {
    /// High-profile web apps with first-class desktop PWA experiences.
    static let knownHosts: [String: String] = [
        "outlook.office.com": "Outlook",
        "outlook.live.com": "Outlook",
        "outlook.cloud.microsoft": "Outlook",
        "github.com": "GitHub",
        "youtube.com": "YouTube",
        "music.youtube.com": "YouTube Music",
        "open.spotify.com": "Spotify",
        "discord.com": "Discord",
        "chatgpt.com": "ChatGPT",
        "chat.openai.com": "ChatGPT",
        "notion.so": "Notion",
        "linear.app": "Linear",
        "instagram.com": "Instagram",
        "web.whatsapp.com": "WhatsApp",
        "slack.com": "Slack",
        "teams.microsoft.com": "Teams",
        "app.slack.com": "Slack",
        "figma.com": "Figma",
        "notebook.google.com": "NotebookLM"
    ]

    /// Known brand theme colors for desktop web apps to ensure seamless, unified header blending.
    static let knownThemeColors: [String: String] = [
        "outlook.office.com": "#0078D4",
        "outlook.live.com": "#0078D4",
        "outlook.cloud.microsoft": "#0078D4",
        "github.com": "#010409",
        "youtube.com": "#0F0F0F",
        "music.youtube.com": "#030303",
        "open.spotify.com": "#121212",
        "discord.com": "#313338",
        "chatgpt.com": "#212121",
        "chat.openai.com": "#212121",
        "notion.so": "#191919",
        "linear.app": "#0F1015",
        "instagram.com": "#000000",
        "web.whatsapp.com": "#111B21",
        "slack.com": "#1A1D21",
        "teams.microsoft.com": "#1F1F1F",
        "app.slack.com": "#1A1D21",
        "figma.com": "#2C2C2C",
        "canvas": "#2D3B45"
    ]

    /// Resolves brand theme color for a URL.
    static func knownThemeColor(for url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        for (pattern, color) in knownThemeColors {
            if host == pattern || host.hasSuffix("." + pattern) {
                return color
            }
        }
        if host.contains("canvas.") || host.hasPrefix("canvas") {
            return knownThemeColors["canvas"]
        }
        return nil
    }

    /// Checks if a URL matches a known PWA or academic service (e.g., Canvas).
    static func knownApp(for url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        for (pattern, name) in knownHosts {
            if host == pattern || host.hasSuffix("." + pattern) {
                return name
            }
        }
        if host.contains("canvas.") || host.hasPrefix("canvas") {
            return "Canvas"
        }
        return nil
    }

    /// Determines whether a target URL is in-scope for a given PWA host.
    static func inScope(_ target: URL, host: String) -> Bool {
        guard let targetHost = target.host()?.lowercased() else { return false }
        let cleanHost = host.lowercased()
        // Same host or direct subdomain
        if targetHost == cleanHost || targetHost.hasSuffix("." + cleanHost) {
            return true
        }
        // Common authentication / SSO origins for web apps
        if cleanHost.contains("outlook") || cleanHost.contains("microsoft") {
            if targetHost.contains("login.microsoftonline.com")
                || targetHost.contains("login.live.com")
                || targetHost.contains("account.activedirectory.windowsazure.com") {
                return true
            }
        }
        if cleanHost.contains("github.com") {
            if targetHost == "github.githubassets.com" || targetHost == "api.github.com" {
                return true
            }
        }
        return false
    }

    /// Evaluates the DOM to detect manifest links, meta tags, and theme colors.
    static func detect(for tab: Tab) {
        guard let url = tab.address, let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host() else {
            tab.pwa = nil
            return
        }

        let knownName = knownApp(for: url)

        let script = """
        (function() {
            try {
                var m = document.querySelector('link[rel="manifest"]');
                var apple = document.querySelector('meta[name="apple-mobile-web-app-capable"]');
                var mobile = document.querySelector('meta[name="mobile-web-app-capable"]');
                var theme = document.querySelector('meta[name="theme-color"]');
                var appName = document.querySelector('meta[name="application-name"]');
                var hasPWA = !!m || (apple && apple.content === "yes") || (mobile && mobile.content === "yes");
                return {
                    hasManifest: !!m,
                    hasPWA: hasPWA,
                    themeColorHex: theme ? theme.content : null,
                    name: (appName && appName.content) ? appName.content : null
                };
            } catch(e) {
                return null;
            }
        })()
        """

        tab.built?.evaluateInSearch(script) { [weak tab] result in
            guard let tab else { return }
            MainActor.assumeIsolated {
                var hasManifest = false
                var hasPWA = false
                var themeHex: String? = nil
                var domName: String? = nil

                if let dict = result as? [String: Any] {
                    hasManifest = dict["hasManifest"] as? Bool ?? false
                    hasPWA = dict["hasPWA"] as? Bool ?? false
                    themeHex = dict["themeColorHex"] as? String
                    domName = dict["name"] as? String
                }

                let isKnown = knownName != nil
                if hasManifest || hasPWA || isKnown {
                    let finalName = knownName ?? domName ?? (tab.title.isEmpty ? SiteCard.site(url) : tab.title)
                    let resolvedHex = themeHex ?? knownThemeColor(for: url)
                    let nativeColor: NSColor?
                    if #available(macOS 12.0, *) {
                        nativeColor = tab.built?.themeColor ?? parseColor(hex: resolvedHex)
                    } else {
                        nativeColor = parseColor(hex: resolvedHex)
                    }

                    tab.pwa = PWAInfo(
                        name: finalName,
                        host: host,
                        startURL: url,
                        themeColorHex: resolvedHex,
                        themeColor: nativeColor,
                        hasManifest: hasManifest,
                        isKnownApp: isKnown
                    )
                } else {
                    tab.pwa = nil
                }
            }
        }
    }

    /// Parses hex or CSS rgb strings into NSColor.
    static func parseColor(hex: String?) -> NSColor? {
        guard var text = hex?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if text.hasPrefix("#") {
            text.removeFirst()
            var rgbValue: UInt64 = 0
            guard Scanner(string: text).scanHexInt64(&rgbValue) else { return nil }
            if text.count == 6 {
                let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
                let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
                let b = CGFloat(rgbValue & 0x0000FF) / 255.0
                return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
            } else if text.count == 3 {
                let r = CGFloat((rgbValue & 0xF00) >> 8) / 15.0
                let g = CGFloat((rgbValue & 0x0F0) >> 4) / 15.0
                let b = CGFloat(rgbValue & 0x00F) / 15.0
                return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
            }
        }
        return nil
    }
}
