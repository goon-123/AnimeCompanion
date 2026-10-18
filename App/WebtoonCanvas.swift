import SwiftUI
import UIKit
import AnimeCore

struct WebtoonJump: Equatable {
    let id = UUID()
    let page: Int
    let fraction: Double
}

/// A window of reusable page views, rather than a chapter-sized bitmap stack.
/// Long source images are displayed as GPU-sized slices with zero page spacing.
@MainActor
struct WebtoonCanvas: UIViewRepresentable {
    let source: MangaSourceReference
    let version: String
    let chapterKey: String
    let pages: [SourceMangaImage]
    let initial: MangaReadingPosition?
    let jump: WebtoonJump?
    let preferences: WebtoonPreferences
    let autoScroll: Bool
    let hasNext: Bool
    let loader: @Sendable (SourceMangaImage) async throws -> Data
    let onPosition: (Int, Double, Bool) -> Void
    let onTap: () -> Void
    let onDrag: () -> Void
    let onAutoStop: () -> Void
    let onNext: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WebtoonScrollView {
        let scroll = WebtoonScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 3
        scroll.showsVerticalScrollIndicator = false; scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.accessibilityIdentifier = "webtoon-canvas"
        context.coordinator.attach(scroll)
        return scroll
    }
    func updateUIView(_ view: WebtoonScrollView, context: Context) { context.coordinator.update(self) }
    static func dismantleUIView(_ view: WebtoonScrollView, coordinator: Coordinator) { coordinator.stop() }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: WebtoonCanvas
        weak var scroll: WebtoonScrollView?
        let content = UIView()
        private let end = WebtoonEndView()
        private var chapter = ""
        private var pages: [SourceMangaImage] = []
        private var ratios: [Double] = []
        private var offsets: [CGFloat] = []
        private var cells: [Int: WebtoonPageView] = [:]
        private var tasks: [Int: (UUID, Task<Void, Never>)] = [:]
        private var failures = Set<Int>()
        private var succeeded = Set<Int>()
        private var generation = UUID()
        private var pending: (Int, Double)?
        private var lastJump: UUID?
        private var layingOut = false
        private var lastWidth: CGFloat = 0
        private var lastReport = 0.0
        private var displayLink: CADisplayLink?
        private var lastTick = 0.0
        init(_ parent: WebtoonCanvas) { self.parent = parent }
        func attach(_ scroll: WebtoonScrollView) {
            self.scroll = scroll; scroll.addSubview(content); content.addSubview(end)
            scroll.onSizeChange = { [weak self] in self?.layout(preserving: self?.anchor()) }
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.delegate = self; tap.cancelsTouchesInView = false; scroll.addGestureRecognizer(tap)
            let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
            double.numberOfTapsRequired = 2; double.delegate = self; scroll.addGestureRecognizer(double); tap.require(toFail: double)
            end.action = { [weak self] in self?.parent.onNext() }
        }
        func update(_ value: WebtoonCanvas) {
            let preferencesChanged = parent.preferences != value.preferences
            parent = value
            if chapter != value.chapterKey || pages != value.pages {
                stopLoads(); generation = UUID()
                cells.values.forEach { $0.removeFromSuperview() }; cells.removeAll()
                chapter = value.chapterKey; pages = value.pages; ratios = Array(repeating: 1.7, count: pages.count)
                offsets = []; failures.removeAll(); succeeded.removeAll(); lastJump = nil
                pending = (min(max(0, value.initial?.pageIndex ?? 0), max(0, pages.count - 1)), value.initial?.fraction ?? 0)
                scroll?.setZoomScale(1, animated: false); lastWidth = 0
                layout(preserving: nil)
            } else if preferencesChanged { layout(preserving: anchor()) }
            if let jump = value.jump, jump.id != lastJump, !pages.isEmpty {
                lastJump = jump.id; pending = (min(max(0, jump.page), pages.count - 1), min(1, max(0, jump.fraction)))
                applyPending(); window()
            }
            end.button.setTitle(value.hasNext ? "Next chapter" : "Back to chapters", for: .normal)
            if value.autoScroll && displayLink == nil {
                lastTick = 0
                let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
                link.add(to: .main, forMode: .common); displayLink = link
            } else if !value.autoScroll { displayLink?.invalidate(); displayLink = nil; lastTick = 0 }
            window()
        }
        private func columnWidth(_ scroll: UIScrollView) -> CGFloat {
            min(820, scroll.bounds.width * CGFloat(1 - parent.preferences.sidePadding * 2))
        }
        private func anchor() -> (Int, CGFloat)? {
            guard let scroll, !pages.isEmpty, offsets.count == pages.count + 1 else { return nil }
            let y = max(0, scroll.contentOffset.y / scroll.zoomScale)
            let index = index(at: y)
            return (index, min(1, max(0, (y - offsets[index]) / max(1, offsets[index + 1] - offsets[index]))))
        }
        private func index(at y: CGFloat) -> Int {
            var low = 0, high = max(0, pages.count - 1)
            while low < high {
                let mid = (low + high + 1) / 2
                if offsets[mid] <= y { low = mid } else { high = mid - 1 }
            }
            return low
        }
        private func layout(preserving anchor: (Int, CGFloat)?) {
            guard let scroll, scroll.bounds.width > 0, !layingOut else { return }
            layingOut = true
            let zoom = lastWidth > 0 && abs(lastWidth - scroll.bounds.width) < 1 ? scroll.zoomScale : 1
            let oldX = scroll.contentOffset.x / max(1, scroll.zoomScale)
            if scroll.zoomScale != 1 { scroll.setZoomScale(1, animated: false) }
            lastWidth = scroll.bounds.width
            let width = columnWidth(scroll)
            offsets = [0]
            for ratio in ratios { offsets.append(offsets.last! + width * CGFloat(ratio)) }
            content.frame = CGRect(x: 0, y: 0, width: scroll.bounds.width, height: (offsets.last ?? 0) + (pages.isEmpty ? 0 : 180))
            scroll.contentSize = content.bounds.size
            let x = (scroll.bounds.width - width) / 2
            for (index, cell) in cells where index < pages.count {
                cell.frame = CGRect(x: x, y: offsets[index], width: width, height: offsets[index + 1] - offsets[index])
            }
            end.frame = CGRect(x: x + 20, y: offsets.last ?? 0, width: max(0, width - 40), height: 180)
            let background: UIColor
            switch parent.preferences.background {
            case .black: background = .black
            case .charcoal: background = UIColor(white: 0.10, alpha: 1)
            case .paper: background = UIColor(red: 0.94, green: 0.92, blue: 0.86, alpha: 1)
            }
            scroll.backgroundColor = background; content.backgroundColor = background
            end.label.textColor = parent.preferences.background == .paper ? .black : .white
            if zoom != 1 { scroll.setZoomScale(zoom, animated: false) }
            if let (index, fraction) = anchor, index < pages.count, pending == nil {
                let y = offsets[index] + fraction * (offsets[index + 1] - offsets[index])
                scroll.contentOffset = CGPoint(x: oldX * zoom, y: clamp(y * zoom))
            }
            layingOut = false
            applyPending(); window()
        }
        private func clamp(_ y: CGFloat) -> CGFloat {
            guard let scroll else { return 0 }
            return min(max(0, y), max(0, scroll.contentSize.height - scroll.bounds.height))
        }
        private func applyPending() {
            guard let scroll, let (page, fraction) = pending, offsets.count == pages.count + 1, page < pages.count else { return }
            let height = offsets[page + 1] - offsets[page]
            let y = offsets[page] + CGFloat(fraction) * height
            layingOut = true
            scroll.contentOffset = CGPoint(x: 0, y: clamp(y * scroll.zoomScale))
            layingOut = false
            if cells[page]?.hasImage == true { pending = nil; report(force: true) }
        }
        private func window() {
            guard let scroll, !layingOut, !pages.isEmpty, offsets.count == pages.count + 1, scroll.bounds.height > 0 else { return }
            let scale = max(1, scroll.zoomScale)
            let top = max(0, scroll.contentOffset.y / scale), viewport = scroll.bounds.height / scale
            let first = index(at: max(0, top - viewport * 0.6))
            let last = index(at: min(offsets.last!, top + viewport * 1.6))
            var needed = Set(first...last)
            if let pending { needed.insert(pending.0) }
            for index in Array(cells.keys) where !needed.contains(index) {
                cells.removeValue(forKey: index)?.removeFromSuperview()
                tasks.removeValue(forKey: index)?.1.cancel()
            }
            let width = columnWidth(scroll)
            for index in needed.sorted(by: { abs($0 - self.index(at: top)) < abs($1 - self.index(at: top)) }) {
                if cells[index] == nil {
                    let cell = WebtoonPageView(number: index + 1)
                    cell.frame = CGRect(x: (scroll.bounds.width - width) / 2, y: offsets[index], width: width, height: offsets[index + 1] - offsets[index])
                    cell.retry = { [weak self] in self?.retry(index) }
                    content.addSubview(cell); cells[index] = cell
                    if failures.contains(index) { cell.failed() }
                }
                if cells[index]?.hasImage == false, !failures.contains(index), tasks[index] == nil, tasks.count < 3 { load(index, refresh: false) }
            }
            content.bringSubviewToFront(end)
        }
        private func load(_ index: Int, refresh: Bool) {
            guard let scroll, index < pages.count else { return }
            let token = generation, flight = UUID(), page = pages[index], loader = parent.loader
            let key = MangaImageKey(source: parent.source.id, version: parent.version, page: page)
            let width = Int(columnWidth(scroll) * min(3, scroll.window?.screen.scale ?? UIScreen.main.scale))
            cells[index]?.loading()
            let task = Task { [weak self] in
                do {
                    let bitmap = try await MangaImagePipeline.shared.image(key: key, width: width, refresh: refresh) { try await loader(page) }
                    guard let self, !Task.isCancelled, self.generation == token, self.tasks[index]?.0 == flight else { return }
                    self.tasks.removeValue(forKey: index)
                    let anchor = self.anchor()
                    self.ratios[index] = bitmap.ratio; self.failures.remove(index); self.succeeded.insert(index)
                    self.cells[index]?.show(bitmap)
                    self.layout(preserving: anchor)
                    self.end.subtitle.text = self.succeeded.count == self.pages.count ? "You reached the end." : "Some pages have not loaded yet."
                    self.report(force: true)
                } catch is CancellationError {
                    guard let self, self.generation == token, self.tasks[index]?.0 == flight else { return }
                    self.tasks.removeValue(forKey: index)
                } catch {
                    guard let self, !Task.isCancelled, self.generation == token, self.tasks[index]?.0 == flight else { return }
                    self.tasks.removeValue(forKey: index); self.failures.insert(index)
                    self.cells[index]?.failed()
                    self.window()
                }
            }
            tasks[index] = (flight, task)
        }
        private func retry(_ index: Int) {
            failures.remove(index); tasks.removeValue(forKey: index)?.1.cancel(); load(index, refresh: true)
        }
        private func report(force: Bool = false) {
            guard let scroll, !layingOut, !pages.isEmpty, offsets.count == pages.count + 1 else { return }
            let now = CACurrentMediaTime()
            guard force || now - lastReport > 0.20 else { return }; lastReport = now
            let viewport = scroll.bounds.height / scroll.zoomScale
            let y = max(0, scroll.contentOffset.y / scroll.zoomScale)
            let page = index(at: y)
            guard cells[page]?.hasImage == true, pending == nil else { return }
            let fraction = min(1, max(0, (y - offsets[page]) / max(1, offsets[page + 1] - offsets[page])))
            let complete = y + viewport >= offsets.last! - 2 && succeeded.count == pages.count
            let token = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, let scroll = self.scroll, self.generation == token, self.pending == nil,
                      self.index(at: max(0, scroll.contentOffset.y / scroll.zoomScale)) == page else { return }
                self.parent.onPosition(page, Double(fraction), complete)
            }
        }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { guard !layingOut else { return }; window(); report() }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { guard !layingOut else { return }; window(); report(force: true) }
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { pending = nil; parent.onDrag() }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { report(force: true) } }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { report(force: true) }
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view { if current is UIControl { return false }; view = current.superview }
            return true
        }
        @objc private func tapped() { parent.onTap() }
        @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scroll else { return }
            if scroll.zoomScale > 1 { scroll.setZoomScale(1, animated: true) }
            else {
                let point = recognizer.location(in: content), scale: CGFloat = 2
                scroll.zoom(to: CGRect(x: point.x - scroll.bounds.width / scale / 2, y: point.y - scroll.bounds.height / scale / 2,
                    width: scroll.bounds.width / scale, height: scroll.bounds.height / scale), animated: true)
            }
        }
        @objc private func tick(_ link: CADisplayLink) {
            guard let scroll, parent.autoScroll, !scroll.isDragging, !scroll.isDecelerating, !scroll.isZooming else { lastTick = 0; return }
            guard !pages.isEmpty, cells[index(at: max(0, scroll.contentOffset.y / scroll.zoomScale))]?.hasImage == true else {
                lastTick = 0; parent.onAutoStop(); return
            }
            let delta = lastTick == 0 ? 0 : min(0.05, link.timestamp - lastTick); lastTick = link.timestamp
            let maximum = max(0, scroll.contentSize.height - scroll.bounds.height)
            let next = min(maximum, scroll.contentOffset.y + CGFloat(delta * parent.preferences.autoScrollSpeed))
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: next), animated: false)
            if next >= maximum - 0.5 { parent.onAutoStop(); report(force: true) }
        }
        private func stopLoads() { tasks.values.forEach { $0.1.cancel() }; tasks.removeAll() }
        func stop() {
            displayLink?.invalidate(); displayLink = nil; stopLoads()
            cells.values.forEach { $0.removeFromSuperview() }; cells.removeAll()
            scroll?.delegate = nil; scroll?.onSizeChange = nil
        }
    }
}

final class WebtoonScrollView: UIScrollView {
    var onSizeChange: (() -> Void)?
    private var previous = CGSize.zero
    override func layoutSubviews() {
        super.layoutSubviews()
        if previous != bounds.size { previous = bounds.size; onSizeChange?() }
    }
}

private final class WebtoonPageView: UIView {
    private let number: Int
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let message = UILabel()
    private let button = UIButton(type: .system)
    private var tiles: [(UIImageView, CGFloat)] = []
    private var pixelWidth: CGFloat = 1
    var retry: (() -> Void)?
    private(set) var hasImage = false
    init(number: Int) {
        self.number = number; super.init(frame: .zero)
        accessibilityIdentifier = "webtoon-page-\(number - 1)"
        spinner.color = .lightGray; addSubview(spinner)
        message.text = "This page could not load."; message.textColor = .lightGray; message.textAlignment = .center; message.font = .systemFont(ofSize: 14)
        addSubview(message)
        button.setTitle("Retry page \(number)", for: .normal); button.tintColor = UIColor(red: 0.69, green: 0.77, blue: 1, alpha: 1)
        button.accessibilityIdentifier = "webtoon-retry-\(number - 1)"
        button.addTarget(self, action: #selector(retryTapped), for: .touchUpInside); addSubview(button)
        loading()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func loading() { message.isHidden = true; button.isHidden = true; spinner.startAnimating(); setNeedsLayout() }
    func failed() { spinner.stopAnimating(); message.isHidden = false; button.isHidden = false; setNeedsLayout() }
    func show(_ bitmap: MangaBitmap) {
        tiles.forEach { $0.0.removeFromSuperview() }; tiles.removeAll()
        spinner.stopAnimating(); message.isHidden = true; button.isHidden = true
        pixelWidth = CGFloat(bitmap.image.width); hasImage = true
        for y in stride(from: 0, to: bitmap.image.height, by: 2048) {
            let height = min(2048, bitmap.image.height - y)
            guard let image = bitmap.image.cropping(to: CGRect(x: 0, y: CGFloat(y), width: CGFloat(bitmap.image.width), height: CGFloat(height))) else { continue }
            let view = UIImageView(image: UIImage(cgImage: image))
            view.contentMode = .scaleToFill; view.isAccessibilityElement = true
            view.accessibilityLabel = "Page \(number)"
            if y == 0 { view.accessibilityIdentifier = "webtoon-page-image-\(number - 1)" }
            addSubview(view); tiles.append((view, CGFloat(height)))
        }
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        var y: CGFloat = 0
        for (view, height) in tiles {
            let scaled = height * bounds.width / pixelWidth
            view.frame = CGRect(x: 0, y: y, width: bounds.width, height: scaled); y += scaled
        }
        let center = min(max(90, bounds.height / 2), 300)
        spinner.center = CGPoint(x: bounds.midX, y: center)
        message.frame = CGRect(x: 12, y: center - 25, width: max(0, bounds.width - 24), height: 25)
        button.frame = CGRect(x: 20, y: center + 8, width: max(0, bounds.width - 40), height: 44)
    }
    @objc private func retryTapped() { retry?() }
}

private final class WebtoonEndView: UIView {
    let label = UILabel(), subtitle = UILabel(), button = UIButton(type: .system)
    var action: (() -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.text = "End of chapter"; label.textAlignment = .center; label.font = .systemFont(ofSize: 20, weight: .bold)
        subtitle.textAlignment = .center; subtitle.font = .systemFont(ofSize: 13); subtitle.textColor = .gray
        button.backgroundColor = UIColor(red: 0.69, green: 0.77, blue: 1, alpha: 1); button.setTitleColor(.black, for: .normal)
        button.layer.cornerRadius = 22; button.accessibilityIdentifier = "webtoon-end-action"
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        [label, subtitle, button].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = CGRect(x: 0, y: 22, width: bounds.width, height: 28)
        subtitle.frame = CGRect(x: 0, y: 55, width: bounds.width, height: 24)
        button.frame = CGRect(x: max(0, (bounds.width - 280) / 2), y: 94, width: min(280, bounds.width), height: 46)
    }
    @objc private func tapped() { action?() }
}
