import SwiftUI

/// Arc-style empty space canvas rendered when a space has no active tabs.
struct EmptySpaceStage: View {
    @ObservedObject var browser: Browser
    var corner: CGFloat = 0
    @State private var buttonHovered = false

    var body: some View {
        ZStack {
            if browser.prefs.homeTheme != .off {
                HomeBackground(theme: browser.prefs.homeTheme, tuning: browser.prefs.homeTuning,
                               image: browser.prefs.homeThemeImage, shuffle: browser.prefs.homeShuffle)
            } else {
                (browser.prefs.cards ? Palette.frame : Palette.ground)
            }

            if let tint = browser.space.tint {
                RadialGradient(
                    colors: [tint.opacity(0.14), .clear],
                    center: .center,
                    startRadius: 10,
                    endRadius: 260
                )
                .allowsHitTesting(false)
            }

            VStack(spacing: 18) {
                Spacer()

                VStack(spacing: 8) {
                    if let icon = browser.space.icon, !icon.isEmpty {
                        Image(systemName: icon)
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle((browser.space.tint ?? Palette.muted).opacity(0.75))
                    }
                    Text(browser.space.name)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Palette.ink.opacity(0.88))
                }

                Button {
                    Haptics.tap()
                    browser.launch()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("New Tab")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("⌘T")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Palette.muted)
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Palette.ink.opacity(buttonHovered ? 0.10 : 0.055), in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
                .onHover { buttonHovered = $0 }
                .animation(Motion.quick, value: buttonHovered)

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
