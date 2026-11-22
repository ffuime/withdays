import SwiftUI
import UIKit

/// A user's icon: their photo, or one generated from their colour and initial. Mynote has its own, the same for
/// every account. Square; callers clip it.
struct ToocIconImage: View {
    let user: ToocUser

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            if user.isMynote {
                ZStack {
                    LinearGradient(
                        colors: [Color.brand, Color.brand.mix(with: .black, by: 0.3)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Image(systemName: "note.text")
                        .font(.system(size: side * 0.44, weight: .semibold))
                        .foregroundStyle(.white)
                }
            } else if let file = user.iconFile, let photo = ToocPhotos.image(file) {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [user.color, Color(hue: user.hue + 0.08, saturation: 0.65, brightness: 0.7)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Text(user.initial)
                        .font(.system(size: side * 0.44, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    /// The same icon as a small round image, for laying inline in text at the text's size.
    @MainActor
    static func inline(_ user: ToocUser, size: CGFloat) -> UIImage {
        let renderer = ImageRenderer(content: ToocIconImage(user: user).frame(width: size, height: size).clipShape(Circle()))
        renderer.scale = 3
        return renderer.uiImage ?? UIImage()
    }
}

/// The round icon used in the lists, with a badge (pin or star) in the lower right when given.
struct ToocAvatar: View {
    let user: ToocUser
    var size: CGFloat = 52
    var badge: String?

    var body: some View {
        ToocIconImage(user: user)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    let side = size * 0.4
                    Image(systemName: badge)
                        .font(.system(size: side * 0.5, weight: .bold))
                        .rotationEffect(.degrees(badge.hasPrefix("pin") ? 45 : 0))
                        .foregroundStyle(.white)
                        .frame(width: side, height: side)
                        .background(Circle().fill(Color.brand))
                        // A ring of the background's colour, so it reads as laid on top of the icon.
                        .padding(2)
                        .background(Circle().fill(Color(.systemBackground)))
                        .offset(x: 3, y: 3)
                }
            }
            .accessibilityHidden(true)
    }
}

/// A filled circle (or capsule) with a number: a group's size, or the unread count.
struct ToocCountBadge: View {
    let count: Int
    var prominent = false

    var body: some View {
        Text(count > 999 ? "999+" : "\(count)")
            .font(.system(size: prominent ? 13 : 10, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(prominent ? Color.white : Color.secondary)
            .padding(.horizontal, prominent ? 6 : 4)
            .frame(minWidth: prominent ? 22 : 16, minHeight: prominent ? 22 : 16)
            .background(Capsule().fill(prominent ? Color.brand : Color(.tertiarySystemFill)))
    }
}

/// The background drawn from someone's icon: their icon spread over everything and blurred.
struct ToocIconBackdrop: View {
    let user: ToocUser
    var blur: CGFloat = 40

    var body: some View {
        ToocIconImage(user: user)
            .scaleEffect(1.4)
            .blur(radius: blur)
            .clipped()
    }
}
