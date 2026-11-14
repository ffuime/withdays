import SwiftUI

/// The corner radius iOS gives an icon of this size (a continuous rounded square).
func iconCornerRadius(_ size: CGFloat) -> CGFloat { size * 0.225 }

/// An app's icon, drawn at any size: colored glass-like tiles with each app's logo; Cal shows today's date.
struct AppIconArt: View {
    let app: SpringApp
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: iconCornerRadius(size), style: .continuous)
        ZStack {
            shape.fill(background)
            glyph
            // A soft light from above, like the system's icons.
            shape.fill(LinearGradient(
                colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                startPoint: .top, endPoint: .center
            ))
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: max(0.5, size / 120)))
        .compositingGroup()
    }

    private var background: AnyShapeStyle {
        switch app {
        case .cal: AnyShapeStyle(Color.white)
        case .todo: AnyShapeStyle(Self.gradient(0x2F8FD8, 0x065A8C))
        case .go: AnyShapeStyle(Self.gradient(0x3DD47A, 0x14965A))
        case .mo: AnyShapeStyle(Self.gradient(0xFFB547, 0xF2711C))
        case .notes: AnyShapeStyle(Self.gradient(0xFFD84D, 0xF5B400))
        case .slides: AnyShapeStyle(Self.gradient(0x2ED3D3, 0x02979A))
        case .settings: AnyShapeStyle(Self.gradient(0xA9AFB8, 0x6B717B))
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch app {
        case .cal:
            let now = Date.now
            VStack(spacing: -size * 0.02) {
                Text(now.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "ja_JP"))) + "曜日")
                    .font(.system(size: size * 0.15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.95, green: 0.23, blue: 0.2))
                Text(now.formatted(.dateTime.day()))
                    .font(.system(size: size * 0.5, weight: .regular))
                    .foregroundStyle(Color.black)
                    .monospacedDigit()
            }
            .padding(.top, size * 0.02)
        case .todo, .go, .mo:
            Image(app == .todo ? "TdLogo" : app == .go ? "GoLogo" : "MoLogo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .frame(width: size * 0.56, height: size * 0.56)
        case .notes:
            symbol("pencil.and.scribble")
        case .slides:
            symbol("rectangle.on.rectangle.angled")
        case .settings:
            symbol("gearshape.fill", scale: 0.6)
        }
    }

    private func symbol(_ name: String, scale: CGFloat = 0.46) -> some View {
        Image(systemName: name)
            .font(.system(size: size * scale, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.12), radius: size * 0.02, y: size * 0.01)
    }

    private static func gradient(_ top: UInt32, _ bottom: UInt32) -> LinearGradient {
        LinearGradient(colors: [Color(uiColor: UIColor(hex: top)), Color(uiColor: UIColor(hex: bottom))], startPoint: .top, endPoint: .bottom)
    }
}

/// A folder: a frosted tile with its first nine apps small inside.
struct FolderIconArt: View {
    let folder: SpringFolder
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: iconCornerRadius(size), style: .continuous)
        let inner = size * 0.2
        let gap = size * 0.06
        let pad = (size - inner * 3 - gap * 2) / 2
        ZStack(alignment: .topLeading) {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color.white.opacity(0.12))
            ForEach(Array(folder.apps.prefix(9).enumerated()), id: \.element) { index, app in
                AppIconArt(app: app, size: inner)
                    .offset(x: pad + CGFloat(index % 3) * (inner + gap), y: pad + CGFloat(index / 3) * (inner + gap))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: max(0.5, size / 120)))
    }
}

/// An item's icon: an app or a folder.
struct SpringIconArt: View {
    let item: SpringItem
    let size: CGFloat

    var body: some View {
        switch item {
        case .app(let app): AppIconArt(app: app, size: size)
        case .folder(let folder): FolderIconArt(folder: folder, size: size)
        }
    }
}
