import SwiftUI
import AnimeCore
#if canImport(Flutter)
import Flutter
import FlutterPluginRegistrant
#endif

/// One lazy, headless engine for all extension systems. The SwiftUI shell,
/// existing Keiyoushi reader, accounts and normal launch do not depend on it.
@MainActor
final class AnymeXRuntime: ObservableObject {
    static let shared = AnymeXRuntime()
    @Published var showingPlayer = false
    @Published var website: ExtensionWebsiteRequest?
    #if canImport(Flutter)
    private var engine: FlutterEngine?
    private var channel: FlutterMethodChannel?
    private var pending: [UUID: CheckedContinuation<Any?, Error>] = [:]
    private var timers: [UUID: Task<Void, Never>] = [:]
    private var websiteCompletion: FlutterResult?
    #endif
    private init() {}

    func call<T: Decodable>(_ operation: String, _ args: [String: Any] = [:], as: T.Type = T.self) async throws -> T {
        let value = try await raw(operation, args)
        let data = try JSONSerialization.data(withJSONObject: value ?? NSNull(), options: [.fragmentsAllowed])
        return try JSONDecoder().decode(T.self, from: data)
    }
    func raw(_ operation: String, _ args: [String: Any] = [:]) async throws -> Any? {
        #if canImport(Flutter)
        start()
        return try await withCheckedThrowingContinuation { continuation in
            let id = UUID()
            pending[id] = continuation
            timers[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(operation == "initialize" ? 180 : 120))
                guard !Task.isCancelled else { return }
                self?.finish(id, result: .failure(ServiceError.message("The extension timed out. Try another source or retry.")))
            }
            channel?.invokeMethod(operation, arguments: args) { [weak self] value in
                if let failure = value as? FlutterError {
                    self?.finish(id, result: .failure(ServiceError.message(failure.message ?? "The extension request failed.")))
                } else if let value, (value as AnyObject) === FlutterMethodNotImplemented {
                    self?.finish(id, result: .failure(ServiceError.message("This extension operation is unavailable.")))
                } else { self?.finish(id, result: .success(value)) }
            }
        }
        #else
        throw ServiceError.message("This build does not contain the extension runtime. Install the AnymeX-enabled IPA.")
        #endif
    }
    #if canImport(Flutter)
    private func start() {
        guard engine == nil else { return }
        let engine = FlutterEngine(name: "companion-extensions", project: nil, allowHeadlessExecution: true)
        engine.run()
        GeneratedPluginRegistrant.register(with: engine)
        let channel = FlutterMethodChannel(name: "com.animecompanion.extensions", binaryMessenger: engine.binaryMessenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(nil); return }
            if call.method == "closePlayer" { self.showingPlayer = false; result(nil) }
            else if call.method == "websiteSession", let args = call.arguments as? [String: Any],
                    let value = args["url"] as? String, let url = URL(string: value),
                    ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
                guard self.websiteCompletion == nil else { result(nil); return }
                self.websiteCompletion = result
                self.website = ExtensionWebsiteRequest(url: url)
            } else { result(FlutterMethodNotImplemented) }
        }
        self.engine = engine; self.channel = channel
    }
    private func finish(_ id: UUID, result: Result<Any?, Error>) {
        timers.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }
    func playerController() -> UIViewController {
        start()
        return FlutterViewController(engine: engine!, nibName: nil, bundle: nil)
    }
    #endif
    func playInline(_ video: ExtensionVideo, title: String) async throws {
        var args = video.arguments; args["title"] = title
        _ = try await raw("playVideo", args)
        showingPlayer = true
    }
    func stopVideo() { Task { _ = try? await raw("stopVideo") } }
    func finishWebsite(cookies: String = "", userAgent: String = "", solved: Bool = false) {
        #if canImport(Flutter)
        let completion = websiteCompletion; websiteCompletion = nil
        completion?(["cookies": cookies, "userAgent": userAgent, "solved": solved])
        #endif
        website = nil
    }
    /// Close Isar/plugin handles before Reset erases application support.
    func shutdownForReset() async {
        showingPlayer = false; finishWebsite()
        #if canImport(Flutter)
        if engine != nil { _ = try? await raw("shutdown") }
        for id in Array(pending.keys) { finish(id, result: .failure(CancellationError())) }
        channel?.setMethodCallHandler(nil)
        engine?.destroyContext(); engine = nil; channel = nil
        #endif
    }
}

struct ExtensionWebsiteRequest: Identifiable { let id = UUID(); let url: URL }

struct AnymeXPlayerContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        #if canImport(Flutter)
        return AnymeXRuntime.shared.playerController()
        #else
        return UIViewController()
        #endif
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

@MainActor
final class UnifiedExtensionStore: ObservableObject {
    @Published private(set) var snapshot = UnifiedExtensionSnapshot()
    @Published private(set) var busy = false
    @Published var error: String?
    @Published var status = ""
    let runtime = AnymeXRuntime.shared
    private var loaded = false
    func load() async { guard !loaded else { return }; await update("initialize"); loaded = !snapshot.managers.isEmpty }
    func update(_ operation: String, _ arguments: [String: Any] = [:]) async {
        guard !busy else { return }
        busy = true; error = nil
        switch operation {
        case "initialize": status = "Loading your sources…"
        case "install": status = "Installing source…"
        case "uninstall": status = "Removing source…"
        case "addRepo": status = "Adding repository…"
        case "removeRepo": status = "Removing repository…"
        case "refresh", "retry": status = "Checking sources…"
        default: status = "Updating sources…"
        }
        defer { busy = false; status = "" }
        do { snapshot = try await runtime.call(operation, arguments) }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    func mutate(_ operation: String, source: UnifiedExtensionSource) async { await update(operation, source.arguments) }
    func request<T: Decodable>(_ operation: String, source: UnifiedExtensionSource, arguments: [String: Any] = [:], as: T.Type = T.self) async throws -> T {
        var args = source.arguments.merging(arguments) { _, new in new }
        let token = UUID().uuidString; args["token"] = token
        return try await withTaskCancellationHandler {
            let result: T = try await runtime.call(operation, args)
            try Task.checkCancellation()
            return result
        } onCancel: {
            Task { @MainActor in _ = try? await AnymeXRuntime.shared.raw("cancel", ["token": token]) }
        }
    }
}
