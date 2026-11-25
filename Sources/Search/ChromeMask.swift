import Foundation

/// Per-host User-Agent mask so sites that refuse Safari/WebKit render with a
/// clean Chrome desktop User-Agent without affecting the rest of your browsing.
@MainActor
final class ChromeMask: ObservableObject {
    static let shared = ChromeMask()

    static let chromeUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
    private let key = "privacy.chromeMaskHosts"

    @Published private(set) var hosts: Set<String>

    private init() {
        let saved = Store.settings.stringArray(forKey: key) ?? []
        hosts = Set(saved.map { $0.lowercased() })
    }

    static func normalizedHost(_ url: URL?) -> String? {
        guard let raw = url?.host?.lowercased(), !raw.isEmpty else { return nil }
        return raw.hasPrefix("www.") ? String(raw.dropFirst(4)) : raw
    }

    func isMasked(url: URL?) -> Bool {
        guard let host = Self.normalizedHost(url) else { return false }
        return hosts.contains(host)
    }

    func toggle(for url: URL?) -> Bool {
        guard let host = Self.normalizedHost(url) else { return false }
        if hosts.contains(host) {
            hosts.remove(host)
        } else {
            hosts.insert(host)
        }
        Store.settings.set(Array(hosts).sorted(), forKey: key)
        return hosts.contains(host)
    }

    func clearAll() {
        hosts.removeAll()
        Store.settings.removeObject(forKey: key)
    }
}
