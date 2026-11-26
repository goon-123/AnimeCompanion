import SwiftUI
import UIKit
import Observation
import AnimeCore

/// Views reading semantic Theme colors observe this value, including independent
/// native tab hosts. Preferences remain portable through the existing sync file.
@Observable
final class ThemeSelection {
    static let shared = ThemeSelection()
    private(set) var preferences: AppThemePreferences
    private(set) var colors: ResolvedThemeColors
    private init() {
        let value = AppThemePreferences(saved: UserDefaults.standard.string(forKey: AppThemePreferences.storageKey))
        preferences = value; colors = ResolvedThemeColors(value)
    }
    func reload() {
        let next = AppThemePreferences(saved: UserDefaults.standard.string(forKey: AppThemePreferences.storageKey))
        if preferences != next { preferences = next; colors = ResolvedThemeColors(next) }
    }
}

struct ResolvedThemeColors {
    let accent: Color
    let background: Color
    let surface: Color
    let onAccent: Color
    init(_ preferences: AppThemePreferences) {
        let light = preferences.accentColor(dark: false), dark = preferences.accentColor(dark: true)
        accent = Theme.adaptive(light: Theme.uiColor(light), dark: Theme.uiColor(dark))
        background = Theme.adaptive(light: Theme.uiColor(ThemeRGB(hex: preferences.canvas.background(dark: false))!),
                                    dark: Theme.uiColor(ThemeRGB(hex: preferences.canvas.background(dark: true))!))
        surface = Theme.adaptive(light: Theme.uiColor(ThemeRGB(hex: preferences.canvas.surface(dark: false))!),
                                 dark: Theme.uiColor(ThemeRGB(hex: preferences.canvas.surface(dark: true))!))
        func text(on color: ThemeRGB) -> UIColor {
            color.contrast(with: ThemeRGB(hex: "000000")!) >= color.contrast(with: ThemeRGB(hex: "FFFFFF")!) ? .black : .white
        }
        onAccent = Theme.adaptive(light: text(on: light), dark: text(on: dark))
    }
}

struct ThemeSettingsControls: View {
    @AppStorage(AppThemePreferences.storageKey) private var saved = AppThemePreferences().saved
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @Environment(\.colorScheme) private var scheme
    private var preferences: AppThemePreferences { AppThemePreferences(saved: saved) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppAppearance.allCases) { Text($0.label).tag($0.rawValue) }
            }.pickerStyle(.segmented).accessibilityIdentifier("appearance-scheme")
            Text("Accent color").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84))], spacing: 10) {
                ForEach(AppAccent.allCases) { accent in
                    Button {
                        update { $0.accent = accent; $0.customAccent = nil }
                    } label: {
                        VStack(spacing: 6) {
                            Circle().fill(Color(uiColor: Theme.uiColor(ThemeRGB(hex: accent.hex(dark: scheme == .dark))!)))
                                .frame(width: 28, height: 28)
                                .overlay { if preferences.accent == accent && preferences.customAccent == nil { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(scheme == .dark ? .black : .white) } }
                            Text(accent.label).font(.caption).foregroundStyle(.primary)
                        }.frame(maxWidth: .infinity, minHeight: 62)
                            .background(Theme.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityIdentifier("theme-accent-" + accent.rawValue)
                        .accessibilityAddTraits(preferences.accent == accent && preferences.customAccent == nil ? .isSelected : [])
                }
            }
            ColorPicker("Custom accent", selection: Binding(get: {
                Color(uiColor: Theme.uiColor(ThemeRGB(hex: preferences.customAccent ?? preferences.accent.hex(dark: scheme == .dark))!))
            }, set: { color in
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
                let hex = String(format: "%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
                update { $0.customAccent = hex }
            }), supportsOpacity: false).accessibilityIdentifier("theme-custom-accent")
            Picker("Background & cards", selection: Binding(get: { preferences.canvas }, set: { canvas in update { $0.canvas = canvas } })) {
                ForEach(AppCanvas.allCases) { Text($0.label).tag($0) }
            }.accessibilityIdentifier("theme-canvas")
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack.fill").font(.title).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your next story").font(.headline)
                    Text("A preview of your colors").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.circle.fill").font(.title).foregroundStyle(Theme.accent)
            }.padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .padding(12).background(Theme.background, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityIdentifier("theme-preview")
            Text("Applies across anime, manga, navigation and controls. Accent brightness adapts for readable text in light and dark mode. The reader keeps its own page background.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Reset theme") { saved = AppThemePreferences().saved; appearance = AppAppearance.system.rawValue; ThemeSelection.shared.reload() }
                .accessibilityIdentifier("theme-reset")
        }.onChange(of: saved) { _, _ in ThemeSelection.shared.reload() }
    }
    private func update(_ change: (inout AppThemePreferences) -> Void) {
        var value = preferences; change(&value); saved = value.saved; ThemeSelection.shared.reload()
    }
}
