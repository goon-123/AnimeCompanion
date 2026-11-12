import SwiftUI
import UIKit
import QuartzCore
import AnimeCore

/// Visibility belongs to the single native tab controller. Navigation keeps its
/// own delegates and interactive back gesture, including cancellation recovery.
@MainActor
final class CompanionDockPresentation: ObservableObject {
    private var hiddenScreens: [AppTab: Set<UUID>] = [:]
    private var selection: AppTab = .home
    private var reduceMotion = false
    private weak var controller: UITabBarController?
    private var hidden: Bool { !(hiddenScreens[selection] ?? []).isEmpty }

    func mount(_ controller: UITabBarController, selection: AppTab, reduceMotion: Bool) {
        self.controller = controller
        configure(selection: selection, reduceMotion: reduceMotion)
    }
    func configure(selection: AppTab, reduceMotion: Bool) {
        self.selection = selection; self.reduceMotion = reduceMotion
        apply(animated: false)
    }
    func setHidden(_ active: Bool, screen: UUID, tab: AppTab,
                   coordinator: UIViewControllerTransitionCoordinator? = nil) {
        let wasHidden = hidden
        if active { hiddenScreens[tab, default: []].insert(screen) }
        else { hiddenScreens[tab]?.remove(screen) }
        guard wasHidden != hidden else { return }
        apply(animated: coordinator?.isAnimated == true)
    }
    private func apply(animated: Bool) {
        if #available(iOS 18.0, *), let controller, controller.isTabBarHidden != hidden {
            controller.setTabBarHidden(hidden, animated: animated && !reduceMotion)
        }
    }
}

private struct CompanionDockPresentationKey: EnvironmentKey {
    static let defaultValue: CompanionDockPresentation? = nil
}
private struct CompanionDockTabKey: EnvironmentKey { static let defaultValue = AppTab.home }
private struct BrowseInteractionReadyKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var browseInteractionReady: Bool {
        get { self[BrowseInteractionReadyKey.self] }
        set { self[BrowseInteractionReadyKey.self] = newValue }
    }
    var companionDockPresentation: CompanionDockPresentation? {
        get { self[CompanionDockPresentationKey.self] }
        set { self[CompanionDockPresentationKey.self] = newValue }
    }
    var companionDockTab: AppTab {
        get { self[CompanionDockTabKey.self] }
        set { self[CompanionDockTabKey.self] = newValue }
    }
}

extension View {
    func companionDockHidden() -> some View { modifier(CompanionDockHidden()) }
}

private struct CompanionDockHidden: ViewModifier {
    @Environment(\.companionDockPresentation) private var presentation
    @Environment(\.companionDockTab) private var tab
    func body(content: Content) -> some View {
        content.toolbar(.hidden, for: .tabBar)
            .ignoresSafeArea(.container, edges: presentation == nil ? [] : .bottom)
            .background {
                if let presentation { DockVisibilityBridge(presentation: presentation, tab: tab) }
            }
    }
}

private struct DockVisibilityBridge: UIViewControllerRepresentable {
    let presentation: CompanionDockPresentation
    let tab: AppTab
    func makeUIViewController(context: Context) -> DockVisibilityController {
        DockVisibilityController(presentation: presentation, tab: tab)
    }
    func updateUIViewController(_ controller: DockVisibilityController, context: Context) {}
    static func dismantleUIViewController(_ controller: DockVisibilityController, coordinator: ()) {
        controller.detach()
    }
}

private final class DockVisibilityController: UIViewController {
    private let presentation: CompanionDockPresentation
    private let appTab: AppTab
    private let screen = UUID()
    private var active = false
    private var revision = 0

    init(presentation: CompanionDockPresentation, tab: AppTab) {
        self.presentation = presentation; self.appTab = tab
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        let view = UIView(); view.backgroundColor = .clear; view.isUserInteractionEnabled = false
        self.view = view
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); change(to: true) }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); change(to: false) }

    private func change(to visible: Bool) {
        let previous = active
        active = visible; revision += 1
        let currentRevision = revision
        let coordinator = transitionCoordinator
        presentation.setHidden(visible, screen: screen, tab: appTab, coordinator: coordinator)
        coordinator?.animate(alongsideTransition: nil) { [weak self] context in
            guard let self, context.isCancelled, self.revision == currentRevision else { return }
            self.active = previous
            self.presentation.setHidden(previous, screen: self.screen, tab: self.appTab)
        }
    }
    func detach() {
        revision += 1; active = false
        presentation.setHidden(false, screen: screen, tab: appTab)
    }
}

/// Only actual environment/layout changes replace a hosting root. Data stores
/// observe their own changes; a tab tap must not reassign every catalog root.
private struct CompanionTabEnvironment: Equatable {
    let scheme: ColorScheme
    let typeSize: DynamicTypeSize
    let horizontal: UserInterfaceSizeClass?
    let vertical: UserInterfaceSizeClass?
    let scale: CGFloat
    let direction: LayoutDirection
    let locale: String
    let timeZone: String
    let calendar: String
    let legibility: String
    let contrast: String
    let differentiateColors: Bool
    let viewport: CGFloat?
    let reduceTransparency: Bool
    let reduceMotion: Bool
    let interactionReady: Bool
    init(_ environment: EnvironmentValues) {
        scheme = environment.colorScheme; typeSize = environment.dynamicTypeSize
        horizontal = environment.horizontalSizeClass; vertical = environment.verticalSizeClass
        scale = environment.displayScale; direction = environment.layoutDirection
        locale = environment.locale.identifier; timeZone = environment.timeZone.identifier
        calendar = String(describing: environment.calendar.identifier)
        legibility = String(describing: environment.legibilityWeight)
        contrast = String(describing: environment.colorSchemeContrast)
        differentiateColors = environment.accessibilityDifferentiateWithoutColor
        viewport = environment.animeBrowseViewportHeight
        reduceTransparency = environment.accessibilityReduceTransparency
        reduceMotion = environment.accessibilityReduceMotion
        // Launch initially hides accessibility and interaction. Refresh the
        // copied environment once at reveal, never on ordinary tab selection.
        interactionReady = environment.browseInteractionReady
    }
}
@MainActor
private final class CompanionTabActivity: ObservableObject {
    @Published private(set) var phase = ScenePhase.inactive
    func set(_ phase: ScenePhase) { if self.phase != phase { self.phase = phase } }
}
private struct CompanionActivePane<Content: View>: View {
    @ObservedObject var activity: CompanionTabActivity
    let content: Content
    var body: some View { content.environment(\.scenePhase, activity.phase) }
}

/// UIKit owns the Liquid Glass bar and lens; only page content crossfades.
@available(iOS 26.0, *)
struct CompanionNativeTabs<Content: View>: UIViewControllerRepresentable {
    let presentation: CompanionDockPresentation
    let tabs: [AppTab]
    @Binding var selection: AppTab
    let reduceMotion: Bool
    let contentKey: (AppTab) -> String
    @ViewBuilder let content: (AppTab) -> Content

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UITabBarController {
        let controller = UITabBarController()
        controller.mode = .tabBar
        controller.delegate = context.coordinator
        controller.view.backgroundColor = UIColor(Theme.background)
        controller.view.tintColor = UIColor(Theme.accent)
        controller.tabBar.accessibilityIdentifier = "companion-dock"
        update(controller, context: context)
        return controller
    }
    func updateUIViewController(_ controller: UITabBarController, context: Context) {
        context.coordinator.parent = self
        update(controller, context: context)
    }
    private func update(_ controller: UITabBarController, context: Context) {
        let coordinator = context.coordinator
        let stamp = CompanionTabEnvironment(context.environment)
        let environmentChanged = stamp != coordinator.environmentStamp
        var hosts: [UIViewController] = []
        for tab in tabs {
            let key = contentKey(tab)
            let activity = coordinator.activities[tab] ?? CompanionTabActivity()
            coordinator.activities[tab] = activity
            activity.set(tab == selection ? context.environment.scenePhase : .inactive)
            let host: UIHostingController<AnyView>
            if let existing = coordinator.hosts[tab], !environmentChanged, coordinator.contentKeys[tab] == key {
                host = existing
            } else {
                // Whole environment outside, narrow per-tab overrides inside.
                let root = AnyView(CompanionActivePane(activity: activity, content: content(tab))
                    .environment(\.companionDockPresentation, presentation)
                    .environment(\.companionDockTab, tab)
                    .environment(\.self, context.environment))
                if let existing = coordinator.hosts[tab] {
                    existing.rootView = root; host = existing
                    coordinator.rootReassignments += 1
                } else {
                    host = UIHostingController(rootView: root)
                    host.tabBarItem = UITabBarItem(title: tab.title, image: UIImage(systemName: tab.symbol), selectedImage: UIImage(systemName: tab.symbol + ".fill"))
                    host.tabBarItem.accessibilityIdentifier = "dock-tab-" + tab.rawValue
                    coordinator.hosts[tab] = host
                }
                coordinator.contentKeys[tab] = key
            }
            hosts.append(host)
        }
        coordinator.environmentStamp = stamp
        let orderChanged = coordinator.order != tabs
        if orderChanged {
            controller.setViewControllers(hosts, animated: false)
            coordinator.order = tabs
            coordinator.hosts = coordinator.hosts.filter { tabs.contains($0.key) }
            coordinator.activities = coordinator.activities.filter { tabs.contains($0.key) }
            coordinator.contentKeys = coordinator.contentKeys.filter { tabs.contains($0.key) }
        }
        // Provider updates may arrive before UIKit's didSelect callback. Only
        // apply a changed binding, never rewind a native selection in flight.
        if orderChanged || coordinator.boundSelection != selection {
            coordinator.boundSelection = selection
            if let index = tabs.firstIndex(of: selection), controller.selectedIndex != index {
                controller.selectedIndex = index
            }
        }
        presentation.mount(controller, selection: selection, reduceMotion: reduceMotion)
        coordinator.scenePhase = context.environment.scenePhase
        if context.environment.browseInteractionReady, context.environment.scenePhase == .active {
            coordinator.prepareIdleTabs(in: controller)
        } else { coordinator.warmup?.cancel(); coordinator.warmup = nil }
    }
    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var parent: CompanionNativeTabs
        var hosts: [AppTab: UIHostingController<AnyView>] = [:]
        fileprivate var activities: [AppTab: CompanionTabActivity] = [:]
        fileprivate var environmentStamp: CompanionTabEnvironment?
        var contentKeys: [AppTab: String] = [:]
        var order: [AppTab] = []
        var boundSelection: AppTab?
        var scenePhase = ScenePhase.active
        var rootReassignments = 0
        var warmup: Task<Void, Never>?
        #if DEBUG
        private var probe: DockSwitchProbe?
        #endif
        init(_ parent: CompanionNativeTabs) { self.parent = parent }
        deinit { warmup?.cancel() }
        func prepareIdleTabs(in controller: UITabBarController) {
            guard warmup == nil, hosts.values.contains(where: { !$0.isViewLoaded }) else { return }
            warmup = Task { @MainActor [weak self, weak controller] in
                defer { self?.warmup = nil }
                guard let self else { return }
                for tab in self.order {
                    do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
                    guard !Task.isCancelled, let controller, self.scenePhase == .active else { return }
                    guard let host = self.hosts[tab], !host.isViewLoaded else { continue }
                    // Native backing views only. Do not lay out an offscreen
                    // Spotlight with fake safe areas or start synthetic appearances.
                    if Self.isScrolling(controller.selectedViewController?.viewIfLoaded) { continue }
                    host.loadViewIfNeeded()
                }
            }
        }
        private static func isScrolling(_ view: UIView?) -> Bool {
            guard let view else { return false }
            if let scroll = view as? UIScrollView, scroll.isTracking || scroll.isDragging || scroll.isDecelerating { return true }
            return view.subviews.contains { isScrolling($0) }
        }
        func tabBarController(_ controller: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-tab-performance"), viewController !== controller.selectedViewController {
                probe?.cancel()
                probe = DockSwitchProbe(rootReassignments: rootReassignments)
            }
            #endif
            return true
        }
        func tabBarController(_ controller: UITabBarController, didSelect viewController: UIViewController) {
            guard let index = controller.viewControllers?.firstIndex(of: viewController), order.indices.contains(index) else { return }
            let tab = order[index]
            parent.presentation.configure(selection: tab, reduceMotion: parent.reduceMotion)
            parent.selection = tab
        }
        func tabBarController(_ controller: UITabBarController,
                              animationControllerForTransitionFrom fromVC: UIViewController,
                              to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
            CompanionTabTransition(reduceMotion: parent.reduceMotion) { [weak self, weak controller] in
                #if DEBUG
                guard let self, let controller else { return }
                self.probe?.finish(on: controller.tabBar, rootReassignments: self.rootReassignments)
                self.probe = nil
                #endif
            }
        }
    }
}

final class CompanionTabTransition: NSObject, UIViewControllerAnimatedTransitioning {
    let reduceMotion: Bool
    let completed: () -> Void
    init(reduceMotion: Bool, completed: @escaping () -> Void = {}) { self.reduceMotion = reduceMotion; self.completed = completed }
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        reduceMotion ? 0 : 0.12
    }
    func animateTransition(using context: UIViewControllerContextTransitioning) {
        guard let destination = context.view(forKey: .to), let controller = context.viewController(forKey: .to) else {
            context.completeTransition(false); completed(); return
        }
        destination.frame = context.finalFrame(for: controller)
        context.containerView.addSubview(destination)
        destination.alpha = reduceMotion ? 1 : 0
        UIView.animate(withDuration: transitionDuration(using: context), delay: 0,
                       options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
            destination.alpha = 1
        } completion: { _ in
            let success = !context.transitionWasCancelled
            if !success { destination.removeFromSuperview() }
            destination.alpha = 1
            context.completeTransition(success)
            self.completed()
        }
    }
}

#if DEBUG
/// Owned native test measurements, including destination view construction and
/// main-run-loop frame gaps. Never exposed in Release or used as production data.
@MainActor
private final class DockSwitchProbe: NSObject {
    private let started = CACurrentMediaTime()
    private let roots: Int
    private var lastFrame = CACurrentMediaTime()
    private var largestGap: Double = 0
    private var link: CADisplayLink?
    init(rootReassignments: Int) {
        roots = rootReassignments
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(frame))
        self.link = link; link.add(to: .main, forMode: .common)
    }
    @objc private func frame() {
        let now = CACurrentMediaTime()
        largestGap = max(largestGap, now - lastFrame); lastFrame = now
    }
    func cancel() { link?.invalidate(); link = nil }
    func finish(on bar: UITabBar, rootReassignments: Int) {
        cancel()
        let result: [String: Double] = ["milliseconds": (CACurrentMediaTime() - started) * 1000,
            "largestFrameGapMS": largestGap * 1000, "rootReassignments": Double(rootReassignments - roots)]
        if let data = try? JSONSerialization.data(withJSONObject: result), let value = String(data: data, encoding: .utf8) {
            bar.accessibilityValue = value
            print("Owned dock switch: " + value)
        }
    }
}
#endif
