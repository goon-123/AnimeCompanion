import SwiftUI
import UniformTypeIdentifiers
import AnimeCore

enum HomeWidgetDrag {
    static let type = UTType(exportedAs: "com.animecompanion.home-widget")
    static func provider(for section: HomeSection) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { completion in
            completion(Data(section.rawValue.utf8), nil); return nil
        }
        return provider
    }
}

struct HomeWidgetFrame<Content: View>: View {
    let section: HomeSection
    @Binding var saved: String
    @Binding var editing: Bool
    @Binding var dragging: HomeSection?
    let content: Content
    init(section: HomeSection, saved: Binding<String>, editing: Binding<Bool>, dragging: Binding<HomeSection?>,
         @ViewBuilder content: () -> Content) {
        self.section = section; _saved = saved; _editing = editing; _dragging = dragging; self.content = content()
    }
    private var preferences: HomePreferences { HomePreferences(saved: saved) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editing { controls }
            content.disabled(editing).allowsHitTesting(!editing)
        }.padding(editing ? 12 : 0)
            .overlay {
                if editing {
                    RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .contextMenu {
                Button("Edit Home", systemImage: "slider.horizontal.3") { editing = true }
                moveActions
                sizeActions
                Button("Hide widget", systemImage: "minus.circle", role: .destructive) { update { $0.setVisible(section, false) } }
            }
            .onDrop(of: [HomeWidgetDrag.type], delegate: HomeWidgetDropDelegate(target: section, saved: $saved, dragging: $dragging, enabled: editing))
            .accessibilityIdentifier("home-widget-" + section.rawValue)
            .accessibilityAction(named: "Edit Home") { editing = true }
            .accessibilityAction(named: "Hide widget") { update { $0.setVisible(section, false) } }
            .accessibilityAction(named: "Move up") { move(by: -1) }
            .accessibilityAction(named: "Move down") { move(by: 1) }
    }
    private var controls: some View {
        HStack(spacing: 8) {
            Button { update { $0.setVisible(section, false) } } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Hide \(section.title)").accessibilityIdentifier("home-hide-" + section.rawValue)
            Text(section.title).font(.caption.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
            Menu { moveActions; sizeActions } label: {
                Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
            }.accessibilityLabel("Options for \(section.title)").accessibilityIdentifier("home-options-" + section.rawValue)
            Image(systemName: "line.3.horizontal").foregroundStyle(Theme.accent).frame(width: 44, height: 44)
                .contentShape(Rectangle()).onDrag { dragging = section; return HomeWidgetDrag.provider(for: section) }
                .accessibilityLabel("Reorder \(section.title)").accessibilityHint("Use Move up or Move down actions, or drag to a new position")
                .accessibilityIdentifier("home-drag-" + section.rawValue)
        }
    }
    @ViewBuilder private var moveActions: some View {
        Button("Move to top", systemImage: "arrow.up.to.line") {
            if let first = preferences.visible.first { update { $0.move(section, before: first) } }
        }.disabled(preferences.visible.first == section)
        Button("Move up", systemImage: "arrow.up") { move(by: -1) }.disabled(preferences.visible.first == section)
        Button("Move down", systemImage: "arrow.down") { move(by: 1) }.disabled(preferences.visible.last == section)
        Button("Move to bottom", systemImage: "arrow.down.to.line") {
            if let last = preferences.visible.last { update { $0.move(section, after: last) } }
        }.disabled(preferences.visible.last == section)
    }
    @ViewBuilder private var sizeActions: some View {
        if section.supportsItemLimit {
            Menu("Preview items") {
                ForEach(HomeWidgetSize.allCases) { size in
                    Button {
                        update { $0.setSize(size, for: section) }
                    } label: {
                        if preferences.size(for: section) == size { Label("\(size.title) · \(size.itemLimit)", systemImage: "checkmark") }
                        else { Text("\(size.title) · \(size.itemLimit)") }
                    }
                }
            }
        }
    }
    private func move(by offset: Int) {
        let visible = preferences.visible
        guard let index = visible.firstIndex(of: section), visible.indices.contains(index + offset) else { return }
        let target = visible[index + offset]
        update { if offset < 0 { $0.move(section, before: target) } else { $0.move(section, after: target) } }
    }
    private func update(_ change: (inout HomePreferences) -> Void) {
        var value = preferences; change(&value)
        withAnimation(.easeInOut(duration: 0.18)) { saved = value.saved }
    }
}

struct HomeWidgetDropDelegate: DropDelegate {
    let target: HomeSection?
    @Binding var saved: String
    @Binding var dragging: HomeSection?
    var enabled: Bool
    func validateDrop(info: DropInfo) -> Bool { enabled && dragging != nil && info.hasItemsConforming(to: [HomeWidgetDrag.type]) }
    func dropEntered(info: DropInfo) {
        guard validateDrop(info: info), let source = dragging, let target, source != target else { return }
        var value = HomePreferences(saved: saved)
        guard let from = value.order.firstIndex(of: source), let to = value.order.firstIndex(of: target) else { return }
        if from < to { value.move(source, after: target) } else { value.move(source, before: target) }
        withAnimation(.easeInOut(duration: 0.18)) { saved = value.saved }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { validateDrop(info: info) ? DropProposal(operation: .move) : nil }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info) else { return false }
        dragging = nil; return true
    }
}
