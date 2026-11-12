import SwiftUI
import UIKit
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
extension EnvironmentValues {
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

/// Use the same UIKit Liquid Glass tab bar as 0.56.1. We own this controller
/// and its delegate, so a short content crossfade never replaces SwiftUI's or a
/// navigation controller's delegate. UIKit alone draws and animates the lens.
@available(iOS 26.0, *)
struct CompanionNativeTabs<Content: View>: UIViewControllerRepresentable {
    let presentation: CompanionDockPresentation
    let tabs: [AppTab]
    @Binding var selection: AppTab
    let reduceMotion: Bool
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
        var hosts: [UIViewController] = []
        for tab in tabs {
            // Retain the actual hosting controller for each tab: changing tabs
            // never rebuilds its navigation path, filters or scroll position.
            // The full environment is outermost. Per-tab overrides then apply
            // inside it; reversing this order erases the visibility coordinator.
            let root = AnyView(content(tab)
                .environment(\.companionDockPresentation, presentation)
                .environment(\.companionDockTab, tab)
                .environment(\.scenePhase, tab == selection ? context.environment.scenePhase : .inactive)
                .environment(\.self, context.environment))
            let host = coordinator.hosts[tab] ?? UIHostingController(rootView: root)
            host.rootView = root
            if coordinator.hosts[tab] == nil {
                host.tabBarItem = UITabBarItem(title: tab.title, image: UIImage(systemName: tab.symbol), selectedImage: UIImage(systemName: tab.symbol + ".fill"))
                host.tabBarItem.accessibilityIdentifier = "dock-tab-" + tab.rawValue
                coordinator.hosts[tab] = host
            }
            hosts.append(host)
        }
        if coordinator.order != tabs {
            controller.setViewControllers(hosts, animated: false)
            coordinator.order = tabs
            coordinator.hosts = coordinator.hosts.filter { tabs.contains($0.key) }
        }
        if let index = tabs.firstIndex(of: selection), controller.selectedIndex != index {
            controller.selectedIndex = index
        }
        presentation.mount(controller, selection: selection, reduceMotion: reduceMotion)
    }
    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var parent: CompanionNativeTabs
        var hosts: [AppTab: UIHostingController<AnyView>] = [:]
        var order: [AppTab] = []
        init(_ parent: CompanionNativeTabs) { self.parent = parent }
        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            guard let index = tabBarController.viewControllers?.firstIndex(of: viewController), order.indices.contains(index) else { return }
            let tab = order[index]
            parent.presentation.configure(selection: tab, reduceMotion: parent.reduceMotion)
            parent.selection = tab
        }
        func tabBarController(_ tabBarController: UITabBarController,
                              animationControllerForTransitionFrom fromVC: UIViewController,
                              to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
            CompanionTabTransition(reduceMotion: parent.reduceMotion)
        }
    }
}

/// Only the page content fades. No snapshotting or glass-layer manipulation.
final class CompanionTabTransition: NSObject, UIViewControllerAnimatedTransitioning {
    let reduceMotion: Bool
    init(reduceMotion: Bool) { self.reduceMotion = reduceMotion }
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        reduceMotion ? 0 : 0.18
    }
    func animateTransition(using context: UIViewControllerContextTransitioning) {
        guard let destination = context.view(forKey: .to), let controller = context.viewController(forKey: .to) else {
            context.completeTransition(false); return
        }
        destination.frame = context.finalFrame(for: controller)
        context.containerView.addSubview(destination)
        destination.alpha = reduceMotion ? 1 : 0
        UIView.animate(withDuration: transitionDuration(using: context), delay: 0,
                       options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
            destination.alpha = 1
        } completion: { _ in
            let completed = !context.transitionWasCancelled
            if !completed { destination.removeFromSuperview() }
            destination.alpha = 1
            context.completeTransition(completed)
        }
    }
}
