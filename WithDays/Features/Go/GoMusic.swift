import MediaPlayer
import SwiftUI

/// The system Music app's player, as Go shows it: what's playing, whether it plays, and whether it shuffles.
/// Kept current from the player's notifications while Go is on screen.
@MainActor
@Observable
final class GoMusic {
    private let player = MPMusicPlayerController.systemMusicPlayer
    private var observers: [NSObjectProtocol] = []

    private(set) var authorized = false
    private(set) var title = ""
    private(set) var artist = ""
    private(set) var artwork: UIImage?
    private(set) var hasItem = false
    private(set) var isPlaying = false
    private(set) var shuffleOn = false
    /// Changes on each skip, shuffle toggle and long-press shuffle, for a light haptic.
    private(set) var haptic = 0

    /// Shown only with access to the library and something to play.
    var visible: Bool { authorized && hasItem }

    func start() {
        authorized = MPMediaLibrary.authorizationStatus() == .authorized
        guard observers.isEmpty else {
            refresh()
            return
        }
        player.beginGeneratingPlaybackNotifications()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .MPMusicPlayerControllerNowPlayingItemDidChange,
            .MPMusicPlayerControllerPlaybackStateDidChange,
            // Shuffle can change in the Music app; it has no notification of its own.
            UIApplication.didBecomeActiveNotification,
        ]
        for name in names {
            let object: Any? = name == UIApplication.didBecomeActiveNotification ? nil : player
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    func stop() {
        guard !observers.isEmpty else { return }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        player.endGeneratingPlaybackNotifications()
    }

    func refresh() {
        authorized = MPMediaLibrary.authorizationStatus() == .authorized
        guard authorized, let item = player.nowPlayingItem else {
            hasItem = false
            return
        }
        hasItem = true
        title = item.title ?? ""
        artist = item.artist ?? ""
        artwork = item.artwork?.image(at: CGSize(width: 144, height: 144))
        isPlaying = player.playbackState == .playing
        shuffleOn = player.shuffleMode != .off
    }

    /// Returns whether it plays now.
    @discardableResult
    func togglePlay() -> Bool {
        if player.playbackState == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        return isPlaying
    }

    func toggleShuffle() {
        player.shuffleMode = player.shuffleMode == .off ? .songs : .off
        shuffleOn = player.shuffleMode != .off
        haptic += 1
    }

    /// Shuffles what's already queued (the queue stays) and plays.
    func shuffleQueue() {
        player.shuffleMode = .songs
        player.play()
        shuffleOn = true
        isPlaying = true
        haptic += 1
    }

    func next() {
        player.skipToNextItem()
        haptic += 1
    }

    func previous() {
        player.skipToPreviousItem()
        haptic += 1
    }
}

/// Go's music row, laid over the bottom of the screen: artwork (tap: play / pause), title over artist (scrolling when
/// too long) and shuffle. Holding the row shuffles the current queue. Plain, with no box behind it.
struct GoMusicBar: View {
    let music: GoMusic
    let width: CGFloat

    /// The play or pause symbol shown for a moment over the artwork after a tap.
    @State private var flash: String?
    @State private var flashTask: Task<Void, Never>?

    static let artworkSize: CGFloat = 48
    /// Shuffle off: black, or grey in dark mode where black wouldn't show.
    private static let shuffleOff = Color(uiColor: UIColor(light: 0x000000, dark: 0x8E8E93))

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: music.title, font: .system(size: 15, weight: .semibold), color: .primary)
                MarqueeText(text: music.artist, font: .system(size: 13, weight: .regular), color: .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: music.toggleShuffle) {
                Image(systemName: "shuffle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(music.shuffleOn ? GoView.goBlue : Self.shuffleOff)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("シャッフル")
            .accessibilityValue(music.shuffleOn ? "オン" : "オフ")
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5) { music.shuffleQueue() }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "シャッフル再生") { music.shuffleQueue() }
    }

    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Group {
            if let image = music.artwork {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(uiColor: .secondarySystemFill)
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: Self.artworkSize, height: Self.artworkSize)
        .clipShape(shape)
        .overlay {
            if let flash {
                ZStack {
                    shape.fill(Color.black.opacity(0.35))
                    Image(systemName: flash)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .transition(.opacity)
            }
        }
        .contentShape(shape)
        .onTapGesture {
            let playing = music.togglePlay()
            showFlash(playing ? "play.fill" : "pause.fill")
        }
        .accessibilityElement()
        .accessibilityLabel(music.isPlaying ? "一時停止" : "再生")
        .accessibilityAddTraits(.isButton)
    }

    private func showFlash(_ symbol: String) {
        flashTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) { flash = symbol }
        flashTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { flash = nil }
        }
    }
}

/// One line of text that, only when it doesn't fit, scrolls sideways like Apple Music: a pause, a slow scroll, and
/// soft fades at both edges. When it fits it stays still.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var started = Date.now

    private static let gap: CGFloat = 32
    private static let speed: CGFloat = 30
    private static let pause: Double = 2
    private static let fade: CGFloat = 14

    var body: some View {
        let overflows = textWidth > boxWidth + 0.5 && boxWidth > 0
        // The line's height and the box's width, whatever the text.
        label
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
            .overlay(alignment: .leading) {
                if overflows {
                    TimelineView(.animation) { context in
                        HStack(spacing: Self.gap) {
                            label
                            label
                        }
                        .offset(x: -offset(at: context.date))
                    }
                } else {
                    label
                }
            }
            .mask {
                if overflows {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: Self.fade / max(boxWidth, 1)),
                            .init(color: .black, location: 1 - Self.fade / max(boxWidth, 1)),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                } else {
                    Rectangle()
                }
            }
            .background {
                // The text's own width, measured apart from the box.
                label
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            }
            .onChange(of: text) { _, _ in started = .now }
            .accessibilityElement()
            .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }

    /// Still for the pause, then one full lap at a steady speed, over and over.
    private func offset(at date: Date) -> CGFloat {
        let lap = textWidth + Self.gap
        let scroll = Double(lap / Self.speed)
        let elapsed = date.timeIntervalSince(started).truncatingRemainder(dividingBy: Self.pause + scroll)
        guard elapsed > Self.pause else { return 0 }
        return CGFloat(elapsed - Self.pause) * Self.speed
    }
}
