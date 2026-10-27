import SwiftUI
import AnimeCore

struct MangaBakaSourceLinkSection: View {
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var links: MangaSourceLinkStore
    @EnvironmentObject private var navigation: AppNavigationStore
    let series: MangaBakaSeries
    @State private var removing: MangaSourceLinkTarget?
    private var target: MangaSourceLinkTarget? { account.sourceLinkTarget(for: series) }
    private var link: MangaSourceLink? { target.flatMap { links.link(for: $0) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let target, let link {
                Label("Linked reading source", systemImage: "link").font(.headline)
                Text(link.title.source.name + " · " + link.title.manga.title)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("manga-linked-source-name")
                NavigationLink {
                    MangaTitleDetailView(title: link.title, linkingTo: target, resumeOnOpen: true)
                } label: {
                    Label("Continue reading", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 7)
                }.buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black)
                    .accessibilityIdentifier("manga-linked-source-continue")
                HStack(spacing: 18) {
                    NavigationLink("Chapters") { MangaTitleDetailView(title: link.title, linkingTo: target) }
                    Button("Change source") { find(target) }.accessibilityIdentifier("manga-change-source-link")
                    Spacer(minLength: 0)
                    Button(role: .destructive) { removing = target } label: { Image(systemName: "xmark.circle") }
                        .accessibilityLabel("Remove linked source").accessibilityIdentifier("manga-remove-source-link")
                }.font(.subheadline).buttonStyle(.plain)
            } else if links.loading { ProgressView("Loading reading source…") }
            else {
                Button { find(target) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "book.closed").font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Find a reading source").font(.headline)
                            Text("Choose a title from an installed source and link it here").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "arrow.right")
                    }
                }.buttonStyle(.plain)
            }
            if let error = links.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(18).background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
            .task { await links.load() }
            .confirmationDialog("Remove linked reading source?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                if let removing {
                    Button("Remove link", role: .destructive) { Task { await links.setSource(nil, for: removing) } }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Your saved manga and chapter history are kept. You can link another source later.") }
    }
    private func find(_ target: MangaSourceLinkTarget?) {
        navigation.openMangaSearch(titles: series.searchTitles, linkingTo: target)
    }
}

/// Offered both after a contextual library search and when browsing a source directly.
struct MangaSourceLinkControl: View {
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var links: MangaSourceLinkStore
    @EnvironmentObject private var reading: MangaReadingStore
    let title: MangaTitleReference
    let requestedTarget: MangaSourceLinkTarget?
    @State private var chosen: MangaSourceLinkTarget?
    @State private var choosing = false
    @State private var saving = false
    private var target: MangaSourceLinkTarget? {
        guard account.connected, let accountID = account.profile?.id else { return nil }
        if let value = chosen ?? requestedTarget, value.accountID == accountID { return value }
        return links.state.links.values.filter { $0.library.accountID == accountID && $0.title.id == title.id }
            .max(by: { $0.updatedAt < $1.updatedAt })?.library
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let target {
                let current = links.link(for: target)
                Text(target.title).font(.subheadline.bold()).lineLimit(2)
                if current?.title.id == title.id {
                    Label("Linked to this library entry", systemImage: "link").font(.subheadline).foregroundStyle(.mint)
                    Button("Remove link", role: .destructive) {
                        saving = true
                        Task { await links.setSource(nil, for: target); saving = false }
                    }.font(.caption).disabled(saving || links.unreadable)
                        .accessibilityIdentifier("manga-source-remove-library-link")
                } else {
                    if let current { Text("Current source: " + current.title.source.name).font(.caption).foregroundStyle(.secondary) }
                    Button {
                        saving = true
                        Task {
                            if await links.setSource(title, for: target) { await reading.save(title, saved: true) }
                            saving = false
                        }
                    } label: { Label(saving ? "Saving link…" : current == nil ? "Use this reading source" : "Replace linked source", systemImage: "link.badge.plus") }
                        .buttonStyle(.borderedProminent).tint(MangaStyle.accent).foregroundStyle(.black)
                        .disabled(saving || links.loading || links.unreadable).accessibilityIdentifier("manga-link-source-to-entry")
                }
                Button("Choose a different library entry") { choosing = true }.font(.caption)
            } else {
                Button { choosing = true } label: { Label("Link to My Library", systemImage: "link.badge.plus") }
                    .buttonStyle(.bordered).accessibilityIdentifier("manga-link-to-library")
                Text("Save this source as the reading shortcut for a MangaBaka library title.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = links.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(MangaStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            .task { await links.load() }
            .sheet(isPresented: $choosing) {
                NavigationStack { MangaLibrarySourcePicker(title: title) { chosen = $0 } }
            }
    }
}

private struct MangaLibrarySourcePicker: View {
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var preferences: AppStore
    @EnvironmentObject private var links: MangaSourceLinkStore
    @EnvironmentObject private var reading: MangaReadingStore
    @Environment(\.dismiss) private var dismiss
    let title: MangaTitleReference
    let onLinked: (MangaSourceLinkTarget) -> Void
    @State private var query = ""
    @State private var saving = false
    @State private var signingIn = false
    private var series: [MangaBakaSeries] {
        account.library.compactMap(\.series).filter {
            $0.type != "novel" && $0.isVisible(contentFilter: preferences.mangaBakaContent) &&
            (query.isEmpty || $0.searchTitles.contains { $0.localizedCaseInsensitiveContains(query) })
        }.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    }
    var body: some View {
        List {
            Section {
                Text(title.manga.title).font(.headline)
                Text("Select the library title that should open " + title.source.name + ".").font(.subheadline).foregroundStyle(.secondary)
            }
            if !account.connected {
                Section { Button("Connect MangaBaka") { signingIn = true } }
            } else {
                Section("My Library") {
                    ForEach(series) { series in
                        Button { save(series) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(series.displayTitle).foregroundStyle(.primary)
                                if let target = account.sourceLinkTarget(for: series), let link = links.link(for: target) {
                                    Text("Linked: " + link.title.source.name + " · Tap to replace").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 5)
                        }.disabled(saving || links.unreadable || account.profile == nil)
                            .accessibilityIdentifier("manga-link-library-entry-\(series.id)")
                    }
                    if account.loadingLibrary { ProgressView("Loading your library…") }
                    else if series.isEmpty { Text("No matching manga in this library. Add the title to MangaBaka or change your search.").foregroundStyle(.secondary) }
                }
                if let error = account.libraryError { Section { Text(error); Button("Retry library") { Task { await loadLibrary() } } } }
                if let error = links.error { Section { Text(error).foregroundStyle(.orange) } }
            }
        }.navigationTitle("Link reading source").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Find a title in My Library")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) } }
            .task(id: account.connectionID) { await links.load(); await loadLibrary() }
            .sheet(isPresented: $signingIn) {
                NavigationStack { MangaBakaAccountView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { signingIn = false } } } }
            }
    }
    private func loadLibrary() async {
        guard account.connected else { return }
        if account.profile == nil { await account.refreshProfile() }
        await account.loadCompleteLibrary(state: nil)
    }
    private func save(_ series: MangaBakaSeries) {
        guard let target = account.sourceLinkTarget(for: series) else { return }
        let connection = account.connectionID
        saving = true
        Task {
            let saved = await links.setSource(title, for: target)
            if saved { await reading.save(title, saved: true) }
            saving = false
            guard saved, connection == account.connectionID else { return }
            onLinked(target); dismiss()
        }
    }
}

struct MangaSourceLinkBadge: View {
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var links: MangaSourceLinkStore
    let series: MangaBakaSeries
    var body: some View {
        if let target = account.sourceLinkTarget(for: series), let link = links.link(for: target) {
            Label(link.title.source.name, systemImage: "link").font(.caption2).foregroundStyle(.mint).lineLimit(1)
        }
    }
}

struct MangaLibrarySourceMenu: View {
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var links: MangaSourceLinkStore
    @EnvironmentObject private var navigation: AppNavigationStore
    let series: MangaBakaSeries
    var body: some View {
        if series.type != "novel", let target = account.sourceLinkTarget(for: series) {
            if let link = links.link(for: target) {
                Button { navigation.openLinkedManga(link) } label: { Label("Continue reading", systemImage: "play.fill") }
                Button { navigation.openMangaSearch(titles: series.searchTitles, linkingTo: target) } label: {
                    Label("Change linked source", systemImage: "link")
                }
            } else {
                Button { navigation.openMangaSearch(titles: series.searchTitles, linkingTo: target) } label: {
                    Label("Find a reading source", systemImage: "magnifyingglass")
                }
            }
        }
    }
}
