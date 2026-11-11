import SwiftUI
import UIKit
import AnimeCore

/// The dock stays mounted outside navigation. Only its surface moves, so hiding
/// a series never changes the browse viewport or waits for iOS to rebuild a bar.
@MainActor
final class CompanionDockPresentation: ObservableObject {
    private var hiddenScreens: [AppTab: Set<UUID>] = [:]
    private var selection: AppTab = .home
    private var reduceMotion = false
    private weak var surface: UIView?

    private var hidden: Bool { !(hiddenScreens[selection] ?? []).isEmpty }

    func mount(_ view: UIView, selection: AppTab, reduceMotion: Bool) {
        surface = view; self.selection = selection; self.reduceMotion = reduceMotion
        applyImmediately()
    }

    func configure(selection: AppTab, reduceMotion: Bool) {
        let changed = self.selection != selection || self.reduceMotion != reduceMotion
        self.selection = selection; self.reduceMotion = reduceMotion
        if changed { applyImmediately() }
    }

    func setHidden(_ active: Bool, screen: UUID, tab: AppTab,
                   coordinator: UIViewControllerTransitionCoordinator? = nil) {
        let wasHidden = hidden
        if active { hiddenScreens[tab, default: []].insert(screen) }
        else { hiddenScreens[tab]?.remove(screen) }
        guard hidden != wasHidden, let surface else { return }
        surface.isUserInteractionEnabled = !hidden
        surface.accessibilityElementsHidden = hidden
        surface.superview?.isUserInteractionEnabled = !hidden
        let changes = { [weak self] in self?.applyImmediately() }
        // UIKit drives this animation with the interactive back gesture and
        // reverses it on cancellation. No navigation delegate is replaced.
        if !reduceMotion, let coordinator,
           coordinator.animate(alongsideTransition: { _ in changes() }, completion: { [weak self] _ in
               self?.applyImmediately()
           }) { return }
        UIView.animate(withDuration: reduceMotion ? 0.12 : 0.25, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
                       animations: { changes() })
    }

    private func applyImmediately() {
        guard let surface else { return }
        surface.alpha = hidden ? 0 : 1
        surface.transform = hidden && !reduceMotion ? CGAffineTransform(translationX: 0, y: 12) : .identity
        surface.isUserInteractionEnabled = !hidden
        surface.accessibilityElementsHidden = hidden
        surface.superview?.isUserInteractionEnabled = !hidden
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

/// A separate hosting surface allows the transition coordinator to animate the
/// glass without animating TabView, changing safe areas, or touching UIKit internals.
@available(iOS 26.0, *)
struct CompanionDockHost: UIViewControllerRepresentable {
    let presentation: CompanionDockPresentation
    let tabs: [AppTab]
    @Binding var selection: AppTab
    let reduceMotion: Bool
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize

    func makeUIViewController(context: Context) -> CompanionDockController {
        let controller = CompanionDockController(content: content)
        controller.loadViewIfNeeded()
        presentation.mount(controller.host.view, selection: selection, reduceMotion: reduceMotion)
        return controller
    }
    func updateUIViewController(_ controller: CompanionDockController, context: Context) {
        controller.host.rootView = content
        presentation.configure(selection: selection, reduceMotion: reduceMotion)
    }
    private var content: AnyView {
        AnyView(CompanionDock(tabs: tabs, selection: $selection)
            .environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, dynamicTypeSize))
    }
}

@available(iOS 26.0, *)
final class CompanionDockController: UIViewController {
    let host: UIHostingController<AnyView>
    init(content: AnyView) {
        host = UIHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)
        host.safeAreaRegions = []
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(host)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
}

@available(iOS 26.0, *)
private struct CompanionDock: View {
    let tabs: [AppTab]
    @Binding var selection: AppTab
    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                Button { selection = tab } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol).font(.system(size: 21, weight: .semibold))
                        Text(tab.title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                    }.frame(maxWidth: .infinity, minHeight: 48)
                        .padding(.vertical, 2)
                        .foregroundStyle(selection == tab ? Theme.accent : .primary)
                        .background(selection == tab ? Theme.accent.opacity(0.14) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }.buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
                    .accessibilityIdentifier("dock-tab-" + tab.rawValue)
            }
        }.padding(5)
            .glassEffect(.regular, in: .capsule)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isTabBar)
            .accessibilityIdentifier("companion-dock")
    }
}
