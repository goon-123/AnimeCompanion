import SwiftUI
import AnimeCore

struct HomeCatchUpView: View {
    var body: some View {
        ScrollView {
            HomeLibraryWidget(section: .catchUp, limit: 500)
                .padding(20).readableContent(width: 940)
        }.background(Theme.background).navigationTitle("Catch up").navigationBarTitleDisplayMode(.inline)
            .environment(\.posterArtworkBadgesEnabled, false)
            .toolbarBackground(Theme.background, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
    }
}
