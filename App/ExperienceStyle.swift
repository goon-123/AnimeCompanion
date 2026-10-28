import SwiftUI
import UIKit
import AnimeCore

/// Shared, semantic colors keep browsing, reading and provider screens coherent.
enum Theme {
    static let accent = adaptive(light: UIColor(red: 0.36, green: 0.27, blue: 0.83, alpha: 1), dark: UIColor(red: 0.76, green: 0.70, blue: 1, alpha: 1))
    static let background = adaptive(light: UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1), dark: UIColor(red: 0.045, green: 0.045, blue: 0.065, alpha: 1))
    static let surface = adaptive(light: .white, dark: UIColor(red: 0.09, green: 0.09, blue: 0.12, alpha: 1))
    static let secondarySurface = Color(uiColor: .tertiarySystemFill)
    static let border = Color.primary.opacity(0.08)
    static let highlight = adaptive(light: UIColor(red: 0.55, green: 0.32, blue: 0.01, alpha: 1), dark: .systemYellow)
    static let radius: CGFloat = 18
    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    static func scheme(_ preference: String) -> ColorScheme? {
        switch AppAppearance(rawValue: preference) ?? .system { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

struct CompanionPanel: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content.padding(padding).background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay { RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.border, lineWidth: 1).allowsHitTesting(false) }
    }
}
extension View { func companionPanel(padding: CGFloat = 16) -> some View { modifier(CompanionPanel(padding: padding)) } }

struct CompanionSectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(.primary).accessibilityAddTraits(.isHeader)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CompanionFilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(selected ? .semibold : .medium))
                .padding(.horizontal, 15).frame(minHeight: 44)
                .foregroundStyle(selected ? Theme.accent : Color.secondary)
                .background(selected ? Theme.accent.opacity(0.12) : Theme.surface, in: Capsule())
                .overlay { Capsule().stroke(selected ? Theme.accent.opacity(0.25) : Theme.border) }
                .contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct CompanionSearchLink: View {
    var body: some View {
        NavigationLink(value: ExploreSearchRoute()) {
            HStack(spacing: 11) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.accent)
                Text("Search anime, manga & novels").foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }.font(.subheadline).padding(.horizontal, 16).frame(minHeight: 52)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(Theme.border) }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// The reader canvas owns its chosen background; its controls stay legible in
/// light or dark app appearance without adding blur work to scrolling.
extension View {
    func readerControlSurface<S: Shape>(in shape: S) -> some View {
        background(Color(white: 0.10).opacity(0.97), in: shape)
            .overlay { shape.stroke(Color.white.opacity(0.12), lineWidth: 1).allowsHitTesting(false) }
    }
}
