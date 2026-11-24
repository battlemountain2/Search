import SwiftUI

/// Arc-style empty space canvas rendered when a space has no active tabs.
struct EmptySpaceStage: View {
    @ObservedObject var browser: Browser
    var corner: CGFloat = 0

    var body: some View {
        ZStack {
            if browser.prefs.homeTheme != .off {
                HomeBackground(theme: browser.prefs.homeTheme, tuning: browser.prefs.homeTuning,
                               image: browser.prefs.homeThemeImage, shuffle: browser.prefs.homeShuffle)
            } else {
                (browser.prefs.cards ? Palette.frame : Palette.ground)
            }

            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 8) {
                    if let icon = browser.space.icon, !icon.isEmpty {
                        Image(systemName: icon)
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(Palette.muted.opacity(0.65))
                    }
                    Text(browser.space.name)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Palette.ink.opacity(0.85))
                }

                Button {
                    Haptics.tap()
                    browser.launch()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("New Tab")
                            .font(.system(size: 13, weight: .medium))
                        Text("⌘T")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Palette.muted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())

                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            browser.launch()
        }
    }
}
