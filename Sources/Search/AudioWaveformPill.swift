import SwiftUI

/// Animated equalizer waveform displayed on tabs playing audio, expanding on hover
/// to provide 1-click Play/Pause and Mute/Unmute controls without switching tabs.
struct AudioWaveformPill: View {
    @ObservedObject var tab: Tab

    @State private var isHovering = false
    @State private var playHovering = false
    @State private var muteHovering = false

    var body: some View {
        Group {
            if isHovering {
                // Expanded 1-click media control bar
                HStack(spacing: 2) {
                    // 1-Click Play / Pause toggle
                    Button(action: { tab.togglePlayback() }) {
                        Image(systemName: tab.stilled ? "play.fill" : (tab.noisy || tab.playingVideo ? "pause.fill" : "play.fill"))
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 17, height: 17)
                            .background(playHovering ? Palette.ink.opacity(0.12) : Color.clear, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()
                    .onHover { playHovering = $0 }
                    .help(tab.stilled ? "Play" : "Pause")

                    // 1-Click Mute / Unmute toggle
                    Button(action: { tab.toggleMute() }) {
                        Image(systemName: tab.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(tab.muted ? Palette.unsafe : Palette.muted)
                            .frame(width: 17, height: 17)
                            .background(muteHovering ? Palette.ink.opacity(0.12) : Color.clear, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()
                    .onHover { muteHovering = $0 }
                    .help(tab.muted ? "Unmute Tab" : "Mute Tab")
                }
                .padding(.horizontal, 3)
                .frame(height: 19)
                .background(
                    Capsule()
                        .fill(Palette.ink.opacity(0.08))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Palette.hairline.opacity(0.8), lineWidth: 0.5)
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.85, anchor: .trailing).combined(with: .opacity),
                    removal: .scale(scale: 0.85, anchor: .trailing).combined(with: .opacity)
                ))
            } else {
                // Compact resting waveform or speaker icon
                ZStack {
                    if tab.muted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Palette.muted)
                    } else if tab.stilled {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 7.5))
                            .foregroundStyle(Palette.muted)
                    } else if tab.isPlayingAudio {
                        EqualizerView(isPlaying: true, tint: Palette.safe)
                    } else {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Palette.muted)
                    }
                }
                .frame(width: 17, height: 17)
                .contentShape(Rectangle())
            }
        }
        .onHover { over in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                isHovering = over
            }
        }
    }
}

/// SwiftUI animated equalizer view with 4 rhythmic pulsing bars.
struct EqualizerView: View {
    var isPlaying: Bool = true
    var tint: Color = Palette.safe

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            EqualizerBar(minHeight: 3, maxHeight: 11, duration: 0.42, delay: 0.0, isPlaying: isPlaying, tint: tint)
            EqualizerBar(minHeight: 4, maxHeight: 13, duration: 0.32, delay: 0.12, isPlaying: isPlaying, tint: tint)
            EqualizerBar(minHeight: 3, maxHeight: 9, duration: 0.48, delay: 0.05, isPlaying: isPlaying, tint: tint)
            EqualizerBar(minHeight: 2, maxHeight: 12, duration: 0.38, delay: 0.18, isPlaying: isPlaying, tint: tint)
        }
        .frame(width: 13, height: 13, alignment: .bottom)
    }
}

private struct EqualizerBar: View {
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let duration: Double
    let delay: Double
    let isPlaying: Bool
    let tint: Color

    @State private var animating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(tint)
            .frame(width: 2, height: animating && isPlaying ? maxHeight : minHeight)
            .onAppear {
                if isPlaying {
                    withAnimation(
                        Animation.easeInOut(duration: duration)
                            .repeatForever(autoreverses: true)
                            .delay(delay)
                    ) {
                        animating = true
                    }
                }
            }
            .onChange(of: isPlaying) { _, playing in
                if playing {
                    withAnimation(
                        Animation.easeInOut(duration: duration)
                            .repeatForever(autoreverses: true)
                            .delay(delay)
                    ) {
                        animating = true
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        animating = false
                    }
                }
            }
    }
}
