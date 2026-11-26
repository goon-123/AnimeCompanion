import UIKit
import SwiftUI
import AnimeCore

@main
final class ExtensionStartupHost: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        if ProcessInfo.processInfo.arguments.contains("--repository-editor-ui") {
            // A public fixture only, placed on the simulator clipboard for the
            // actual native paste controls. Never compiled into the real app.
            UIPasteboard.general.string = "https://jormungandr.ofchaos.com/releases/sora/recommended/Jorm.json"
            window.rootViewController = UIHostingController(rootView: RepositoryEditorTestHost())
        } else { window.rootViewController = UIViewController() }
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

private struct RepositoryEditorTestHost: View {
    @StateObject private var store = UnifiedExtensionStore()
    @State private var adding = false
    @State private var settings = false
    @State private var saved = false
    var body: some View {
        Button("Open settings") { settings = true }
        .task { await store.load() }
        .sheet(isPresented: $settings) {
            // Match production: an app navigation stack inside Settings, with
            // repository setup pushed onto it rather than another sheet.
            AppNavigationStack {
                Form {
                    Button("Open repository editor") { adding = true }
                        .disabled(store.busy || store.snapshot.managers.isEmpty)
                    if saved { Text("Browse sources opened") }
                    ForEach(store.snapshot.managers.filter { $0.id == "sora" }) { owner in
                        ForEach(owner.repositories, id: \.url) { repo in Text(repo.url) }
                    }
                }
                .navigationTitle("Extensions")
                .navigationDestination(isPresented: $adding) {
                    ExtensionAddRepositorySheet(initialKind: .anime) { _, _ in saved = true }.environmentObject(store)
                }
            }.interactiveDismissDisabled(adding)
        }
    }
}
