import SwiftUI

/// Go: the next target time of the selected preset and how long is left, centred on the screen.
/// Hold anywhere for the presets (whose top-right button goes back to the calendar); swipe up or down for brightness.
/// With something playing in the Music app, a music row is laid over the bottom (never moving the countdown), and a
/// swipe left or right anywhere skips to the next or previous song.
struct GoView: View {
    var onCalendar: () -> Void

    @Environment(GoStore.self) private var go
    @State private var showPresets = false
    /// The brightness when the swipe began, and what it is now (shown while swiping).
    @State private var brightnessStart: CGFloat?
    @State private var brightness: CGFloat = 0
    @State private var music = GoMusic()
    /// The screen's width, for the music row (two thirds of it).
    @State private var width: CGFloat = 0
    /// The music row's frame, and where the touch in progress began, so holding the row doesn't open the presets.
    @State private var musicFrame: CGRect = .zero
    @State private var pressStart: CGPoint?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            countdown(now: context.date)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // Laid over the bottom, apart from the countdown: showing, hiding or changing it moves nothing else.
        .overlay(alignment: .bottom) {
            if music.visible {
                GoMusicBar(music: music, width: width * 2 / 3)
                    .padding(.bottom, 16)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { musicFrame = $0 }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: music.visible)
        .overlay(alignment: .top) {
            if brightnessStart != nil {
                Label("\(Int((brightness * 100).rounded()))%", systemImage: "sun.max.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Self.goBlue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.snappy, value: brightnessStart == nil)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard let screen = Self.screen else { return }
                    if brightnessStart == nil {
                        // Vertical swipes only; sideways ones are left alone.
                        guard abs(value.translation.height) > abs(value.translation.width) else { return }
                        brightnessStart = screen.brightness
                    }
                    // A swipe across about half the screen goes from dark to bright.
                    let level = min(1, max(0, (brightnessStart ?? 0) - value.translation.height / 400))
                    screen.brightness = level
                    brightness = level
                }
                .onEnded { value in
                    let wasBrightness = brightnessStart != nil
                    brightnessStart = nil
                    // A sideways swipe (not one that turned into brightness) skips songs: left for the next one.
                    let dx = value.translation.width
                    guard !wasBrightness, music.visible, abs(dx) > 60, abs(dx) > abs(value.translation.height) * 1.5 else { return }
                    if dx < 0 { music.next() } else { music.previous() }
                }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                // Holding the music row shuffles instead (the row handles it).
                if music.visible, let start = pressStart, musicFrame.contains(start) { return }
                showPresets = true
            }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                .onChanged { value in if pressStart == nil { pressStart = value.startLocation } }
                .onEnded { _ in pressStart = nil }
        )
        .coordinateSpace(.named(Self.space))
        .sheet(isPresented: $showPresets) {
            GoPresetSheet(onCalendar: onCalendar)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: showPresets) { _, new in new }
        .sensoryFeedback(.impact(weight: .light), trigger: music.haptic)
        // The countdown stays on screen: no auto-lock while Go is open.
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            music.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            music.stop()
        }
        .task {
            // Temporary presets expire after a day, even while this screen stays open.
            while !Task.isCancelled {
                go.expireTemporary()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    @ViewBuilder
    private func countdown(now: Date) -> some View {
        if let preset = go.selectedPreset, let next = GoData.nextTarget(for: preset, now: now) {
            let seconds = max(0, Int(next.date.timeIntervalSince(now).rounded(.up)))
            VStack(spacing: 12) {
                // Target time: faint grey, as on the web.
                Text(next.time)
                    .font(.system(size: 27, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(Self.targetGrey)
                    .contentTransition(.numericText())
                if seconds >= 3600 {
                    // An hour or more to go: a clock instead of the countdown, as on the web.
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 96, weight: .ultraLight))
                        .foregroundStyle(Self.goBlue)
                } else {
                    VStack(spacing: -17) {
                        remaining(seconds / 60, unit: "分")
                        remaining(seconds % 60, unit: "秒")
                    }
                }
            }
            .animation(.snappy, value: seconds)
            .animation(.snappy, value: next.time)
        } else {
            Text("プリセットがありません")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Self.targetGrey)
        }
    }

    private static var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    private static let space = "go"

    /// #27a and #aaa from the web app.
    static let goBlue = Color(uiColor: UIColor(hex: 0x2277AA))
    private static let targetGrey = Color(uiColor: UIColor(hex: 0xAAAAAA))

    private func remaining(_ value: Int, unit: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            spacedDigits(String(format: "%02d", value), width: 76, size: 112, weight: .ultraLight, color: Self.goBlue)
            Text(unit)
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(Self.goBlue.opacity(0.67))
        }
    }

    /// Each character in a fixed-width slot, which spaces the digits like the web app and lets
    /// every digit roll on its own.
    private func spacedDigits(_ text: String, width: CGFloat, size: CGFloat, weight: Font.Weight, color: Color) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .font(.system(size: size, weight: weight))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText(countsDown: true))
                    .frame(width: character == ":" ? width * 0.3 : width)
            }
        }
    }
}
