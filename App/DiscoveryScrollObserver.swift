import SwiftUI
import UIKit
import AnimeCore

/// Observe the enclosing vertical scroll view, rather than a footer's estimated
/// SwiftUI frame. Also works on iOS 17 and with large lazy poster grids.
struct DiscoveryScrollObserver: UIViewRepresentable {
    let positionChanged: (Bool, Bool) -> Void

    func makeUIView(context: Context) -> Probe { Probe(positionChanged: positionChanged) }
    func updateUIView(_ view: Probe, context: Context) {
        view.positionChanged = positionChanged
        // Completion of a page/filter scan may leave the viewport near the end
        // without changing its offset. Re-evaluate after SwiftUI lays out content.
        view.scheduleReport()
    }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.detach() }

    final class Probe: UIView {
        var positionChanged: (Bool, Bool) -> Void
        private weak var scroll: UIScrollView?
        private var observations: [NSKeyValueObservation] = []
        private var reportScheduled = false
        private var userContinued = false

        init(positionChanged: @escaping (Bool, Bool) -> Void) {
            self.positionChanged = positionChanged
            super.init(frame: .zero)
            isUserInteractionEnabled = false; isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { detach() } else { scheduleReport() }
        }
        override func didMoveToSuperview() { super.didMoveToSuperview(); scheduleReport() }
        func detach() {
            scroll?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged(_:)))
            observations.removeAll(); scroll = nil
        }
        func scheduleReport() {
            guard !reportScheduled else { return }
            reportScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reportScheduled = false
                guard self.window != nil else { return }
                self.attachIfNeeded()
                guard let scroll = self.scroll else { return }
                let nearEnd = DiscoveryPaginationPolicy.isNearEnd(offset: Double(scroll.contentOffset.y),
                    viewport: Double(scroll.bounds.height), content: Double(scroll.contentSize.height),
                    bottomInset: Double(scroll.adjustedContentInset.bottom))
                let continued = self.userContinued; self.userContinued = false
                self.positionChanged(nearEnd, continued)
            }
        }
        private func attachIfNeeded() {
            var ancestor = superview
            while let view = ancestor {
                if let found = view as? UIScrollView {
                    guard scroll !== found else { return }
                    detach(); scroll = found
                    observations = [
                        found.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in Task { @MainActor in self?.scheduleReport() } },
                        found.observe(\.contentSize, options: [.new]) { [weak self] _, _ in Task { @MainActor in self?.scheduleReport() } },
                        found.observe(\.bounds, options: [.new]) { [weak self] _, _ in Task { @MainActor in self?.scheduleReport() } }
                    ]
                    found.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
                    return
                }
                ancestor = view.superview
            }
        }
        @objc private func panChanged(_ pan: UIPanGestureRecognizer) {
            if pan.state == .ended, pan.translation(in: scroll).y < -20 {
                userContinued = true; scheduleReport()
            }
        }
    }
}
