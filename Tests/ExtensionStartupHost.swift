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
    @State private var saved = false
    var body: some View {
        NavigationStack {
            VStack {
                Button("Open repository editor") { adding = true }
                    .disabled(store.busy || store.snapshot.managers.isEmpty)
                if saved { Text("Repository added") }
            }
        }
        .task { await store.load() }
        .sheet(isPresented: $adding) {
            ExtensionAddRepositorySheet(initialKind: .anime) { _, _ in saved = true }.environmentObject(store)
        }
    }
}
