import Foundation

/// Unwraps known tracking/redirect wrapper URLs before navigation starts so
/// Search jumps straight to the clean destination URL.
enum RedirectBypass {
    static func unwrap(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return nil }

        let paramName: String?
        if host == "l.instagram.com" || host == "lm.facebook.com" || host == "l.facebook.com" {
            paramName = "u"
        } else if host == "www.youtube.com" && components.path == "/redirect" {
            paramName = "q"
        } else if (host == "www.google.com" || host.hasPrefix("www.google.")) && components.path == "/url" {
            paramName = items.contains(where: { $0.name == "q" }) ? "q" : "url"
        } else if host.hasSuffix(".safelinks.protection.outlook.com") {
            paramName = "url"
        } else if host == "out.reddit.com" {
            paramName = "url"
        } else {
            paramName = nil
        }

        guard let key = paramName,
              let raw = items.first(where: { $0.name == key })?.value,
              let target = URL(string: raw),
              let scheme = target.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              target != url else { return nil }

        return target
    }
}
