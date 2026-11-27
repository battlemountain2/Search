import Foundation
import SwiftUI

// The address field doubles as the most basic kind of command line: a
// handful of words that mean "go here in the app" rather than "go here on
// the web". Only the whole word runs on Return, so a search that starts
// with one still searches; part of a word is just offered lower in the
// list. On unless turned off (Settings › Spaces & Pins › Opening and
// starting › Address bar commands), since 25 Nov 2026 (Drice): whoever
// wants "settings" alone sent to their search engine turns it off.
//
// With it on, every menu command (Shortcuts.swift's Command) is offered
// too, as in Arc's Command Bar, found by the words of its name, and every
// Settings page by its name: under what was typed, so Return still goes
// where it went, and run through the menu's own action.

@MainActor
enum AddressCommand: Equatable {
    case settings
    case newTab
    case newPrivateTab
    case newSpace
    case bookmarks
    case history
    case downloads
    case passwords
    case toggleSidebar
    /// Open a specific Library drawer section (`Downloads`, `Media`, `Bookmarks`, `History`, `Spaces`, `Extensions`).
    case library(LibrarySection)
    /// Switch directly to a Space by UUID + name.
    case space(UUID, String)
    /// Launch existing desktop PWA for current tab, or install it as a standalone macOS `.app`.
    case pwaAction
    /// Sync PWARunner binary, cookies, and code signature across all installed web apps.
    case refreshPWAs
    /// Toggle Dynamic Mode top bar (`zenTopBar`) / borderless web canvas (`zenBorderless`).
    case toggleDynamicBar
    case toggleBorderless
    /// A menu command, by its id in Command.all.
    case menu(String)
    /// A Settings page, opened on that page.
    case page(SettingsPanel.Page)

    /// The words, which run on Return when typed whole.
    static let allCases: [AddressCommand] = [
        .settings, .newTab, .newPrivateTab, .newSpace, .bookmarks, .history, .downloads, .passwords, .toggleSidebar,
        .library(.downloads), .library(.media), .library(.bookmarks), .library(.history), .library(.spaces), .library(.extensions),
        .pwaAction, .refreshPWAs, .toggleDynamicBar, .toggleBorderless,
    ]

    /// What you'd type to reach it. The first is what the list shows.
    var aliases: [String] {
        switch self {
        case .settings: return ["settings", "preferences"]
        case .newTab: return ["new tab"]
        case .newPrivateTab: return ["new private tab", "private tab"]
        case .newSpace: return ["new space"]
        case .bookmarks: return ["bookmarks"]
        case .history: return ["history"]
        case .downloads: return ["downloads"]
        case .passwords: return ["passwords"]
        case .toggleSidebar: return ["toggle sidebar", "sidebar"]
        case .library(let section): return ["\(section.title) Library", "library \(section.title.lowercased())", section.title.lowercased()]
        case .space(_, let name): return ["Space: \(name)", "switch to \(name.lowercased())", name.lowercased()]
        case .pwaAction: return ["Open or Install as App", "install app", "pwa", "desktop app"]
        case .refreshPWAs: return ["Refresh Installed Web Apps", "refresh pwa", "sync web apps"]
        case .toggleDynamicBar: return ["Toggle Dynamic Top Bar", "dynamic mode", "top bar"]
        case .toggleBorderless: return ["Toggle Borderless Canvas", "borderless"]
        case .menu(let id): return [Command.named(id)?.title ?? id]
        case .page(let page): return ["\(page.title) Settings"]
        }
    }

    var title: String {
        switch self {
        case .menu, .page, .library, .space, .pwaAction, .refreshPWAs, .toggleDynamicBar, .toggleBorderless:
            return aliases[0]
        default:
            return aliases[0].localizedCapitalized
        }
    }

    var subtitle: String {
        switch self {
        case .library: return "Library"
        case .space: return "Space"
        case .pwaAction, .refreshPWAs: return "Desktop App"
        case .toggleDynamicBar, .toggleBorderless: return "Appearance"
        case .page: return "Settings"
        default: return ""
        }
    }

    var symbolName: String {
        switch self {
        case .library(let section): return section.icon
        case .space: return "square.stack"
        case .pwaAction, .refreshPWAs: return "arrow.up.forward.app"
        case .toggleDynamicBar, .toggleBorderless: return "menubar.rectangle"
        default: return "command"
        }
    }

    /// The menu command that does the same, whose key the row shows.
    var commandID: String? {
        switch self {
        case .settings: return "app.settings"
        case .newTab: return "file.newTab"
        case .newPrivateTab: return "file.newPrivateTab"
        case .bookmarks: return "bookmarks.show"
        case .history: return "history.show"
        case .downloads: return "history.downloads"
        case .passwords: return "app.passwords"
        case .toggleSidebar: return "view.sidebar"
        case .menu(let id): return id
        case .newSpace, .page, .library, .space, .pwaAction, .refreshPWAs, .toggleDynamicBar, .toggleBorderless: return nil
        }
    }

    /// Its key as it stands, as the menu writes it: "⇧⌘N".
    var key: String? { commandID.flatMap { ShortcutStore.shared.key(for: $0)?.display } }

    /// Some only mean something once the feature behind them is even on.
    func available(in browser: Browser) -> Bool {
        switch self {
        case .newSpace, .space: return browser.prefs.usesSpaces
        case .pwaAction: return browser.active?.isWeb == true && browser.active?.address != nil
        case .refreshPWAs: return !PWAInstaller.installedApps().isEmpty
        case .menu(let id): return Self.offers(id, in: browser)
        case .page(let page): return page != .ai || AI.shipped
        default: return true
        }
    }

    func run(on browser: Browser) {
        switch self {
        case .settings: browser.tuning = true
        case .newTab: browser.newTab()
        case .newPrivateTab: browser.newShyTab()
        case .newSpace: browser.askForSpace()
        case .bookmarks: browser.bookmarking = true
        case .history: browser.recalling = true
        case .downloads: browser.showDownloads()
        case .passwords: browser.managing = true
        case .toggleSidebar: browser.toggleSidebar()
        case .library(let section):
            if browser.folded { browser.toggleFold() }
            withAnimation(Motion.glide) {
                browser.librarySection = section
            }
        case .space(let id, _):
            browser.switchSpace(to: id)
        case .pwaAction:
            guard let tab = browser.active else { return }
            if PWAInstaller.isInstalled(for: tab) {
                PWAInstaller.launch(for: tab)
            } else {
                PWAInstaller.install(for: tab, browser: browser)
            }
        case .refreshPWAs:
            let count = PWAInstaller.refreshInstalledApps()
            browser.announce(count > 0 ? "Refreshed \(count) web app\(count == 1 ? "" : "s")" : "No installed web apps found")
        case .toggleDynamicBar:
            withAnimation(Motion.glide) { browser.prefs.zenTopBar.toggle() }
        case .toggleBorderless:
            withAnimation(Motion.glide) { browser.prefs.zenBorderless.toggle() }
        case .menu(let id): Command.named(id)?.run(browser)
        case .page(let page):
            browser.settingsPage = page
            browser.tuning = true
        }
    }

    /// The command whose words are all that was typed, if any. Only the
    /// whole thing: a command must not take a search from anyone, so
    /// "settings for gmail" or "sett" still searches.
    static func matching(_ typed: String, in browser: Browser) -> AddressCommand? {
        let needle = typed.trimmingCharacters(in: .whitespaces).lowercased()
        return allCases.first { $0.available(in: browser) && $0.aliases.contains(needle) }
    }

    /// A command that partly matches: "down", "dwn" or "downlaods" for
    /// Downloads. From three letters, and only offered, never run on Return.
    static func near(_ typed: String, in browser: Browser) -> AddressCommand? {
        let needle = typed.trimmingCharacters(in: .whitespaces).lowercased()
        guard needle.count >= 3, matching(needle, in: browser) == nil else { return nil }
        let letters = Array(needle.utf8)
        let available = allCases.filter { $0.available(in: browser) }
        // Closest match first, then the order above.
        let tests: [(String) -> Bool] = [
            { $0.hasPrefix(needle) || $0.split(separator: " ").contains { $0.hasPrefix(needle) } },
            { $0.split(separator: " ").contains { Fuzzy.abbreviates(needle, $0) } },
            { Fuzzy.nearly(letters, in: $0) },
        ]
        for test in tests {
            if let found = available.first(where: { $0.aliases.contains(where: test) }) { return found }
        }
        return nil
    }

    /// Menu commands that make no sense from the field: it is already open,
    /// there is nothing found to step through, or the key must be held.
    private static let unoffered: Set<String> = [
        "file.openAddress", "edit.findNext", "edit.findPrevious", Command.recentTabs, "tabs.search",
    ]
    /// Those the menu greys out without a web page in front.
    private static let needsPage: Set<String> = [
        "file.share", "file.savePage", "file.exportPDF", "file.print", "edit.copyCleanLink", "view.reader",
        "view.summarize", "view.ask", "tabs.duplicate", "tabs.copyAddress", "tabs.copyMarkdown", "bookmarks.add",
        "view.style",
    ]
    /// More words for a few, the ones other browsers use.
    private static let alsoCalled: [String: String] = [
        "view.reader": "reader view", "tabs.mute": "mute", "view.float": "picture in picture pip",
        "view.inspector": "devtools developer tools", "bookmarks.add": "bookmark", "view.hide": "zapper",
        "view.style": "boost css",
    ]

    /// A menu command, offered only where the menu has it, and enabled.
    private static func offers(_ id: String, in browser: Browser) -> Bool {
        guard let command = Command.named(id), !unoffered.contains(id) else { return false }
        let prefs = browser.prefs
        if command.section == .spaces, !prefs.usesSpaces { return false }
        if command.section == .profiles, !Profiles.shared.several { return false }
        if Command.split.contains(id) {
            guard prefs.splitView else { return false }
            if id != "tabs.split", browser.activeSplit == nil { return false }
        }
        if Command.ai.contains(id), !prefs.ai { return false }
        if Command.dusk.contains(id), !prefs.darkensPages { return false }
        if Command.archive.contains(id), prefs.tabLife == .never { return false }
        if Command.capture.contains(id), !prefs.capturesPages { return false }
        if Command.styles.contains(id), !prefs.sitesStyles || browser.active?.shy == true { return false }
        if id == "view.sitePanel", !prefs.sitesInPanel { return false }
        if id == "tabs.pinRow", !prefs.showsPinRows { return false }
        if id == "view.foldGroups", !browser.canFoldAllGroups { return false }
        if id == "view.unfoldGroups", !browser.canUnfoldAllGroups { return false }
        if needsPage.contains(id), browser.active?.isWeb != true { return false }
        return true
    }

    /// Menu commands and Settings pages every typed word begins a word of,
    /// in any order: "priv tab" for New Private Tab, "hide el" for Hide
    /// Elements…, "appear" for Appearance Settings. Those whose name starts
    /// with what was typed first, then the menus' order; never a command
    /// one of the words above already stands for. From three letters, and
    /// never for an address.
    static func listed(_ typed: String, in browser: Browser, limit: Int = 4) -> [AddressCommand] {
        let needle = typed.trimmingCharacters(in: .whitespaces).lowercased()
        guard needle.count >= 3, Address.url(from: needle) == nil else { return [] }
        let asked = needle.split(separator: " ")
        let taken = Set([matching(needle, in: browser), near(needle, in: browser)].compactMap { $0?.commandID })
        let candidates = Command.all.map { AddressCommand.menu($0.id) }
            + SettingsPanel.Page.allCases.map { AddressCommand.page($0) }
        var first: [AddressCommand] = [], rest: [AddressCommand] = []
        for candidate in candidates {
            if let id = candidate.commandID, taken.contains(id) { continue }
            let name = candidate.title.lowercased().replacingOccurrences(of: "…", with: "")
            let extra = candidate.commandID.flatMap { alsoCalled[$0] } ?? ""
            let words = (name + " " + extra).split(separator: " ")
            guard asked.allSatisfy({ typed in words.contains { $0.hasPrefix(typed) } }),
                  candidate.available(in: browser) else { continue }
            if name.hasPrefix(needle) { first.append(candidate) } else { rest.append(candidate) }
        }
        return Array((first + rest).prefix(limit))
    }

    /// True `⌘K` Command Palette items: Library drawers, Space switching,
    /// desktop PWA actions, UI toggles, menu actions, and Settings sections.
    static func paletteOffers(_ typed: String, in browser: Browser, limit: Int = 8) -> [Suggestion] {
        let needle = typed.trimmingCharacters(in: .whitespaces).lowercased()
        let placeholderURL = URL(string: "search://command")!
        func row(_ cmd: AddressCommand, subtitle: String? = nil) -> Suggestion {
            Suggestion(
                key: cmd.title,
                title: subtitle ?? cmd.subtitle,
                url: placeholderURL,
                kind: .command(cmd)
            )
        }

        if needle.isEmpty {
            var defaults: [AddressCommand] = [
                .library(.media),
                .library(.bookmarks),
                .library(.downloads),
                .library(.history),
                .pwaAction,
                .toggleDynamicBar,
                .toggleSidebar,
                .settings,
            ]
            if browser.prefs.usesSpaces {
                let otherSpaces = browser.spaces
                    .filter { $0.id != browser.space.id }
                    .prefix(3)
                    .map { AddressCommand.space($0.id, $0.name) }
                defaults.insert(contentsOf: otherSpaces, at: min(1, defaults.count))
            }
            return defaults
                .filter { $0.available(in: browser) }
                .prefix(limit)
                .map { row($0) }
        }

        let words = needle.split(whereSeparator: \.isWhitespace).map(String.init)
        var pool: [(cmd: AddressCommand, haystack: String, exactStart: Bool)] = []

        // 1. Dynamic Spaces
        if browser.prefs.usesSpaces {
            for space in browser.spaces where space.id != browser.space.id {
                let cmd = AddressCommand.space(space.id, space.name)
                let hay = "space \(space.name.lowercased()) switch"
                pool.append((cmd, hay, space.name.lowercased().hasPrefix(needle)))
            }
        }

        // 2. Built-in & fork AddressCommands
        for cmd in allCases where cmd.available(in: browser) {
            let hay = (cmd.aliases + [cmd.subtitle]).joined(separator: " ").lowercased()
            pool.append((cmd, hay, cmd.title.lowercased().hasPrefix(needle)))
        }

        // 3. Menu commands & Settings pages
        for id in Command.all.map(\.id) {
            let cmd = AddressCommand.menu(id)
            guard cmd.available(in: browser) else { continue }
            let extra = alsoCalled[id] ?? ""
            let hay = "\(cmd.title.lowercased()) \(extra)"
            pool.append((cmd, hay, cmd.title.lowercased().hasPrefix(needle)))
        }
        for page in SettingsPanel.Page.allCases {
            let cmd = AddressCommand.page(page)
            guard cmd.available(in: browser) else { continue }
            let hay = "\(page.title.lowercased()) settings preferences"
            pool.append((cmd, hay, page.title.lowercased().hasPrefix(needle)))
        }

        var seen = Set<String>()
        let matched = pool
            .filter { item in
                words.allSatisfy { item.haystack.contains($0) }
            }
            .sorted { a, b in a.exactStart && !b.exactStart }
            .compactMap { item -> Suggestion? in
                guard seen.insert(item.cmd.title).inserted else { return nil }
                return row(item.cmd)
            }
        return Array(matched.prefix(limit))
    }
}
