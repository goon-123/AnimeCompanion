import SwiftUI

/// Display branding is separate from persistence, bundle IDs and URL schemes so
/// this release updates existing installations without losing their saved data.
enum AniNextBrand {
    static let background = Color(red: 1, green: 248.0 / 255, blue: 237.0 / 255)
    static let ink = Color(red: 49.0 / 255, green: 14.0 / 255, blue: 76.0 / 255)
    static let lavender = Color(red: 177.0 / 255, green: 102.0 / 255, blue: 250.0 / 255)
}

struct AniNextWordmark: View {
    var body: some View {
        (Text("Ani").foregroundColor(AniNextBrand.lavender) + Text("Next").foregroundColor(AniNextBrand.ink))
            .font(.system(size: 36, weight: .bold, design: .rounded)).tracking(-1.1)
            .accessibilityLabel("AniNext")
    }
}
