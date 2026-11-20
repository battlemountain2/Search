import SwiftUI
import AppKit

/// A frosted glass hovercard presented when hovering over a tab row in the sidebar or tab strip.
/// Displays a live or cached thumbnail preview, domain & memory badge,
/// integrated media controls (when media is present), and quick action pills.
struct TabHovercard: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    @Binding var isHoveringCard: Bool
    let onDismiss: () -> Void

    @State private var previewImage: NSImage?
    @State private var copied = false
    @State private var loadingPreview = true

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // 1. Visual Thumbnail Preview
            previewSection

            // 2. Metadata: Domain & Memory Badge
            metadataSection

            // 3. Integrated Media Bar (if tab.hasMedia or tab.isPlayingAudio)
            if tab.hasMedia || tab.isPlayingAudio || tab.stilled {
                mediaBarSection
            }

            // 4. Quick Action Pill Buttons (bottom row)
            quickActionsSection
        }
        .padding(10)
        .frame(width: 295)
        .background(
            ZStack {
                VisualEffectView(material: .popover, blendingMode: .withinWindow)
                Palette.ground.opacity(0.85)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.hairline.opacity(0.8), lineWidth: 0.8)
        )
        .onHover { over in
            isHoveringCard = over
            if !over {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    if !isHoveringCard {
                        onDismiss()
                    }
                }
            }
        }
        .onAppear {
            fetchPreview()
        }
    }

    // MARK: - 1. Thumbnail Preview

    @ViewBuilder
    private var previewSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.ink.opacity(0.04))

            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 250, height: 140)
                    .clipped()
            } else if loadingPreview {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                VStack(spacing: 6) {
                    Mark(icon: tab.icon, letter: tab.monogram, size: 28)
                    Text(tab.label)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                .padding(12)
            }
        }
        .frame(width: 250, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Palette.hairline.opacity(0.7), lineWidth: 0.5)
        )
    }

    private func fetchPreview() {
        tab.preview(width: 250) { image in
            self.previewImage = image
            self.loadingPreview = false
        }
    }

    // MARK: - 2. Domain & Memory Badge

    @ViewBuilder
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(tab.address?.host() ?? tab.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)

                Spacer(minLength: 4)

                memoryBadge
            }

            Text(tab.title.isEmpty ? tab.label : tab.title)
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var memoryBadge: some View {
        if tab.asleep {
            let saved = Browser.isHeavyTab(tab) ? "450" : "180"
            Text("Asleep (Saved ~\(saved) MB)")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.purple.opacity(0.95))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.12), in: Capsule())
        } else if tab.noisy {
            let memStr = tab.activeMemoryMB.map { " (\($0) MB)" } ?? ""
            Text("Playing\(memStr)")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Palette.safe)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Palette.safe.opacity(0.12), in: Capsule())
        } else if tab.throttled {
            let memStr = tab.activeMemoryMB.map { " (\($0) MB)" } ?? ""
            Text("Throttled\(memStr)")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Palette.unsafe)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Palette.unsafe.opacity(0.12), in: Capsule())
        } else {
            let memText = tab.activeMemoryMB.map { "\($0) MB" } ?? "Active"
            Text(memText)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Palette.ink.opacity(0.06), in: Capsule())
        }
    }

    // MARK: - 3. Integrated Media Bar

    @ViewBuilder
    private var mediaBarSection: some View {
        HStack(spacing: 8) {
            // Play / Pause Toggle
            Button(action: {
                Haptics.tap()
                tab.togglePlayback()
            }) {
                Image(systemName: tab.stilled ? "play.fill" : (tab.noisy || tab.playingVideo ? "pause.fill" : "play.fill"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 22, height: 22)
                    .background(Palette.ink.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .help(tab.stilled ? "Play" : "Pause")

            // Mute / Unmute Toggle
            Button(action: {
                Haptics.tap()
                tab.toggleMute()
            }) {
                Image(systemName: tab.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tab.muted ? Palette.unsafe : Palette.ink)
                    .frame(width: 22, height: 22)
                    .background(Palette.ink.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .help(tab.muted ? "Unmute" : "Mute")

            // Clean Status or Track Title (deduplicates against page title)
            mediaLabel

            Spacer(minLength: 0)

            if tab.noisy {
                // Mini Equalizer Bars
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Palette.safe)
                        .frame(width: 2, height: 8)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Palette.safe)
                        .frame(width: 2, height: 12)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Palette.safe)
                        .frame(width: 2, height: 6)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Palette.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Palette.hairline.opacity(0.6), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var mediaLabel: some View {
        let isDuplicate = tab.label.trimmingCharacters(in: .whitespaces).lowercased() == tab.title.trimmingCharacters(in: .whitespaces).lowercased()
        if isDuplicate || tab.label.isEmpty {
            Text(tab.stilled ? "Audio Paused" : (tab.muted ? "Audio Muted" : "Now Playing"))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.muted)
        } else {
            Text(tab.label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.ink.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - 4. Quick Action Pill Buttons

    @ViewBuilder
    private var quickActionsSection: some View {
        HStack(spacing: 4) {
            // 📌 Pin Tab Pill
            HovercardPill(
                icon: tab.pin != nil ? "pin.fill" : "pin",
                label: tab.pin != nil ? "Unpin" : "Pin",
                iconColor: tab.pin != nil ? Palette.ink : nil
            ) {
                browser.pins.toggle(tab)
            }

            // ⭐ Bookmark Pill
            let bookmarked = tab.address.map { browser.bookmarks.contains($0) } ?? false
            HovercardPill(
                icon: bookmarked ? "star.fill" : "star",
                label: bookmarked ? "Saved" : "Save",
                iconColor: bookmarked ? Color.yellow : nil
            ) {
                browser.bookmarks.toggle(tab)
            }

            // ◫ Split View Pill (ALWAYS present on every tab!)
            let isCurrentTabSplit = browser.prefs.splitView && (browser.active?.id == tab.id || browser.splitPair?.left.id == tab.id || browser.splitPair?.right.id == tab.id)
            HovercardPill(
                icon: "rectangle.split.2x1",
                label: isCurrentTabSplit ? "Unsplit" : "Split",
                iconColor: isCurrentTabSplit ? Color.accentColor : nil
            ) {
                Haptics.click()
                if let activeTab = browser.active, activeTab.id != tab.id {
                    // Hovering a background tab: pair it side-by-side with active
                    if !browser.prefs.splitView {
                        browser.prefs.splitView = true
                    }
                    browser.pair(tab, with: activeTab, onLeft: false)
                } else {
                    // Hovering the active tab: toggle split view on/off
                    browser.splitKey()
                }
            }

            // 🔗 Copy Link Pill
            HovercardPill(
                icon: copied ? "checkmark" : "link",
                label: copied ? "Copied" : "Copy",
                iconColor: copied ? Palette.safe : nil
            ) {
                if let url = tab.address {
                    CleanLink.copy(url)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        copied = false
                    }
                }
            }

            // 💤 Sleep Now Pill
            HovercardPill(
                icon: "moon.zzz.fill",
                label: tab.asleep ? "Sleeping" : "Sleep",
                iconColor: tab.asleep ? Color.purple.opacity(0.7) : nil,
                disabled: tab.asleep || browser.awake(because: tab) != nil
            ) {
                browser.sleep(tab)
            }
        }
    }
}

private struct HovercardPill: View {
    let icon: String
    let label: String
    var iconColor: Color? = nil
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(iconColor ?? (disabled ? Palette.muted.opacity(0.4) : Palette.ink))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(disabled ? Palette.muted.opacity(0.5) : Palette.ink)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering && !disabled ? Palette.ink.opacity(0.08) : Palette.ink.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Palette.hairline.opacity(0.6), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}
