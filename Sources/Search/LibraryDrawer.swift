import AppKit
import ImageIO
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

enum LibrarySection: String, CaseIterable, Identifiable {
    case downloads, media, bookmarks, history, spaces, extensions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloads: return "Downloads"
        case .media: return "Media"
        case .bookmarks: return "Bookmarks"
        case .history: return "History"
        case .spaces: return "Spaces"
        case .extensions: return "Extensions"
        }
    }

    var icon: String {
        switch self {
        case .downloads: return "arrow.down.circle"
        case .media: return "photo.on.rectangle"
        case .bookmarks: return "bookmark"
        case .history: return "clock.arrow.circlepath"
        case .spaces: return "square.stack"
        case .extensions: return "puzzlepiece.extension"
        }
    }
}

/// Zen / Artemis-inspired sidebar Library drawer: vertical section rail on the
/// left (Downloads, Media, Bookmarks, History, Spaces, Extensions) with a `<`
/// back button at the bottom, and searchable content on the right.
struct LibraryDrawer: View {
    static let preferredWidth: CGFloat = 390

    @ObservedObject var browser: Browser
    @ObservedObject var fetches: Fetches
    @ObservedObject var loot: Loot
    @ObservedObject var prefs: Preferences

    @State private var query = ""
    @State private var downloadFilter: DownloadFilter = .all
    @State private var mediaFilter: MediaFilter = .all
    @AppStorage("library.media.downloads.v2") private var includeDownloads = true
    @AppStorage("library.media.pictures.v2") private var includePictures = true
    @AppStorage("library.media.documents.v2") private var includeDocuments = true
    @State private var archiveExpanded = false
    @State private var addingFolder = false
    @State private var newFolderName = ""
    @State private var expandedFolders: Set<Bookmark.ID> = []
    @State private var draggingBookmarkID: Bookmark.ID? = nil
    @State private var dropTarget: BookmarkDropTarget? = nil
    @State private var folderExpandWork: DispatchWorkItem? = nil
    @State private var mediaItems: [MediaFile] = []
    @State private var loadingMedia = false
    @State private var thumbnails: [URL: NSImage] = [:]

    @Environment(\.greys) private var greys

    enum DownloadFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case available = "On Disk"
        case documents = "Docs & PDFs"
        case archives = "Installers & Archives"
        var id: String { rawValue }
    }

    enum MediaFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case pictures = "Pictures"
        case downloads = "Downloads"
        case documents = "Docs"
        case imagesOnly = "Images"
        case pdfsOnly = "PDFs"
        var id: String { rawValue }
    }

    @State private var draggingSpaceID: UUID? = nil

    private var section: LibrarySection {
        browser.librarySection ?? .downloads
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
                .frame(width: 58)
                .padding(.vertical, 6)

            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 1)
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 8) {
                searchHeader
                if section == .downloads || section == .media {
                    filterPills
                }
                listBody
            }
            .padding(.leading, 8)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if section == .media { loadMedia() }
        }
        .onChange(of: browser.librarySection) { _, next in
            query = ""
            if next == .media { loadMedia() }
        }
        .onChange(of: includeDownloads) { _, _ in if section == .media { loadMedia() } }
        .onChange(of: includePictures) { _, _ in if section == .media { loadMedia() } }
        .onChange(of: includeDocuments) { _, _ in if section == .media { loadMedia() } }
        .onChange(of: draggingBookmarkID) { _, id in
            if id == nil {
                dropTarget = nil
                folderExpandWork?.cancel()
                folderExpandWork = nil
            }
        }
    }

    // MARK: - Left Rail

    private var rail: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)

            ForEach(LibrarySection.allCases, id: \.self) { item in
                RailButton(
                    item: item,
                    active: item == section,
                    action: { withAnimation(Motion.quick) { browser.librarySection = item } }
                )
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(Motion.quick) { browser.librarySection = nil }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.ink.opacity(0.75))
                    .frame(width: 28, height: 28)
                    .background(greys.hover.opacity(0.65), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Back to Tabs")
            .padding(.bottom, 6)
        }
    }

    // MARK: - Quick Filter Pills

    @ViewBuilder
    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                if section == .downloads {
                    ForEach(DownloadFilter.allCases) { f in
                        let on = downloadFilter == f
                        Button {
                            Haptics.tap()
                            withAnimation(Motion.quick) { downloadFilter = f }
                        } label: {
                            Text(f.rawValue)
                                .font(.system(size: 11, weight: on ? .semibold : .medium))
                                .foregroundStyle(on ? Palette.ink : greys.muted)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(on ? greys.wash : greys.hover.opacity(0.45))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                } else if section == .media {
                    let visible: [MediaFilter] = [.all, .pictures, .downloads] + (includeDocuments ? [.documents] : []) + [.imagesOnly, .pdfsOnly]
                    ForEach(visible) { f in
                        let on = mediaFilter == f
                        Button {
                            Haptics.tap()
                            withAnimation(Motion.quick) { mediaFilter = f }
                        } label: {
                            Text(f.rawValue)
                                .font(.system(size: 11, weight: on ? .semibold : .medium))
                                .foregroundStyle(on ? Palette.ink : greys.muted)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(on ? greys.wash : greys.hover.opacity(0.45))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
        }
    }

    // MARK: - Search & Filter Header

    private var searchHeader: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5))
                    .foregroundStyle(greys.muted)
                TextField("Search \(section.title)…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(greys.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(greys.hover.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )

            if section == .downloads {
                Menu {
                    Picker("Filter", selection: $downloadFilter) {
                        ForEach(DownloadFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    Divider()
                    Button("Open Downloads Folder") {
                        NSWorkspace.shared.open(prefs.downloads)
                    }
                    Button("Clear Missing") {
                        for keep in loot.kept where !keep.stillThere {
                            loot.forget(keep)
                        }
                    }
                    .disabled(!loot.kept.contains { !$0.stillThere })
                    Button("Clear List") {
                        loot.forgetAll()
                    }
                    .disabled(loot.kept.isEmpty)
                } label: {
                    Image(systemName: downloadFilter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(downloadFilter == .all ? Palette.ink.opacity(0.75) : Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background(greys.hover.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Filter & Clear")
            } else if section == .media {
                Menu {
                    Picker("Filter", selection: $mediaFilter) {
                        ForEach(MediaFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    Divider()
                    Toggle("Include Downloads", isOn: $includeDownloads)
                    Toggle("Include Pictures", isOn: $includePictures)
                    Toggle("Include Documents", isOn: $includeDocuments)
                    Divider()
                    Button("Refresh Media") { loadMedia() }
                } label: {
                    Image(systemName: mediaFilter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(mediaFilter == .all ? Palette.ink.opacity(0.75) : Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background(greys.hover.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Filter Media")
            } else if section == .bookmarks {
                HStack(spacing: 4) {
                    Menu {
                        if let tab = browser.active, tab.isWeb, let url = tab.address {
                            Button("Bookmark Current Tab") {
                                _ = browser.bookmarks.add(url, title: tab.title)
                            }
                        }
                        Button("New Folder…") {
                            newFolderName = ""
                            addingFolder = true
                        }
                        Divider()
                        Button("Open Bookmarks Manager") {
                            browser.lead(to: InternalPage(.bookmarks))
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Palette.ink.opacity(0.75))
                            .frame(width: 28, height: 28)
                            .background(greys.hover.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Add Bookmark or Folder")
                }
            } else if section == .history {
                Button { browser.lead(to: InternalPage(.history)) } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.ink.opacity(0.75))
                        .frame(width: 28, height: 28)
                        .background(greys.hover.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Open Full History (⌘Y)")
            } else if section == .spaces {
                Button {
                    withAnimation(Motion.quick) { browser.librarySection = nil }
                    browser.askForSpace()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.ink.opacity(0.75))
                        .frame(width: 28, height: 28)
                        .background(greys.hover.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("New Space")
            } else if section == .extensions {
                Button { browser.lead(to: InternalPage(.settings, "extensions")) } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.ink.opacity(0.75))
                        .frame(width: 28, height: 28)
                        .background(greys.hover.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Extensions Settings")
            }
        }
    }

    // MARK: - List Body

    @ViewBuilder
    private var listBody: some View {
        ScrollView {
            Group {
                if section == .bookmarks {
                    VStack(alignment: .leading, spacing: 0) {
                        bookmarksList
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        switch section {
                        case .downloads:
                            downloadsList
                        case .media:
                            mediaList
                        case .bookmarks:
                            EmptyView()
                        case .history:
                            historyList
                        case .spaces:
                            spacesList
                        case .extensions:
                            if #available(macOS 15.4, *) {
                                ExtensionsLibraryList(query: query, browser: browser)
                            } else {
                                emptyState("Extensions require macOS 15.4+", icon: "puzzlepiece.extension")
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Downloads

    @ViewBuilder
    private var downloadsList: some View {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let active = fetches.entries.filter { needle.isEmpty || $0.name.lowercased().contains(needle) }
        let kept = filteredDownloads(needle: needle)

        if !active.isEmpty {
            sectionHeading("In Progress")
            ForEach(active) { entry in
                ActiveDownloadRow(entry: entry, browser: browser)
            }
        }

        if kept.isEmpty && active.isEmpty {
            emptyState("No downloads", icon: "arrow.down.circle")
        } else {
            let grouped = groupByDay(kept, date: \.date)
            ForEach(grouped, id: \.title) { bucket in
                sectionHeading(bucket.title)
                ForEach(bucket.items) { keep in
                    CompletedDownloadRow(keep: keep, loot: loot)
                }
            }
        }
    }

    private func filteredDownloads(needle: String) -> [Keep] {
        loot.kept.filter { keep in
            if !needle.isEmpty && !keep.name.lowercased().contains(needle) && !keep.from.lowercased().contains(needle) {
                return false
            }
            let ext = keep.url.pathExtension.lowercased()
            switch downloadFilter {
            case .all: return true
            case .available: return keep.stillThere
            case .documents: return ["pdf", "doc", "docx", "txt", "md", "csv", "xlsx", "pptx"].contains(ext)
            case .archives: return ["dmg", "pkg", "zip", "tar", "gz", "7z", "iso", "app"].contains(ext)
            }
        }
    }

    // MARK: - Media

    @ViewBuilder
    private var mediaList: some View {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let items = mediaItems.filter { item in
            if !needle.isEmpty && !item.name.lowercased().contains(needle) && !item.source.lowercased().contains(needle) {
                return false
            }
            switch mediaFilter {
            case .all: return true
            case .pictures: return item.source == "Pictures"
            case .downloads: return item.source == "Downloads"
            case .documents: return item.source == "Documents"
            case .imagesOnly: return ["png", "jpg", "jpeg", "webp", "gif", "heic", "tiff", "tif", "bmp"].contains(item.ext)
            case .pdfsOnly: return item.ext == "pdf"
            }
        }

        if loadingMedia && items.isEmpty {
            HStack {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            }
            .padding(.top, 28)
        } else if items.isEmpty {
            emptyState("No matching media", icon: "photo.on.rectangle")
        } else {
            let grouped = groupByDay(items, date: \.modified)
            let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
            let allURLs = items.map(\.url)
            ForEach(grouped, id: \.title) { bucket in
                sectionHeading(bucket.title)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(bucket.items) { item in
                        MediaGridCard(item: item, thumbnail: thumbnails[item.url]) {
                            if let idx = allURLs.firstIndex(of: item.url) {
                                withAnimation(Motion.quick) {
                                    browser.mediaPreview = Browser.MediaPreviewState(items: allURLs, index: idx)
                                }
                            }
                        } openInTab: {
                            _ = browser.open(item.url, foreground: true)
                        } reveal: {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        }
                        .onAppear {
                            ensureThumbnail(for: item)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Bookmarks

    @ViewBuilder
    private var bookmarksList: some View {
        if addingFolder {
            HStack(spacing: 6) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
                TextField("Folder name…", text: $newFolderName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        _ = browser.bookmarks.addFolder(newFolderName)
                        addingFolder = false
                    }
                    .onExitCommand { addingFolder = false }
                Button("Add") {
                    _ = browser.bookmarks.addFolder(newFolderName)
                    addingFolder = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(greys.hover.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let roots = browser.bookmarks.roots
        if roots.isEmpty && !addingFolder {
            emptyState("No bookmarks yet", icon: "bookmark")
        } else if !needle.isEmpty {
            let matches = flattenBookmarks(roots).filter {
                $0.label.lowercased().contains(needle) || ($0.url?.lowercased().contains(needle) ?? false)
            }
            if matches.isEmpty {
                emptyState("No matching bookmarks", icon: "bookmark")
            } else {
                ForEach(matches) { item in
                    LibraryBookmarkLineView(
                        line: LibraryBookmarkLine(item: item, depth: 0, parentID: nil, index: 0, isOpen: false),
                        hasAnyFolder: false,
                        showHostInline: true,
                        browser: browser,
                        expanded: $expandedFolders,
                        draggingID: $draggingBookmarkID,
                        dropTarget: $dropTarget,
                        expandWork: $folderExpandWork
                    )
                }
            }
        } else {
            let lines = Self.buildBookmarkLines(roots, expanded: expandedFolders)
            let hasAnyFolder = roots.contains(where: \.isFolder)
            ForEach(lines) { line in
                LibraryBookmarkLineView(
                    line: line,
                    hasAnyFolder: hasAnyFolder,
                    showHostInline: false,
                    browser: browser,
                    expanded: $expandedFolders,
                    draggingID: $draggingBookmarkID,
                    dropTarget: $dropTarget,
                    expandWork: $folderExpandWork
                )
            }
            BookmarkEndDropZone(
                parentID: nil,
                count: roots.count,
                browser: browser,
                draggingID: $draggingBookmarkID,
                dropTarget: $dropTarget
            )
        }
    }

    private static func buildBookmarkLines(
        _ nodes: [Bookmark],
        expanded: Set<Bookmark.ID>,
        depth: Int = 0,
        parentID: Bookmark.ID? = nil
    ) -> [LibraryBookmarkLine] {
        var out: [LibraryBookmarkLine] = []
        for (idx, node) in nodes.enumerated() {
            let isOpen = node.isFolder && expanded.contains(node.id)
            out.append(LibraryBookmarkLine(item: node, depth: depth, parentID: parentID, index: idx, isOpen: isOpen))
            guard isOpen else { continue }
            if let kids = node.children, !kids.isEmpty {
                out.append(contentsOf: buildBookmarkLines(kids, expanded: expanded, depth: depth + 1, parentID: node.id))
            } else {
                out.append(LibraryBookmarkLine(item: node, depth: depth, parentID: parentID, index: idx, isOpen: true, isEmptyPlaceholder: true))
            }
        }
        return out
    }

    private func flattenBookmarks(_ items: [Bookmark]) -> [Bookmark] {
        var out: [Bookmark] = []
        for item in items {
            if item.isFolder {
                if let children = item.children { out.append(contentsOf: flattenBookmarks(children)) }
            } else {
                out.append(item)
            }
        }
        return out
    }

    // MARK: - History (+ Collapsible Archive Dropdown)

    @ViewBuilder
    private var historyList: some View {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerNeedle = needle.lowercased()
        let ghosts = browser.ghosts.filter {
            lowerNeedle.isEmpty || $0.title.lowercased().contains(lowerNeedle) || $0.url.absoluteString.lowercased().contains(lowerNeedle)
        }
        let sleeping = browser.tabs.filter {
            $0.asleep && (lowerNeedle.isEmpty || $0.label.lowercased().contains(lowerNeedle))
        }
        let archiveCount = ghosts.count + sleeping.count

        if archiveCount > 0 {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Button {
                        withAnimation(Motion.quick) { archiveExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(greys.muted)
                                .rotationEffect(.degrees(archiveExpanded ? 90 : 0))
                                .frame(width: 10)
                            Image(systemName: "archivebox")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Palette.ink.opacity(0.8))
                            Text("Archived & Sleeping")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                            Text("\(archiveCount)")
                                .font(.system(size: 10, weight: .medium).monospacedDigit())
                                .foregroundStyle(greys.muted)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(greys.hover.opacity(0.7), in: Capsule())
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    if !ghosts.isEmpty {
                        Button { browser.reopen() } label: {
                            Text("Restore")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Palette.ink.opacity(0.8))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(greys.hover.opacity(0.75), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Reopen Last Closed Tab")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(greys.hover.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                if archiveExpanded {
                    ForEach(Array(ghosts.enumerated()), id: \.offset) { _, ghost in
                        ArchiveGhostRow(ghost: ghost, browser: browser)
                    }
                    ForEach(sleeping) { tab in
                        Button {
                            browser.select(tab)
                            browser.librarySection = nil
                        } label: {
                            HStack(spacing: 8) {
                                if let url = tab.address {
                                    LibraryFavicon(url: url)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "moon.zzz")
                                        .font(.system(size: 11))
                                        .foregroundStyle(greys.muted)
                                        .frame(width: 16, height: 16)
                                }
                                Text(tab.label.isEmpty ? "Sleeping Tab" : tab.label)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.ink.opacity(0.85))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "moon.zzz")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(greys.muted)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 4)
        }

        let traces = Array(browser.history.everything(matching: needle).prefix(80))
        if traces.isEmpty && archiveCount == 0 {
            emptyState("No matching history", icon: "clock.arrow.circlepath")
        } else {
            let grouped = groupByDay(traces, date: \.last)
            ForEach(grouped, id: \.title) { bucket in
                sectionHeading(bucket.title)
                ForEach(bucket.items, id: \.key) { trace in
                    HistoryRow(trace: trace, browser: browser)
                }
            }
        }
    }

    // MARK: - Spaces

    @ViewBuilder
    private var spacesList: some View {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = Array(browser.spaces.enumerated()).filter {
            needle.isEmpty || $0.element.name.lowercased().contains(needle)
        }

        if filtered.isEmpty {
            emptyState("No matching spaces", icon: "square.stack")
        } else {
            ForEach(filtered, id: \.element.id) { index, space in
                SpaceLibraryCard(
                    space: space,
                    index: index,
                    active: space.id == browser.spaceID,
                    browser: browser,
                    draggingSpaceID: $draggingSpaceID
                )
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(greys.muted)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func emptyState(_ text: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(greys.muted.opacity(0.6))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(greys.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
    }

    private struct DayBucket<Item> {
        let title: String
        let items: [Item]
    }

    private func groupByDay<Item>(_ items: [Item], date: (Item) -> Date) -> [DayBucket<Item>] {
        let cal = Calendar.current
        var buckets: [(String, [Item])] = []
        var indices: [String: Int] = [:]

        for item in items {
            let d = date(item)
            let label: String
            if cal.isDateInToday(d) {
                label = "Today"
            } else if cal.isDateInYesterday(d) {
                label = "Yesterday"
            } else {
                let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 2
                label = days <= 6 ? "\(days) days ago" : "Older"
            }
            if let idx = indices[label] {
                buckets[idx].1.append(item)
            } else {
                indices[label] = buckets.count
                buckets.append((label, [item]))
            }
        }
        return buckets.map { DayBucket(title: $0.0, items: $0.1) }
    }

    private func loadMedia() {
        guard !loadingMedia else { return }
        loadingMedia = true
            let downloadsFolder = includeDownloads ? prefs.downloads : nil
            let picturesFolder = includePictures ? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first : nil
            let documentsFolder = includeDocuments ? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first : nil
        DispatchQueue.global(qos: .utility).async {
            let exts: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "heic", "tiff", "tif", "bmp", "mp4", "mov", "pdf"]
            let skipDirs: Set<String> = ["Photos Library.photoslibrary", "Photo Booth Library", "node_modules", ".git", ".build", "Codex", "Image-Line", "Splice Projects"]
            let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isDirectoryKey]
            var roots: [(url: URL, source: String)] = []
            var seenDirs: Set<URL> = []
            if let downloadsFolder, seenDirs.insert(downloadsFolder.standardizedFileURL).inserted {
                roots.append((downloadsFolder, "Downloads"))
            }
            if let picturesFolder, seenDirs.insert(picturesFolder.standardizedFileURL).inserted {
                roots.append((picturesFolder, "Pictures"))
            }
            if let documentsFolder, seenDirs.insert(documentsFolder.standardizedFileURL).inserted {
                roots.append((documentsFolder, "Documents"))
            }
            var found: [MediaFile] = []
            for root in roots {
                guard let enumerator = FileManager.default.enumerator(
                    at: root.url,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }
                for case let url as URL in enumerator {
                    let vals = try? url.resourceValues(forKeys: Set(keys))
                    if vals?.isDirectory == true {
                        if skipDirs.contains(url.lastPathComponent) || enumerator.level >= 3 {
                            enumerator.skipDescendants()
                        }
                        continue
                    }
                    let ext = url.pathExtension.lowercased()
                    guard exts.contains(ext), vals?.isRegularFile == true else { continue }
                    found.append(MediaFile(
                        url: url,
                        name: url.lastPathComponent,
                        ext: ext,
                        source: root.source,
                        size: Int64(vals?.fileSize ?? 0),
                        modified: vals?.contentModificationDate ?? .distantPast
                    ))
                }
            }
            found.sort { $0.modified > $1.modified }
            let clipped = Array(found.prefix(150))
            DispatchQueue.main.async {
                mediaItems = clipped
                loadingMedia = false
            }
        }
    }

    private func ensureThumbnail(for item: MediaFile) {
        guard thumbnails[item.url] == nil else { return }
        let url = item.url
        let ext = item.ext
        if ext == "pdf" {
            DispatchQueue.global(qos: .utility).async {
                guard let doc = PDFDocument(url: url),
                      let page = doc.page(at: 0) else { return }
                let img = page.thumbnail(of: CGSize(width: 260, height: 204), for: .cropBox)
                DispatchQueue.main.async {
                    thumbnails[url] = img
                }
            }
            return
        }
        guard ["png", "jpg", "jpeg", "webp", "gif", "heic", "tiff", "tif", "bmp"].contains(ext) else { return }
        DispatchQueue.global(qos: .utility).async {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 260,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return }
            let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            DispatchQueue.main.async {
                thumbnails[url] = img
            }
        }
    }
}

private struct MediaFile: Identifiable {
    let url: URL
    let name: String
    let ext: String
    let source: String
    let size: Int64
    let modified: Date
    var id: URL { url }
}

private struct ActiveDownloadRow: View {
    @ObservedObject var entry: FetchEntry
    let browser: Browser
    @Environment(\.greys) private var greys

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
                Text(entry.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if entry.canPause {
                    Button { browser.pauseDownload(entry) } label: {
                        Image(systemName: "pause.fill").font(.system(size: 10))
                    }.buttonStyle(.plain)
                } else if entry.canResume {
                    Button { browser.resumeDownload(entry) } label: {
                        Image(systemName: "play.fill").font(.system(size: 10))
                    }.buttonStyle(.plain)
                }
                Button { browser.cancelDownload(entry) } label: {
                    Image(systemName: "xmark").font(.system(size: 10))
                }.buttonStyle(.plain)
            }
            if let fraction = entry.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            }
            Text(entry.stalled ? "Stalled" : "\(ByteCountFormatter.string(fromByteCount: entry.completedBytes, countStyle: .file))")
                .font(.system(size: 10.5))
                .foregroundStyle(greys.muted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(greys.hover.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CompletedDownloadRow: View {
    let keep: Keep
    let loot: Loot
    @State private var hovering = false
    @State private var cachedIcon: NSImage?
    @State private var cachedSubtitle: String?
    @Environment(\.greys) private var greys

    private var icon: NSImage {
        cachedIcon ?? NSWorkspace.shared.icon(for: .data)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
                .opacity(keep.stillThere ? 1 : 0.45)

            VStack(alignment: .leading, spacing: 1) {
                Text(keep.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(keep.stillThere ? Palette.ink : greys.muted)
                    .lineLimit(1)
                Text(cachedSubtitle ?? keep.from)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(greys.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if hovering {
                Color.clear
                    .frame(width: 20, height: 20)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? greys.hover.opacity(0.65) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if keep.stillThere {
                FileDragOverlay(
                    url: keep.url,
                    fallbackIcon: icon,
                    dragSize: CGSize(width: 34, height: 34),
                    onTap: { NSWorkspace.shared.open(keep.url) }
                )
            }
        }
        .overlay(alignment: .trailing) {
            if hovering {
                Button {
                    loot.reveal(keep)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.ink.opacity(0.75))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
                .padding(.trailing, 8)
            }
        }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .task(id: keep.path) {
            let url = keep.url
            let path = keep.path
            let fallbackFrom = keep.from
            let result = await Task.detached(priority: .utility) { () -> (NSImage, String) in
                let icon = NSWorkspace.shared.icon(forFile: path)
                guard FileManager.default.fileExists(atPath: path) else {
                    return (icon, "File moved or missing")
                }
                let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .localizedTypeDescriptionKey])
                let bytes = vals?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
                let kind = vals?.localizedTypeDescription
                let sub: String
                switch (bytes, kind) {
                case let (b?, k?): sub = "\(b) · \(k)"
                case let (b?, nil): sub = b
                case let (nil, k?): sub = k
                default: sub = fallbackFrom
                }
                return (icon, sub)
            }.value
            cachedIcon = result.0
            cachedSubtitle = result.1
        }
        .contextMenu {
            if keep.stillThere {
                Button("Open") { NSWorkspace.shared.open(keep.url) }
                Button("Show in Finder") { loot.reveal(keep) }
            }
            if let address = keep.address {
                Button("Copy Address") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(address, forType: .string)
                }
            }
            Divider()
            Button("Remove from List") { loot.forget(keep) }
        }
    }
}

private struct RailButton: View {
    let item: LibrarySection
    let active: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.greys) private var greys

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: active ? .semibold : .regular))
                Text(item.title)
                    .font(.system(size: 9, weight: active ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(active ? Palette.ink : (hovering ? Palette.ink.opacity(0.9) : greys.muted))
            .frame(width: 52, height: 46)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active ? greys.wash : (hovering ? greys.hover.opacity(0.75) : .clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .help(item.title)
    }
}

private struct MediaGridCard: View {
    let item: MediaFile
    let thumbnail: NSImage?
    let open: () -> Void
    let openInTab: () -> Void
    let reveal: () -> Void
    @State private var hovering = false
    @Environment(\.greys) private var greys

    var body: some View {
        Color.clear
            .frame(height: 104)
            .overlay {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        greys.hover.opacity(0.55)
                        VStack(spacing: 4) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 34, height: 34)
                            Text(item.ext.uppercased())
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(greys.muted)
                        }
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if item.ext == "pdf" || item.ext == "mp4" || item.ext == "mov" {
                    Text(item.ext.uppercased())
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if hovering {
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.75)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(item.source)
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                        .padding(.leading, 6)
                        .padding(.trailing, 30)
                        .padding(.bottom, 6)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                FileDragOverlay(
                    url: item.url,
                    thumbnail: thumbnail,
                    fallbackIcon: NSWorkspace.shared.icon(forFile: item.url.path),
                    dragSize: CGSize(width: 72, height: 72),
                    onTap: open
                )
            }
            .overlay(alignment: .bottomTrailing) {
                if hovering {
                    Button(action: reveal) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                    .padding(6)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(hovering ? Color.white.opacity(0.28) : Palette.hairline, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
            .contextMenu {
                Button("Quick Preview") { open() }
                Button("Open in New Tab") { openInTab() }
                Button("Show in Finder") { reveal() }
            }
    }
}

/// Transparent AppKit click-and-file-drag bridge that initiates a native
/// `NSDraggingSession` carrying `url as NSURL` (so webpages, `<input type="file">`,
/// Finder, and other apps receive the file directly), while letting hover,
/// context menus, and scroll wheel events pass straight through to SwiftUI.
private struct FileDragOverlay: NSViewRepresentable {
    let url: URL
    var thumbnail: NSImage? = nil
    let fallbackIcon: NSImage
    var dragSize: CGSize = CGSize(width: 72, height: 72)
    let onTap: () -> Void

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        sync(view)
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        sync(nsView)
    }

    private func sync(_ view: DragView) {
        view.url = url
        view.thumbnail = thumbnail
        view.fallbackIcon = fallbackIcon
        view.dragSize = dragSize
        view.onTap = onTap
    }

    final class DragView: NSView, NSDraggingSource {
        var url: URL = URL(fileURLWithPath: "/")
        var thumbnail: NSImage?
        var fallbackIcon: NSImage?
        var dragSize: CGSize = CGSize(width: 72, height: 72)
        var onTap: () -> Void = {}

        private var pressEvent: NSEvent?
        private var didDrag = false

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let type = NSApp.currentEvent?.type,
                  type == .leftMouseDown || type == .leftMouseDragged || type == .leftMouseUp
            else { return nil }
            return super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) {
            pressEvent = event
            didDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let press = pressEvent, !didDrag else { return }
            let dx = event.locationInWindow.x - press.locationInWindow.x
            let dy = event.locationInWindow.y - press.locationInWindow.y
            guard hypot(dx, dy) >= 4 else { return }

            didDrag = true
            pressEvent = nil
            guard FileManager.default.fileExists(atPath: url.path) else { return }

            let image = makeDragPreview()
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let local = convert(press.locationInWindow, from: nil)
            let size = image.size
            let dragFrame = NSRect(
                x: local.x - size.width / 2,
                y: local.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            item.setDraggingFrame(dragFrame, contents: image)
            beginDraggingSession(with: [item], event: press, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            let wasTap = pressEvent != nil && !didDrag
            pressEvent = nil
            didDrag = false
            if wasTap, bounds.contains(convert(event.locationInWindow, from: nil)) {
                onTap()
            }
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            [.copy, .generic]
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            pressEvent = nil
            didDrag = false
        }

        private func makeDragPreview() -> NSImage {
            guard let source = thumbnail else {
                let icon = (fallbackIcon?.copy() as? NSImage) ?? NSWorkspace.shared.icon(forFile: url.path)
                icon.size = dragSize
                return icon
            }
            let aspect = source.size.height > 0 ? source.size.width / source.size.height : 1
            let w: CGFloat
            let h: CGFloat
            if aspect >= 1 {
                w = dragSize.width
                h = max(28, dragSize.width / aspect)
            } else {
                h = dragSize.height
                w = max(28, dragSize.height * aspect)
            }
            let target = NSSize(width: w, height: h)
            return NSImage(size: target, flipped: false) { rect in
                let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
                path.addClip()
                source.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
                NSColor.white.withAlphaComponent(0.28).setStroke()
                path.lineWidth = 1
                path.stroke()
                return true
            }
        }
    }
}

private struct HistoryRow: View {
    let trace: History.Trace
    let browser: Browser
    @State private var hovering = false
    @Environment(\.greys) private var greys

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        Button {
            _ = browser.open(trace.url, foreground: true)
        } label: {
            HStack(spacing: 8) {
                LibraryFavicon(url: trace.url)
                    .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(trace.title.isEmpty ? (trace.url.host() ?? trace.url.absoluteString) : trace.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(trace.url.host() ?? trace.url.absoluteString)
                        .font(.system(size: 11))
                        .foregroundStyle(greys.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if hovering {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(trace.url.absoluteString, forType: .string)
                    } label: {
                        Image(systemName: "link")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.ink.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .help("Copy Address")
                } else {
                    Text(Self.timeFormatter.string(from: trace.last))
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(greys.muted)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? greys.hover.opacity(0.65) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .contextMenu {
            Button("Open in New Tab") { _ = browser.open(trace.url, foreground: true) }
            Button("Open in Split View") {
                if let active = browser.active {
                    browser.openLinkBeside(trace.url, from: active, onLeft: false)
                } else {
                    _ = browser.open(trace.url, foreground: true)
                }
            }
            Button("Copy Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(trace.url.absoluteString, forType: .string)
            }
        }
    }
}

private struct ArchiveGhostRow: View {
    let ghost: Browser.Ghost
    let browser: Browser
    @State private var hovering = false
    @Environment(\.greys) private var greys

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        Button {
            _ = browser.open(ghost.url, foreground: true)
        } label: {
            HStack(spacing: 8) {
                LibraryFavicon(url: ghost.url)
                    .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ghost.title.isEmpty ? "Closed Tab" : ghost.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let host = ghost.url.host() {
                        Text(host)
                            .font(.system(size: 11))
                            .foregroundStyle(greys.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text(Self.relativeFormatter.localizedString(for: ghost.at, relativeTo: Date()))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(greys.muted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? greys.hover.opacity(0.65) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .contextMenu {
            Button("Restore Tab") { _ = browser.open(ghost.url, foreground: true) }
            Button("Open in Split View") {
                if let active = browser.active {
                    browser.openLinkBeside(ghost.url, from: active, onLeft: false)
                } else {
                    _ = browser.open(ghost.url, foreground: true)
                }
            }
        }
    }
}

private struct LibraryFavicon: View {
    let url: URL
    @Environment(\.greys) private var greys

    private var icon: NSImage? {
        if let direct = Favicons.shared.cached(for: url) { return direct }
        if let host = url.host()?.lowercased() {
            return Favicons.shared.cached(host) ?? Favicons.shared.cached("www." + host)
        }
        return nil
    }

    var body: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 15, height: 15)
                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
        } else {
            Image(systemName: "globe")
                .font(.system(size: 11))
                .foregroundStyle(greys.muted)
                .frame(width: 15, height: 15)
        }
    }
}

private struct LibraryBookmarkLine: Identifiable {
    let item: Bookmark
    let depth: Int
    let parentID: Bookmark.ID?
    let index: Int
    let isOpen: Bool
    var isEmptyPlaceholder = false

    var id: String {
        isEmptyPlaceholder ? "empty-\(item.id.uuidString)" : item.id.uuidString
    }
}

private enum BookmarkDropPlacement: Equatable {
    case before, into, after
}

private struct BookmarkDropTarget: Equatable {
    let targetID: Bookmark.ID?
    let isPlaceholder: Bool
    let parentID: Bookmark.ID?
    let index: Int
    let placement: BookmarkDropPlacement
}

private func settleBookmarkDrag(
    draggingID: Binding<Bookmark.ID?>,
    dropTarget: Binding<BookmarkDropTarget?>,
    expandWork: Binding<DispatchWorkItem?>
) {
    Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { timer in
        guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
        timer.invalidate()
        MainActor.assumeIsolated {
            expandWork.wrappedValue?.cancel()
            expandWork.wrappedValue = nil
            dropTarget.wrappedValue = nil
            draggingID.wrappedValue = nil
        }
    }
}

private struct BookmarkTreeDropDelegate: DropDelegate {
    let targetID: Bookmark.ID
    let isFolder: Bool
    let isEmptyPlaceholder: Bool
    let isOpen: () -> Bool
    let rowHeight: () -> CGFloat
    let browser: Browser
    @Binding var draggingID: Bookmark.ID?
    @Binding var dropTarget: BookmarkDropTarget?
    @Binding var expandWork: DispatchWorkItem?
    var onSpringOpen: (() -> Void)? = nil

    private static func position(of id: Bookmark.ID, in nodes: [Bookmark], parent: Bookmark.ID? = nil) -> (parent: Bookmark.ID?, index: Int)? {
        for (idx, node) in nodes.enumerated() {
            if node.id == id { return (parent, idx) }
            if let kids = node.children, let found = position(of: id, in: kids, parent: node.id) {
                return found
            }
        }
        return nil
    }

    private var allows: Bool {
        guard let moved = draggingID else { return false }
        if isEmptyPlaceholder {
            return moved != targetID && !(browser.bookmarks.path(to: targetID) ?? []).contains { $0.id == moved }
        }
        return moved != targetID && !(browser.bookmarks.path(to: targetID) ?? []).contains { $0.id == moved }
    }

    private func placement(for info: DropInfo) -> BookmarkDropPlacement? {
        guard allows else { return nil }
        if isEmptyPlaceholder { return .into }

        let open = isOpen()
        let h = max(rowHeight(), 1)
        let part = info.location.y / h
        let raw: BookmarkDropPlacement
        if isFolder {
            if part < 0.25 { raw = .before }
            else if part > 0.75 { raw = .after }
            else { raw = .into }
        } else {
            raw = part < 0.5 ? .before : .after
        }

        guard let moved = draggingID,
              let movedPos = Self.position(of: moved, in: browser.bookmarks.roots),
              let targetPos = Self.position(of: targetID, in: browser.bookmarks.roots)
        else { return raw }

        // Suppress redundant no-op lines adjacent to the item's own slot
        if raw == .before, movedPos.parent == targetPos.parent, targetPos.index == movedPos.index + 1 {
            return nil
        }
        if raw == .after {
            if isFolder && open {
                if movedPos.parent == targetID && movedPos.index == 0 { return nil }
            } else if movedPos.parent == targetPos.parent, targetPos.index == movedPos.index - 1 {
                return nil
            }
        }
        return raw
    }

    private func updateAim(_ target: BookmarkDropTarget?) {
        guard target != dropTarget else { return }
        dropTarget = target
        expandWork?.cancel()
        expandWork = nil
        if let target, target.placement == .into, isFolder, !isOpen(), let onSpringOpen {
            let work = DispatchWorkItem { onSpringOpen() }
            expandWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: work)
        }
    }

    private func currentTarget(for info: DropInfo) -> BookmarkDropTarget? {
        guard let place = placement(for: info),
              let pos = Self.position(of: targetID, in: browser.bookmarks.roots)
        else { return nil }
        return BookmarkDropTarget(targetID: targetID, isPlaceholder: isEmptyPlaceholder, parentID: pos.parent, index: pos.index, placement: place)
    }

    func validateDrop(info: DropInfo) -> Bool {
        allows
    }

    func dropEntered(info: DropInfo) {
        guard allows else {
            updateAim(nil)
            return
        }
        updateAim(currentTarget(for: info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard allows else {
            updateAim(nil)
            return DropProposal(operation: .forbidden)
        }
        updateAim(currentTarget(for: info))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTarget?.targetID == targetID && dropTarget?.isPlaceholder == isEmptyPlaceholder {
            updateAim(nil)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let place = placement(for: info)
        let targetPos = Self.position(of: targetID, in: browser.bookmarks.roots)
        updateAim(nil)
        dropTarget = nil
        guard let place, let targetPos else {
            draggingID = nil
            return false
        }

        let applyMove: (Bookmark.ID) -> Void = { movedID in
            guard movedID != targetID else { return }
            Haptics.tap()
            withAnimation(Motion.settle) {
                switch place {
                case .into:
                    browser.bookmarks.move(movedID, into: targetID, at: nil)
                case .before:
                    browser.bookmarks.move(movedID, into: targetPos.parent, at: targetPos.index)
                case .after where isFolder && isOpen():
                    browser.bookmarks.move(movedID, into: targetID, at: 0)
                case .after:
                    browser.bookmarks.move(movedID, into: targetPos.parent, at: targetPos.index + 1)
                }
            }
        }

        if let movedID = draggingID {
            draggingID = nil
            applyMove(movedID)
            return true
        }

        guard let provider = info.itemProviders(for: [.plainText, .text, .utf8PlainText]).first else {
            draggingID = nil
            return false
        }
        _ = provider.loadObject(ofClass: NSString.self) { str, _ in
            guard let raw = str as? String, let id = UUID(uuidString: raw) else { return }
            DispatchQueue.main.async {
                draggingID = nil
                dropTarget = nil
                applyMove(id)
            }
        }
        return true
    }
}

private struct BookmarkEndDropZone: View {
    let parentID: Bookmark.ID?
    let count: Int
    let browser: Browser
    @Binding var draggingID: Bookmark.ID?
    @Binding var dropTarget: BookmarkDropTarget?

    private var active: Bool {
        draggingID != nil && dropTarget?.targetID == nil && dropTarget?.parentID == parentID
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .contentShape(Rectangle())
            if active {
                BookmarkInsertionLine()
                    .padding(.top, 2)
                    .allowsHitTesting(false)
            }
        }
        .animation(Motion.quick, value: active)
        .onDrop(of: [.plainText, .text, .utf8PlainText], delegate: BookmarkEndDropDelegate(
            parentID: parentID,
            count: count,
            browser: browser,
            draggingID: $draggingID,
            dropTarget: $dropTarget
        ))
    }
}

private struct BookmarkEndDropDelegate: DropDelegate {
    let parentID: Bookmark.ID?
    let count: Int
    let browser: Browser
    @Binding var draggingID: Bookmark.ID?
    @Binding var dropTarget: BookmarkDropTarget?

    func validateDrop(info: DropInfo) -> Bool {
        draggingID != nil
    }

    func dropEntered(info: DropInfo) {
        guard draggingID != nil else {
            dropTarget = nil
            return
        }
        dropTarget = BookmarkDropTarget(targetID: nil, isPlaceholder: false, parentID: parentID, index: count, placement: .after)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggingID != nil else {
            dropTarget = nil
            return DropProposal(operation: .forbidden)
        }
        dropTarget = BookmarkDropTarget(targetID: nil, isPlaceholder: false, parentID: parentID, index: count, placement: .after)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTarget?.targetID == nil && dropTarget?.parentID == parentID {
            dropTarget = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dropTarget = nil
        let finishMove: (Bookmark.ID) -> Void = { movedID in
            Haptics.tap()
            withAnimation(Motion.settle) {
                browser.bookmarks.move(movedID, into: parentID, at: nil)
            }
        }
        if let movedID = draggingID {
            draggingID = nil
            finishMove(movedID)
            return true
        }
        guard let provider = info.itemProviders(for: [.plainText, .text, .utf8PlainText]).first else {
            draggingID = nil
            return false
        }
        _ = provider.loadObject(ofClass: NSString.self) { str, _ in
            guard let raw = str as? String, let id = UUID(uuidString: raw) else { return }
            DispatchQueue.main.async {
                draggingID = nil
                dropTarget = nil
                finishMove(id)
            }
        }
        return true
    }
}

private struct BookmarkInsertionLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.accentColor.opacity(0.9))
                .frame(width: 5, height: 5)
            Capsule()
                .fill(Color.accentColor.opacity(0.85))
                .frame(height: 1.5)
        }
        .padding(.horizontal, 6)
    }
}

private struct LibraryBookmarkLineView: View {
    let line: LibraryBookmarkLine
    let hasAnyFolder: Bool
    let showHostInline: Bool
    let browser: Browser
    @Binding var expanded: Set<Bookmark.ID>
    @Binding var draggingID: Bookmark.ID?
    @Binding var dropTarget: BookmarkDropTarget?
    @Binding var expandWork: DispatchWorkItem?

    @State private var hovering = false
    @State private var renaming = false
    @State private var draftTitle = ""
    @State private var rowHeight: CGFloat = 28
    @Environment(\.greys) private var greys

    private var item: Bookmark { line.item }

    private var dropPlacement: BookmarkDropPlacement? {
        guard draggingID != nil,
              dropTarget?.targetID == item.id,
              dropTarget?.isPlaceholder == line.isEmptyPlaceholder
        else { return nil }
        return dropTarget?.placement
    }

    private var isTargetedInto: Bool {
        dropPlacement == .into
    }

    private var rowOpacity: Double {
        if draggingID == item.id && !line.isEmptyPlaceholder { return 0.22 }
        if draggingID != nil && dropPlacement == nil { return 0.42 }
        return 1
    }

    private var dragIcon: NSImage? {
        if item.isFolder {
            return NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
        }
        if let url = item.address {
            if let direct = Favicons.shared.cached(for: url) { return direct }
            if let host = url.host()?.lowercased() {
                return Favicons.shared.cached(host) ?? Favicons.shared.cached("www." + host)
            }
        }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
    }

    var body: some View {
        if line.isEmptyPlaceholder {
            HStack(spacing: 6) {
                Text("Empty folder")
                    .font(.system(size: 11.5))
                    .foregroundStyle(isTargetedInto ? Color.accentColor : greys.muted.opacity(0.75))
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(line.depth + 1) * 16 + (hasAnyFolder ? 18 : 0) + 8)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isTargetedInto ? greys.wash : .clear)
            )
            .overlay {
                if isTargetedInto {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .opacity(rowOpacity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = max($0, 1) }
            .onDrop(of: [.plainText, .text, .utf8PlainText], delegate: BookmarkTreeDropDelegate(
                targetID: item.id,
                isFolder: true,
                isEmptyPlaceholder: true,
                isOpen: { true },
                rowHeight: { rowHeight },
                browser: browser,
                draggingID: $draggingID,
                dropTarget: $dropTarget,
                expandWork: $expandWork
            ))
            .animation(Motion.quick, value: dropPlacement)
            .animation(Motion.quick, value: draggingID)
        } else {
            HStack(spacing: 8) {
                if hasAnyFolder {
                    if item.isFolder {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(greys.muted)
                            .rotationEffect(.degrees(line.isOpen ? 90 : 0))
                            .frame(width: 10)
                    } else {
                        Spacer().frame(width: 10)
                    }
                }

                if item.isFolder {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isTargetedInto ? Color.accentColor.opacity(0.2) : greys.hover.opacity(0.85))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Image(systemName: "folder.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(isTargetedInto ? Color.accentColor : greys.muted)
                        )
                } else if let url = item.address {
                    LibraryFavicon(url: url)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "bookmark")
                        .font(.system(size: 11))
                        .foregroundStyle(greys.muted)
                        .frame(width: 16, height: 16)
                }

                if renaming {
                    TextField(item.isFolder ? "Folder name" : "Bookmark name", text: $draftTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, weight: .medium))
                        .onSubmit {
                            BookmarkCard.rename(item.id, draftTitle, in: browser.bookmarks)
                            renaming = false
                        }
                        .onExitCommand { renaming = false }
                } else {
                    Text(item.label)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if item.isFolder {
                    if let kids = item.children, !kids.isEmpty {
                        Text("\(Bookmarks.count(kids))")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(greys.muted)
                    }
                } else if hovering, !renaming, draggingID == nil {
                    Color.clear.frame(width: 16, height: 16)
                } else if showHostInline, let host = item.host {
                    Text(host)
                        .font(.system(size: 11))
                        .foregroundStyle(greys.muted)
                        .lineLimit(1)
                }
            }
            .padding(.leading, CGFloat(line.depth) * 16 + 8)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .background(alignment: .leading) {
                if line.depth > 0 {
                    HStack(spacing: 15) {
                        ForEach(0..<line.depth, id: \.self) { _ in
                            Rectangle()
                                .fill(Palette.hairline.opacity(0.6))
                                .frame(width: 1)
                        }
                    }
                    .padding(.leading, 14)
                    .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isTargetedInto ? greys.wash : (hovering && draggingID == nil ? greys.hover.opacity(0.65) : .clear))
            )
            .overlay {
                if !renaming {
                    BookmarkDragOverlay(
                        id: item.id,
                        label: item.label,
                        icon: dragIcon,
                        onTap: {
                            if item.isFolder {
                                withAnimation(Motion.quick) {
                                    if expanded.contains(item.id) {
                                        expanded.remove(item.id)
                                    } else {
                                        expanded.insert(item.id)
                                    }
                                }
                            } else if let url = item.address {
                                _ = browser.open(url, foreground: true)
                            }
                        },
                        onDragStart: {
                            draggingID = item.id
                            settleBookmarkDrag(draggingID: $draggingID, dropTarget: $dropTarget, expandWork: $expandWork)
                        },
                        onDragEnd: {
                            expandWork?.cancel()
                            expandWork = nil
                            dropTarget = nil
                            draggingID = nil
                        }
                    )
                }
            }
            .overlay(alignment: .trailing) {
                if !item.isFolder, hovering, !renaming, draggingID == nil, let url = item.address {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    } label: {
                        Image(systemName: "link")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.ink.opacity(0.75))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Copy Address")
                    .padding(.trailing, 6)
                }
            }
            .overlay {
                if isTargetedInto {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: dropPlacement == .before ? .top : .bottom) {
                if dropPlacement == .before || dropPlacement == .after {
                    let indentLevel = line.depth + (item.isFolder && line.isOpen && dropPlacement == .after ? 1 : 0)
                    BookmarkInsertionLine()
                        .padding(.leading, CGFloat(indentLevel) * 16)
                        .offset(y: dropPlacement == .before ? -1 : 1)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(rowOpacity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = max($0, 1) }
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
            .animation(Motion.quick, value: dropPlacement)
            .animation(Motion.quick, value: draggingID)
            .onDrop(of: [.plainText, .text, .utf8PlainText], delegate: BookmarkTreeDropDelegate(
                targetID: item.id,
                isFolder: item.isFolder,
                isEmptyPlaceholder: false,
                isOpen: { expanded.contains(item.id) },
                rowHeight: { rowHeight },
                browser: browser,
                draggingID: $draggingID,
                dropTarget: $dropTarget,
                expandWork: $expandWork,
                onSpringOpen: item.isFolder ? {
                    withAnimation(Motion.settle) { _ = expanded.insert(item.id) }
                } : nil
            ))
            .contextMenu {
                if item.isFolder {
                    Button("Rename…") {
                        draftTitle = item.label
                        renaming = true
                    }
                    if line.depth > 0 {
                        Button("Move to Top Level") {
                            browser.bookmarks.move(item.id, into: nil)
                        }
                    }
                    Divider()
                    Button("Delete Folder", role: .destructive) {
                        browser.bookmarks.remove(item.id)
                    }
                } else {
                    if let url = item.address {
                        Button("Open in New Tab") { _ = browser.open(url, foreground: true) }
                        Button("Open in Split View") {
                            if let active = browser.active {
                                browser.openLinkBeside(url, from: active, onLeft: false)
                            } else {
                                _ = browser.open(url, foreground: true)
                            }
                        }
                        Button("Copy Address") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        }
                        Divider()
                    }
                    Button("Rename…") {
                        draftTitle = item.label
                        renaming = true
                    }
                    if line.depth > 0 {
                        Button("Move to Top Level") {
                            browser.bookmarks.move(item.id, into: nil)
                        }
                    }
                    Button("Remove Bookmark", role: .destructive) {
                        browser.bookmarks.remove(item.id)
                    }
                }
            }
        }
    }
}

/// Native AppKit click + drag bridge for Bookmark & Folder rows so drags never
/// fail inside `ScrollView`, and drag start/end fire synchronously through AppKit.
private struct BookmarkDragOverlay: NSViewRepresentable {
    let id: Bookmark.ID
    let label: String
    let icon: NSImage?
    let onTap: () -> Void
    let onDragStart: () -> Void
    let onDragEnd: () -> Void

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        sync(view)
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        sync(nsView)
    }

    private func sync(_ view: DragView) {
        view.bookmarkID = id
        view.label = label
        view.icon = icon
        view.onTap = onTap
        view.onDragStart = onDragStart
        view.onDragEnd = onDragEnd
    }

    final class DragView: NSView, NSDraggingSource {
        var bookmarkID: Bookmark.ID = UUID()
        var label: String = ""
        var icon: NSImage?
        var onTap: () -> Void = {}
        var onDragStart: () -> Void = {}
        var onDragEnd: () -> Void = {}

        private var pressEvent: NSEvent?
        private var didDrag = false

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let type = NSApp.currentEvent?.type else { return nil }
            if type == .leftMouseDown { return super.hitTest(point) }
            if (type == .leftMouseDragged || type == .leftMouseUp), pressEvent != nil {
                return super.hitTest(point)
            }
            return nil
        }

        override func mouseDown(with event: NSEvent) {
            pressEvent = event
            didDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let press = pressEvent, !didDrag else { return }
            let dx = event.locationInWindow.x - press.locationInWindow.x
            let dy = event.locationInWindow.y - press.locationInWindow.y
            guard hypot(dx, dy) >= 4 else { return }

            didDrag = true
            pressEvent = nil
            onDragStart()

            let preview = makePillPreview()
            let item = NSDraggingItem(pasteboardWriter: bookmarkID.uuidString as NSString)
            let local = convert(press.locationInWindow, from: nil)
            let size = preview.size
            item.setDraggingFrame(
                NSRect(x: local.x - 16, y: local.y - size.height / 2, width: size.width, height: size.height),
                contents: preview
            )
            beginDraggingSession(with: [item], event: press, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            let wasTap = pressEvent != nil && !didDrag
            pressEvent = nil
            didDrag = false
            if wasTap, bounds.contains(convert(event.locationInWindow, from: nil)) {
                onTap()
            }
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            [.move, .generic]
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            pressEvent = nil
            didDrag = false
            onDragEnd()
        }

        private func makePillPreview() -> NSImage {
            let font = NSFont.systemFont(ofSize: 12, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: Palette.NS.ink
            ]
            let title = label.isEmpty ? "Bookmark" : label
            let measured = (title as NSString).size(withAttributes: attrs)
            let textW = min(ceil(measured.width), 170)
            let iconW: CGFloat = icon != nil ? 18 : 0
            let size = NSSize(width: 20 + iconW + textW, height: 28)

            return NSImage(size: size, flipped: false) { rect in
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
                Palette.NS.ground.setFill()
                path.fill()
                Palette.NS.hairline.setStroke()
                path.lineWidth = 1
                path.stroke()

                var x: CGFloat = 10
                if let icon = self.icon {
                    let iconRect = NSRect(x: x, y: (rect.height - 14) / 2, width: 14, height: 14)
                    icon.draw(in: iconRect)
                    x += 18
                }
                let textRect = NSRect(x: x, y: (rect.height - ceil(measured.height)) / 2, width: textW, height: ceil(measured.height))
                (title as NSString).draw(in: textRect, withAttributes: attrs)
                return true
            }
        }
    }
}

@available(macOS 15.4, *)
private struct ExtensionsLibraryList: View {
    let query: String
    let browser: Browser
    @ObservedObject private var extensions = Extensions.shared
    @Environment(\.greys) private var greys

    var body: some View {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let items = extensions.installed.filter { needle.isEmpty || $0.name.lowercased().contains(needle) }

        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 20))
                    .foregroundStyle(greys.muted.opacity(0.6))
                Text(extensions.installed.isEmpty ? "No extensions installed" : "No matching extensions")
                    .font(.system(size: 12))
                    .foregroundStyle(greys.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
        } else {
            ForEach(items) { ext in
                ExtensionLibraryRow(ext: ext, extensions: extensions, browser: browser)
            }
        }
    }
}

@available(macOS 15.4, *)
private struct ExtensionLibraryRow: View {
    let ext: Installed
    @ObservedObject var extensions: Extensions
    let browser: Browser
    @State private var hovering = false
    @Environment(\.greys) private var greys

    private var pinned: Bool { ext.pinned ?? false }

    var body: some View {
        HStack(spacing: 9) {
            if let icon = extensions.contexts[ext.id]?.webExtension.icon(for: CGSize(width: 28, height: 28)) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .opacity(ext.enabled ? 1 : 0.45)
            } else {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 14))
                    .foregroundStyle(greys.muted)
                    .frame(width: 24, height: 24)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(ext.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ext.enabled ? Palette.ink : greys.muted)
                    .lineLimit(1)
                Text("\(ext.enabled ? "Active" : "Disabled") · v\(ext.version)\(pinned ? " · Pinned" : "")")
                    .font(.system(size: 10))
                    .foregroundStyle(greys.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                extensions.setPinned(ext.id, !pinned)
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 10.5))
                    .foregroundStyle(pinned ? Color.accentColor : greys.muted)
                    .frame(width: 22, height: 22)
                    .background(hovering ? greys.hover.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(pinned ? "Unpin from Toolbar" : "Pin to Toolbar")

            Toggle("", isOn: Binding(
                get: { ext.enabled },
                set: { extensions.setEnabled(ext.id, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? greys.hover.opacity(0.65) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            guard ext.enabled, let context = extensions.contexts[ext.id] else { return }
            _ = extensions.openPopup(for: context)
        }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .contextMenu {
            if ext.enabled, let context = extensions.contexts[ext.id] {
                Button("Open Popup") { _ = extensions.openPopup(for: context) }
            }
            Button(pinned ? "Unpin from Toolbar" : "Pin to Toolbar") {
                extensions.setPinned(ext.id, !pinned)
            }
            if ext.enabled {
                Button("Reload Extension") { extensions.reload(ext.id) }
            }
            Button(ext.enabled ? "Disable" : "Enable") {
                extensions.setEnabled(ext.id, !ext.enabled)
            }
            Divider()
            Button("Remove Extension", role: .destructive) {
                extensions.remove(ext.id)
            }
        }
    }
}

private struct SpaceLibraryCard: View {
    let space: Space
    let index: Int
    let active: Bool
    @ObservedObject var browser: Browser
    @Binding var draggingSpaceID: UUID?
    @State private var hovering = false
    @State private var renaming = false
    @State private var draftName = ""
    @State private var dropTargeted = false
    @Environment(\.greys) private var greys

    private var spaceTabs: [Tab] {
        let list = active ? browser.tabs : (browser.parked[space.id]?.tabs ?? [])
        return list.filter { $0.pin == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((space.tint ?? Palette.muted).opacity(active ? 0.28 : 0.16))
                    Image(systemName: space.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(space.tint ?? Palette.ink)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    if renaming {
                        TextField("Space name", text: $draftName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, weight: .semibold))
                            .onSubmit {
                                browser.renameSpace(space.id, to: draftName)
                                renaming = false
                            }
                            .onExitCommand { renaming = false }
                    } else {
                        Text(space.name)
                            .font(.system(size: 12.5, weight: active ? .semibold : .medium))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                    }
                    Text(spaceTabs.count == 1 ? "1 tab" : "\(spaceTabs.count) tabs")
                        .font(.system(size: 10.5))
                        .foregroundStyle(greys.muted)
                }

                Spacer(minLength: 0)

                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                }
            }

            if !spaceTabs.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(spaceTabs.prefix(6))) { tab in
                        if let url = tab.address {
                            LibraryFavicon(url: url)
                                .frame(width: 14, height: 14)
                        }
                    }
                    if spaceTabs.count > 6 {
                        Text("+\(spaceTabs.count - 6)")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(greys.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 38)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(active ? greys.wash : (hovering ? greys.hover.opacity(0.65) : greys.hover.opacity(0.25)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(dropTargeted ? Color.accentColor : (active ? (space.tint ?? Palette.hairline).opacity(0.55) : Palette.hairline.opacity(0.5)), lineWidth: dropTargeted ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            guard !renaming else { return }
            browser.switchSpace(to: space.id)
            withAnimation(Motion.quick) { browser.librarySection = nil }
        }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .onDrag {
            draggingSpaceID = space.id
            return NSItemProvider(object: space.id.uuidString as NSString)
        }
        .onDrop(of: [.plainText, .text], isTargeted: $dropTargeted) { _ in
            guard let moved = draggingSpaceID, moved != space.id else { return false }
            draggingSpaceID = nil
            withAnimation(Motion.quick) {
                browser.moveSpace(moved, to: index)
            }
            return true
        }
        .contextMenu {
            Button("Switch to Space") {
                browser.switchSpace(to: space.id)
                withAnimation(Motion.quick) { browser.librarySection = nil }
            }
            Button("Rename…") {
                draftName = space.name
                renaming = true
            }
            Menu("Colour") {
                ForEach(Array(Spaces.colourNames.enumerated()), id: \.offset) { idx, label in
                    Button {
                        browser.setSpaceColour(space.id, to: idx)
                    } label: {
                        HStack {
                            Text(label)
                            if space.colour == idx { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        }
    }
}

/// Zen-style Quick Preview lightbox overlay for Media items (images, PDFs, videos).
struct MediaPreviewOverlay: View {
    @ObservedObject var browser: Browser
    let preview: Browser.MediaPreviewState
    @State private var fullImage: NSImage?
    @State private var modifiedDate: Date?
    @State private var copied = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var url: URL? { preview.current }
    private var ext: String { url?.pathExtension.lowercased() ?? "" }
    private var isImage: Bool { ["png", "jpg", "jpeg", "webp", "gif", "heic", "tiff", "tif", "bmp"].contains(ext) }
    private var isPDF: Bool { ext == "pdf" }

    var body: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                header
                Rectangle().fill(Palette.hairline).frame(height: 1)
                previewContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
            }
            .frame(maxWidth: 740, maxHeight: 620)
            .background(
                ZStack {
                    VisualEffectView(material: .popover, blendingMode: .withinWindow)
                    Palette.ground.opacity(0.86)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.36), radius: 32, y: 12)
            .padding(36)
            .transition(.scale(scale: 0.97).combined(with: .opacity))
        }
        .onAppear { loadCurrent() }
        .onChange(of: preview.index) { _, _ in loadCurrent() }
        .onExitCommand { dismiss() }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")

            HStack(spacing: 2) {
                Button { step(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(preview.index > 0 ? Palette.ink : Palette.muted.opacity(0.4))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(preview.index <= 0)

                Button { step(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(preview.index + 1 < preview.items.count ? Palette.ink : Palette.muted.opacity(0.4))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(preview.index + 1 >= preview.items.count)
            }

            if let url {
                Text(url.lastPathComponent)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let modifiedDate {
                    Text(Self.relativeFormatter.localizedString(for: modifiedDate, relativeTo: Date()))
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(Palette.muted)
                }
                if preview.items.count > 1 {
                    Text("\(preview.index + 1)/\(preview.items.count)")
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.wash, in: Capsule())
                }
            }

            Spacer(minLength: 8)

            if let url {
                Menu {
                    Button("Open in New Tab") {
                        _ = browser.open(url, foreground: true)
                        dismiss()
                    }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    Button("Copy File Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.path, forType: .string)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 26, height: 26)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                if let fullImage {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([fullImage])
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10.5))
                            Text(copied ? "Copied" : "Copy Image")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundStyle(copied ? Color.accentColor : Palette.ink)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Text("Open in Preview")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var previewContent: some View {
        if let url {
            if isImage {
                if let fullImage {
                    Image(nsImage: fullImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    ProgressView().controlSize(.small)
                }
            } else if isPDF {
                PDFKitPreviewView(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                    Text(url.lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Button("Open in Preview") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func step(_ delta: Int) {
        let next = preview.index + delta
        guard preview.items.indices.contains(next) else { return }
        browser.mediaPreview?.index = next
    }

    private func dismiss() {
        withAnimation(Motion.quick) {
            browser.mediaPreview = nil
        }
    }

    private func loadCurrent() {
        fullImage = nil
        modifiedDate = nil
        guard let url else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let img = isImage ? NSImage(contentsOf: url) : nil
            DispatchQueue.main.async {
                if browser.mediaPreview?.current == url {
                    modifiedDate = vals?.contentModificationDate
                    fullImage = img
                }
            }
        }
    }
}

private struct PDFKitPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}
