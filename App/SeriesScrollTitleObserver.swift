import SwiftUI
import UIKit
import AnimeCore

/// Observe the containing vertical scroll without replacing its delegate or
/// adding a gesture that could compete with episode cards and poster rails.
struct SeriesScrollTitleObserver: UIViewRepresentable {
    let changed: (Bool) -> Void
    func makeUIView(context: Context) -> Probe { Probe(changed: changed) }
    func updateUIView(_ view: Probe, context: Context) { view.changed = changed; view.scheduleReport() }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.detach() }

    final class Probe: UIView {
        var changed: (Bool) -> Void
        private weak var scroll: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var scheduled = false
        private var titleState = SeriesScrollTitleState()
        init(changed: @escaping (Bool) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
            isUserInteractionEnabled = false; isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { detach() } else { scheduleReport() } }
        override func didMoveToSuperview() { super.didMoveToSuperview(); scheduleReport() }
        func detach() { observation = nil; scroll = nil }
        func scheduleReport() {
            guard !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scheduled = false
                guard self.window != nil else { return }
                self.attach()
                guard let scroll = self.scroll else { return }
                let top = scroll.adjustedContentInset.top
                let maximum = max(0, scroll.contentSize.height - scroll.bounds.height + top + scroll.adjustedContentInset.bottom)
                let offset = min(maximum, max(0, scroll.contentOffset.y + top))
                let wasVisible = self.titleState.isVisible
                self.titleState.update(offset: Double(offset), userScrolling: scroll.isDragging || scroll.isDecelerating || UIAccessibility.isVoiceOverRunning)
                if wasVisible != self.titleState.isVisible { self.changed(self.titleState.isVisible) }
            }
        }
        private func attach() {
            var ancestor = superview
            while let view = ancestor {
                if let found = view as? UIScrollView {
                    guard scroll !== found else { return }
                    detach(); scroll = found
                    observation = found.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                        Task { @MainActor in self?.scheduleReport() }
                    }
                    return
                }
                ancestor = view.superview
            }
        }
    }
}
