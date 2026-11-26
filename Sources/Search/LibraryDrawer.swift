import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum LibrarySection: String, CaseIterable, Identifiable {
    case downloads, media, bookmarks, history, archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloads: return "Downloads"
        case .media: return "Media"
        case .bookmarks: return "Bookmarks"
        case .history: return "History"
        case .archive: return "Archive"
        }
    }

    var icon: String {
        switch self {
        case .downloads: return "arrow.down.circle"
        case .media: return "photo.on.rectangle"
        case .bookmarks: return "bookmark"
        case .history: return "clock.arrow.circlepath"
        case .archive: return "archivebox"
        }
    }
}

/// Zen / Artemis-inspired sidebar Library drawer: vertical section rail on the
/// left (Downloads, Media, Bookmarks, History, Archive) with a `<` back button
/// at the bottom, and a searchable, date-grouped list on the right.
struct LibraryDrawer: View {
    static let preferredWidth: CGFloat = 390

    @ObservedObject var browser: Browser
    @ObservedObject var fetches: Fetches
    @ObservedObject var loot: Loot
    @ObservedObject var prefs: Preferences

    @State private var query = ""
    @State private var downloadFilter: DownloadFilter = .all
    @State private var mediaFilter: MediaFilter = .all
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
        case documents = "Documents"
        case imagesOnly = "Images Only"
        case pdfsOnly = "PDFs Only"
        var id: String { rawValue }
    }

    private var section: LibrarySection {
        browser.librarySection ?? .downloads
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
                .frame(width: 60)
                .padding(.vertical, 6)

            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 1)
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 8) {
                searchHeader
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
    }

    // MARK: - Left Rail

    private var rail: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)

            ForEach(LibrarySection.allCases, id: \.self) { item in
                let active = item == section
                Button {
                    withAnimation(Motion.quick) { browser.librarySection = item }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: active ? .semibold : .regular))
                        Text(item.title)
                            .font(.system(size: 9, weight: active ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(active ? Palette.ink : Palette.ink.opacity(0.75))
                    .frame(width: 54, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(active ? greys.wash : .clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(item.title)
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

    // MARK: - Search & Filter Header

    private var searchHeader: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(greys.muted)
                TextField("Search \(section.title)…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
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
            .background(greys.hover.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

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
                Button { browser.lead(to: InternalPage(.bookmarks)) } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.ink.opacity(0.75))
                        .frame(width: 28, height: 28)
                        .background(greys.hover.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Open Bookmarks Manager")
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
            } else if section == .archive, !browser.ghosts.isEmpty {
                Button { browser.reopen() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.ink.opacity(0.75))
                        .frame(width: 28, height: 28)
                        .background(greys.hover.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Reopen Last Closed Tab")
            }
        }
    }

    // MARK: - List Body

    @ViewBuilder
    private var listBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                switch section {
                case .downloads:
                    downloadsList
                case .media:
                    mediaList
                case .bookmarks:
                    bookmarksList
                case .history:
                    historyList
                case .archive:
                    archiveList
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
            ForEach(grouped, id: \.title) { bucket in
                sectionHeading(bucket.title)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(bucket.items) { item in
                        MediaGridCard(item: item, thumbnail: thumbnails[item.url]) {
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
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let roots = browser.bookmarks.roots
        if roots.isEmpty {
            emptyState("No bookmarks yet", icon: "bookmark")
        } else if !needle.isEmpty {
            let matches = flattenBookmarks(roots).filter {
                $0.label.lowercased().contains(needle) || ($0.url?.lowercased().contains(needle) ?? false)
            }
            if matches.isEmpty {
                emptyState("No matching bookmarks", icon: "bookmark")
            } else {
                ForEach(matches) { item in
                    BookmarkLibraryRow(item: item, browser: browser)
                }
            }
        } else {
            ForEach(roots) { item in
                BookmarkLibraryNode(item: item, browser: browser, depth: 0)
            }
        }
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

    // MARK: - History

    @ViewBuilder
    private var historyList: some View {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let traces = Array(browser.history.everything(matching: needle).prefix(80))
        if traces.isEmpty {
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

    // MARK: - Archive

    @ViewBuilder
    private var archiveList: some View {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ghosts = browser.ghosts.filter {
            needle.isEmpty || $0.title.lowercased().contains(needle) || $0.url.absoluteString.lowercased().contains(needle)
        }
        let sleeping = browser.tabs.filter {
            $0.asleep && (needle.isEmpty || $0.label.lowercased().contains(needle))
        }

        if ghosts.isEmpty && sleeping.isEmpty {
            emptyState("No archived or sleeping tabs", icon: "archivebox")
        } else {
            if !ghosts.isEmpty {
                sectionHeading("Recently Closed")
                ForEach(Array(ghosts.enumerated()), id: \.offset) { _, ghost in
                    ArchiveGhostRow(ghost: ghost, browser: browser)
                }
            }
            if !sleeping.isEmpty {
                sectionHeading("Sleeping Tabs")
                ForEach(sleeping) { tab in
                    Button {
                        browser.select(tab)
                        browser.librarySection = nil
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "moon.zzz")
                                .font(.system(size: 11))
                                .foregroundStyle(greys.muted)
                            Text(tab.label.isEmpty ? "Sleeping Tab" : tab.label)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.ink.opacity(0.75))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
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
        let downloadsFolder = prefs.downloads
        let picturesFolder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        let documentsFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        DispatchQueue.global(qos: .utility).async {
            let exts: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "heic", "tiff", "tif", "bmp", "mp4", "mov", "pdf"]
            let skipDirs: Set<String> = ["Photos Library.photoslibrary", "Photo Booth Library", "node_modules", ".git", ".build", "Codex", "Image-Line", "Splice Projects"]
            let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isDirectoryKey]
            var roots: [(url: URL, source: String)] = [(downloadsFolder, "Downloads")]
            var seenDirs: Set<URL> = [downloadsFolder.standardizedFileURL]
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
        guard thumbnails[item.url] == nil,
              ["png", "jpg", "jpeg", "webp", "gif", "heic", "tiff", "tif", "bmp"].contains(item.ext) else { return }
        let url = item.url
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
    @Environment(\.greys) private var greys

    private var icon: NSImage {
        NSWorkspace.shared.icon(forFile: keep.path)
    }

    private var subtitle: String {
        guard keep.stillThere else { return "File moved or missing" }
        let size = (try? keep.url.resourceValues(forKeys: [.fileSizeKey, .localizedTypeDescriptionKey]))
        let bytes = size?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        let kind = size?.localizedTypeDescription
        switch (bytes, kind) {
        case let (b?, k?): return "\(b) · \(k)"
        case let (b?, nil): return b
        case let (nil, k?): return k
        default: return keep.from
        }
    }

    var body: some View {
        Button {
            if keep.stillThere {
                NSWorkspace.shared.open(keep.url)
            }
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
                    .opacity(keep.stillThere ? 1 : 0.45)

                VStack(alignment: .leading, spacing: 1) {
                    Text(keep.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(keep.stillThere ? Palette.ink : greys.muted)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(greys.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

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
        .onDrag { keep.dragged ?? NSItemProvider() }
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

private struct MediaGridCard: View {
    let item: MediaFile
    let thumbnail: NSImage?
    let open: () -> Void
    let reveal: () -> Void
    @State private var hovering = false
    @Environment(\.greys) private var greys

    var body: some View {
        Button(action: open) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(greys.hover.opacity(0.55))

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    VStack(spacing: 4) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                        Text(item.ext.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(greys.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if hovering {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    HStack(spacing: 4) {
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
                        Spacer(minLength: 0)
                        Button(action: reveal) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(.black.opacity(0.45), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Show in Finder")
                    }
                    .padding(6)
                }
            }
            .frame(height: 102)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(hovering ? Color.white.opacity(0.25) : Palette.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onDrag {
            let provider = NSItemProvider(object: item.url as NSURL)
            provider.suggestedName = item.name
            return provider
        }
        .contextMenu {
            Button("Open") { open() }
            Button("Show in Finder") { reveal() }
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(trace.url.host() ?? trace.url.absoluteString)
                        .font(.system(size: 10.5))
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
                        .font(.system(size: 10))
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
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(greys.muted)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ghost.title.isEmpty ? "Closed Tab" : ghost.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let host = ghost.url.host() {
                        Text(host)
                            .font(.system(size: 10.5))
                            .foregroundStyle(greys.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text(Self.relativeFormatter.localizedString(for: ghost.at, relativeTo: Date()))
                    .font(.system(size: 10))
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

private struct BookmarkLibraryNode: View {
    let item: Bookmark
    let browser: Browser
    let depth: Int
    @State private var expanded = false
    @Environment(\.greys) private var greys

    var body: some View {
        if item.isFolder {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    withAnimation(Motion.quick) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(greys.muted)
                            .frame(width: 10)
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                            .foregroundStyle(greys.muted)
                        Text(item.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, CGFloat(depth) * 12 + 8)
                    .padding(.trailing, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded, let children = item.children {
                    ForEach(children) { child in
                        BookmarkLibraryNode(item: child, browser: browser, depth: depth + 1)
                    }
                }
            }
        } else {
            BookmarkLibraryRow(item: item, browser: browser)
                .padding(.leading, CGFloat(depth) * 12)
        }
    }
}

private struct BookmarkLibraryRow: View {
    let item: Bookmark
    let browser: Browser
    @State private var hovering = false
    @Environment(\.greys) private var greys

    var body: some View {
        Button {
            if let url = item.address { _ = browser.open(url, foreground: true) }
        } label: {
            HStack(spacing: 8) {
                if let url = item.address {
                    LibraryFavicon(url: url)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "bookmark")
                        .font(.system(size: 11))
                        .foregroundStyle(greys.muted)
                        .frame(width: 16, height: 16)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let host = item.host {
                        Text(host)
                            .font(.system(size: 10.5))
                            .foregroundStyle(greys.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if hovering, let url = item.address {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    } label: {
                        Image(systemName: "link")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.ink.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .help("Copy Address")
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
        .contextMenu {
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
            }
        }
    }
}
