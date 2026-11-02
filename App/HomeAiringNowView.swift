import SwiftUI

/// A Home destination independent of the calendar's weekly controls and filters.
struct HomeAiringNowView: View {
    @State private var settings = false
    var body: some View {
        AiringNowView(showSettings: $settings)
            .background(Theme.background).navigationTitle("Airing now").navigationBarTitleDisplayMode(.inline)
            .animeNavigation().appSettingsSheet(isPresented: $settings)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { settings = true } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("Account and settings")
            } }
    }
}
