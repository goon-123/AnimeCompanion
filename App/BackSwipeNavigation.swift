import SwiftUI
import UIKit
import WebKit

/// Keep UIKit's interactive back gesture first in line. A public edge recognizer
/// supplies Back when a hidden bar disables it, and closes a sheet at its root.
/// No global navigation-controller delegates or private gesture targets change.
struct AppNavigationStack<Root: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    private let path: Binding<NavigationPath>?
    private let rootBack: (() -> Void)?
    private let root: Root

    init(path: Binding<NavigationPath>? = nil, rootBack: (() -> Void)? = nil,
         @ViewBuilder content: () -> Root) {
        self.path = path; self.rootBack = rootBack; root = content()
    }

    var body: some View {
        Group {
            if let path { NavigationStack(path: path) { supportedRoot } }
            else { NavigationStack { supportedRoot } }
        }
    }
    private var supportedRoot: some View {
        root.background(BackSwipeBridge(enabled: true, rootBack: rootBack ?? (isPresented ? { dismiss() } : nil)))
    }
}

extension View {
    /// Full-screen readers/viewers use their existing close action, including
    /// saving reading progress, instead of dismissing their presenting screen.
    func backSwipe(enabled: Bool = true, action: @escaping () -> Void) -> some View {
        background(BackSwipeBridge(enabled: enabled, rootBack: action))
    }
}

private struct BackSwipeBridge: UIViewControllerRepresentable {
    let enabled: Bool
    let rootBack: (() -> Void)?
    func makeUIViewController(context: Context) -> BackSwipeController {
        let controller = BackSwipeController()
        controller.enabled = enabled; controller.rootBack = rootBack
        return controller
    }
    func updateUIViewController(_ controller: BackSwipeController, context: Context) {
        controller.enabled = enabled; controller.rootBack = rootBack
        controller.attachWhenReady()
    }
    static func dismantleUIViewController(_ controller: BackSwipeController, coordinator: ()) { controller.detach() }
}

private final class BackSwipeController: UIViewController, UIGestureRecognizerDelegate {
    var enabled = true
    var rootBack: (() -> Void)?
    private weak var host: UIViewController?
    private var pendingBack: (() -> Void)?
    private lazy var edge: UIScreenEdgePanGestureRecognizer = {
        let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(swiped(_:)))
        gesture.edges = .left; gesture.maximumNumberOfTouches = 1
        gesture.delegate = self
        return gesture
    }()

    override func loadView() {
        let view = UIView(); view.backgroundColor = .clear; view.isUserInteractionEnabled = false
        self.view = view
    }
    override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); attachWhenReady() }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); attach() }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); attach() }

    func attachWhenReady() { DispatchQueue.main.async { [weak self] in self?.attach() } }
    private func attach() {
        guard parent != nil else { return }
        let target: UIViewController
        if let navigationController { target = navigationController }
        else {
            var current: UIViewController = self
            while let parent = current.parent { current = parent }
            target = current
        }
        guard target !== host else { return }
        detach(); host = target
        target.view.addGestureRecognizer(edge)
        if let native = (target as? UINavigationController)?.interactivePopGestureRecognizer {
            // A normal push continues to use the native interactive transition.
            edge.require(toFail: native)
        }
    }
    func detach() { edge.view?.removeGestureRecognizer(edge); host = nil; pendingBack = nil }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Embedded source/add-on browsers retain their own page-back history.
        var touched = touch.view
        while let view = touched {
            if let web = view as? WKWebView, web.allowsBackForwardNavigationGestures, web.canGoBack { return false }
            touched = view.superview
        }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        pendingBack = nil
        guard enabled, let host, host.viewIfLoaded?.window != nil,
              !host.isBeingDismissed, !host.isBeingPresented, host.transitionCoordinator == nil else { return false }
        var ancestor: UIViewController? = host
        while let current = ancestor {
            if current.presentedViewController != nil { return false }
            ancestor = current.parent
        }
        let velocity = edge.velocity(in: edge.view)
        guard velocity.x > abs(velocity.y) * 1.2 else { return false }
        if let navigation = host as? UINavigationController, navigation.viewControllers.count > 1,
           let top = navigation.topViewController {
            pendingBack = { [weak navigation, weak top] in
                guard let navigation, let top, navigation.topViewController === top,
                      navigation.transitionCoordinator == nil else { return }
                navigation.popViewController(animated: true)
            }
        } else {
            // Respect interactiveDismissDisabled while an editor is saving.
            ancestor = host
            while let current = ancestor {
                if current.isModalInPresentation { return false }
                ancestor = current.parent
            }
            pendingBack = rootBack
        }
        return pendingBack != nil
    }

    @objc private func swiped(_ gesture: UIScreenEdgePanGestureRecognizer) {
        switch gesture.state {
        case .ended:
            let distance = gesture.translation(in: gesture.view).x
            let speed = gesture.velocity(in: gesture.view).x
            let threshold = min(140, max(64, (gesture.view?.bounds.width ?? 320) * 0.25))
            let action = pendingBack; pendingBack = nil
            if enabled && (distance >= threshold || (distance >= 24 && speed >= 650)) { action?() }
        case .cancelled, .failed: pendingBack = nil
        default: break
        }
    }
}
