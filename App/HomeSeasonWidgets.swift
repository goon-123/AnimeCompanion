import SwiftUI
import AnimeCore

struct HomeSeasonWidget: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.homeVisuals) private var visuals
    @Environment(\.homeWidgetLayout) private var layout
    let section: HomeSection
    let limit: Int
    let refreshID: Int
    var activationID = 0
    @State private var lineup: [Anime] = []
    @State private var loading = false
    @State private var failed = false
    @State private var attempt = UUID()
    @State private var appliedRefreshID = 0
    @State private var retry = 0
    @State private var pickOffset = 0
    private var needsLineup: Bool { [.seasonCountdown, .nextSeason, .returningSeries].contains(section) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let countdown = HomeSeasonCountdown(now: timeline.date)
            VStack(alignment: .leading, spacing: 12) {
                if section == .seasonCountdown {
                    NavigationLink {
                        DiscoveryBrowseView(category: .seasonal, selection: countdown.next)
                    } label: {
                        HomeSeasonCountdownCard(countdown: countdown, artwork: visibleLineup)
                    }.buttonStyle(.plain).accessibilityIdentifier("home-season-countdown")
                } else {
                    heading(countdown)
                    let values = items(at: timeline.date)
                    if !values.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(values) { anime in
                                    AnimeLink(id: anime.id) {
                                        HomeAnimeBanner(anime: anime, caption: caption(anime))
                                            .overlay(alignment: .topLeading) { if layout == .banner { badge(anime) } }
                                            .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in min(layout == .compact ? visuals.value(300, 400) : (layout == .poster ? visuals.value(340, 460) : visuals.animeBannerLimit), width * (section == .tonightPick ? 1 : 0.92)) }
                                    }.buttonStyle(.plain).accessibilityIdentifier("home-\(section.rawValue)-\(anime.id)")
                                }
                            }.scrollTargetLayout()
                        }.scrollTargetBehavior(.viewAligned)
                    } else if loading {
                        HomeWidgetEmpty(symbol: section.symbol, title: "Your next favorites await.", detail: "The seasonal lineup is loading.")
                    } else { emptyState(countdown) }
                }
                if failed {
                    HStack {
                        Text(lineup.isEmpty ? "Lineup unavailable · Countdown still works offline" : "Showing saved lineup")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button("Retry") { retry += 1 }.font(.caption.weight(.semibold))
                    }
                }
            }.accessibilityIdentifier("home-widget-" + section.rawValue)
                .task(id: "\(countdown.next.label)-\(store.includeAdult)-\(refreshID)-\(activationID)-\(retry)") {
                    guard needsLineup else { return }
                    await load(countdown.next)
                }
        }
    }
    private var visibleLineup: [Anime] { lineup.filter { store.isVisible($0) } }
    private func items(at date: Date) -> [Anime] {
        switch section {
        case .nextSeason: return Array(visibleLineup.prefix(limit))
        case .returningSeries: return Array(HomeSeasonContent.returning(visibleLineup, library: store.visibleEntries).prefix(limit))
        case .hallOfFame: return Array(HomeSeasonContent.favorites(store.visibleEntries).prefix(limit).compactMap(\.media))
        case .tonightPick:
            let candidates = HomeSeasonContent.tonightCandidates(store.visibleEntries, now: date)
            guard !candidates.isEmpty else { return [] }
            let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970 / 86400)
            return [candidates[((day + pickOffset) % candidates.count + candidates.count) % candidates.count]]
        default: return []
        }
    }
    @ViewBuilder private func heading(_ countdown: HomeSeasonCountdown) -> some View {
        HStack(alignment: .top) {
            CompanionSectionHeading(title: section.title, subtitle: subtitle(countdown))
            Spacer(minLength: 4)
            if section == .tonightPick {
                Button { pickOffset += 1 } label: { Image(systemName: "shuffle").font(visuals.toolbarIconFont).frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Choose another anime for tonight")
            } else if needsLineup {
                NavigationLink { DiscoveryBrowseView(category: .seasonal, selection: countdown.next) } label: {
                    Image(systemName: "arrow.up.right.circle.fill").font(visuals.circleIconFont).frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Browse " + countdown.next.label)
            }
        }
    }
    private func subtitle(_ countdown: HomeSeasonCountdown) -> String {
        switch section {
        case .nextSeason: return countdown.next.label + " · A first look at the popular lineup"
        case .returningSeries: return "Sequels and saved premieres in " + countdown.next.label
        case .hallOfFame: return "The stories you finished, ordered by your ratings"
        default: return "Something ready to watch from your own library"
        }
    }
    private func caption(_ anime: Anime) -> String {
        switch section {
        case .nextSeason, .returningSeries:
            if let date = anime.startDate, date.year != nil { return "PREMIERES · " + date.label.uppercased() }
            return "PREMIERE DATE TO BE ANNOUNCED"
        case .hallOfFame:
            if layout != .banner, let score = store.entry(for: anime.id)?.score, score > 0 { return "YOUR SCORE · \(Int(score.rounded()))/100" }
            return "COMPLETED · YOUR COLLECTION"
        default:
            let next = (store.entry(for: anime.id)?.progressValue ?? 0) + 1
            return next == 1 ? "TONIGHT · START EPISODE 1" : "TONIGHT · CONTINUE EPISODE \(next)"
        }
    }
    @ViewBuilder private func badge(_ anime: Anime) -> some View {
        if section == .hallOfFame, let score = store.entry(for: anime.id)?.score, score > 0 {
            Label("\(Int(score.rounded()))/100", systemImage: "star.fill")
                .font(.caption.weight(.bold)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6).background(.black.opacity(0.6), in: Capsule()).padding(12)
                .accessibilityLabel("Your rating \(Int(score.rounded())) out of 100")
        }
    }
    private func emptyState(_ countdown: HomeSeasonCountdown) -> some View {
        HomeWidgetEmpty(symbol: section.symbol, title: emptyTitle, detail: emptyDetail(countdown))
    }
    private var emptyTitle: String {
        switch section {
        case .returningSeries: return "The next chapter is still taking shape."
        case .hallOfFame: return "Your favorites deserve a spotlight."
        case .tonightPick: return "A new story is waiting."
        default: return "The next lineup is on its way."
        }
    }
    private func emptyDetail(_ countdown: HomeSeasonCountdown) -> String {
        switch section {
        case .returningSeries: return "No matches in the loaded popular lineup yet. Add next-season anime to your library, or check back as sequels are announced."
        case .hallOfFame: return "Complete anime in AniList to build your hall of fame. Your own scores decide the order."
        case .tonightPick: return "Add a released anime to Watching or Plan to Watch. Only confirmed available episodes become a pick."
        default: return countdown.next.label + " premieres will appear as they are announced. Tap the arrow to explore."
        }
    }
    @MainActor private func load(_ selection: SeasonSelection) async {
        let current = UUID(); attempt = current; loading = true; failed = false
        defer { if attempt == current { loading = false } }
        if let saved = await store.homeCatalog.cached(selection, includeAdult: store.includeAdult), attempt == current, !Task.isCancelled {
            lineup = saved.value
        }
        do {
            let saved = try await store.homeCatalog.season(selection, includeAdult: store.includeAdult,
                refresh: refreshID != appliedRefreshID || retry > 0)
            try Task.checkCancellation(); guard attempt == current else { return }
            lineup = saved.value; appliedRefreshID = refreshID
        } catch is CancellationError {} catch { if attempt == current { failed = true } }
    }
}

private struct HomeSeasonCountdownCard: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.homeVisuals) private var visuals
    @Environment(\.homeWidgetLayout) private var layout
    let countdown: HomeSeasonCountdown
    let artwork: [Anime]
    private var tint: Color {
        switch countdown.next.season {
        case .winter: return Color(red: 0.56, green: 0.88, blue: 1)
        case .spring: return Color(red: 1, green: 0.69, blue: 0.84)
        case .summer: return Color(red: 1, green: 0.84, blue: 0.50)
        case .fall: return Color(red: 1, green: 0.67, blue: 0.40)
        }
    }
    private var symbol: String {
        switch countdown.next.season { case .winter: return "snowflake"; case .spring: return "leaf.fill"; case .summer: return "sun.max.fill"; case .fall: return "leaf.circle.fill" }
    }
    var body: some View {
        Group {
            if layout == .compact { compactCard }
            else if layout == .poster { mediumCard }
            else { cinematic }
        }
    }
    private var compactCard: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title).foregroundStyle(tint).frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(countdown.next.label).font(.headline)
                Text("\(countdown.days)d  \(countdown.hours)h  \(countdown.minutes)m").font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(tint)
                Text("Next anime season · Season dates vary").font(.caption2).foregroundStyle(.white.opacity(0.7))
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.up.right").font(.headline)
        }.foregroundStyle(.white).padding(16).background { background }.clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            .accessibilityElement(children: .combine)
    }
    private var mediumCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(countdown.next.label).font(.title2.bold())
                Spacer(); Image(systemName: "arrow.up.right").font(.subheadline)
            }
            HStack(spacing: 10) { counter(countdown.days, label: "DAYS"); counter(countdown.hours, label: "HOURS"); counter(countdown.minutes, label: "MINUTES") }
            Text(countdown.startsAt, format: .dateTime.month(.wide).day().year()).font(.caption.weight(.semibold))
            Text("Season boundary · Individual premiere dates vary").font(.caption2).foregroundStyle(.white.opacity(0.65))
        }.foregroundStyle(.white).padding(18).background { background }.clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
    private var cinematic: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text("NOW · " + countdown.current.label.uppercased()).font(.caption2.weight(.bold)).tracking(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(visuals.actionIconFont)
            }.foregroundStyle(.white.opacity(0.85))
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("THE NEXT SEASON").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(tint)
                    Text(countdown.next.label).font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .tracking(-1).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                    Text("New stories. New favorites.").font(.subheadline).foregroundStyle(.white.opacity(0.75))
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !textSize.isAccessibilitySize {
                    Image(systemName: symbol).font(.system(size: visuals.value(34, 46), weight: .light)).foregroundStyle(tint)
                        .frame(width: visuals.value(64, 88), height: visuals.value(64, 88)).background(tint.opacity(0.12), in: Circle())
                        .overlay { Circle().strokeBorder(tint.opacity(0.25), lineWidth: 1) }.accessibilityHidden(true)
                }
            }
            HStack(spacing: 10) {
                counter(countdown.days, label: "DAYS")
                counter(countdown.hours, label: "HOURS")
                counter(countdown.minutes, label: "MINUTES")
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel("\(countdown.days) days, \(countdown.hours) hours and \(countdown.minutes) minutes until \(countdown.next.label)")
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(countdown.current.season.label) → \(countdown.next.season.label)")
                    Spacer()
                    Text("\(Int(countdown.progress * 100))% through this season")
                }.font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.7))
                GeometryReader { geometry in
                    Capsule().fill(.white.opacity(0.12))
                        .overlay(alignment: .leading) { Capsule().fill(LinearGradient(colors: [tint.opacity(0.4), tint], startPoint: .leading, endPoint: .trailing)).frame(width: max(4, geometry.size.width * countdown.progress)) }
                }.frame(height: 4).accessibilityHidden(true)
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "calendar").foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(countdown.startsAt, format: .dateTime.month(.wide).day().year()).font(.caption.weight(.semibold))
                    Text("Season boundary · Individual premiere dates vary").font(.caption2).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
            }.foregroundStyle(.white)
        }.padding(20).background { background }.clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            .overlay { RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(tint.opacity(0.2), lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
    private func counter(_ value: Int, label: String) -> some View {
        VStack(spacing: 5) {
            Text(String(format: "%02d", value)).font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(.white)
            Text(label).font(.system(.caption2, design: .rounded, weight: .bold)).tracking(1).foregroundStyle(tint)
                .minimumScaleFactor(0.6).lineLimit(1)
        }.frame(maxWidth: .infinity).padding(.vertical, 12).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08), lineWidth: 1) }
    }
    private var background: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
                Color(red: 0.05, green: 0.08, blue: 0.15)
                if let anime = artwork.first {
                    ArtworkImage(url: anime.bannerImage.flatMap(URL.init(string:)) ?? anime.coverURL, pointSize: geometry.size.width) { $0.resizable().scaledToFill() }
                        placeholder: { Color.clear }
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped().opacity(0.28)
                }
                LinearGradient(colors: [Color(red: 0.04, green: 0.07, blue: 0.14).opacity(0.85), tint.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                RadialGradient(colors: [tint.opacity(0.18), .clear], center: .topTrailing, startRadius: 0, endRadius: geometry.size.width * 0.8)
            }
        }.accessibilityHidden(true)
    }
}
