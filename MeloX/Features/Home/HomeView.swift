import SwiftUI

struct HomeView: View {
    @Environment(AppSettings.self) private var settings

    @State private var section = AppTab.recommended

    private var availableSections: [AppTab] {
        settings.homeTabs
    }

    private var activeSection: AppTab {
        availableSections.contains(section)
            ? section
            : availableSections.first ?? .recommended
    }

    var body: some View {
        VStack(spacing: 0) {
            if availableSections.count > 1 {
                sectionPicker
            }

            sectionContent(for: activeSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tabRootHeaderTitle(L10n.string("ui.navigation.home"))
        .onChange(of: availableSections) { _, sections in
            guard !sections.contains(section) else { return }
            section = sections.first ?? .recommended
        }
    }

    /// Horizontal scrollable pill row, in the exact style of
    /// `ExploreCategoryPicker` (borderedProminent capsule buttons,
    /// small control size, accent tint when selected, text only).
    /// Replaces the old segmented/menu picker: with five sections
    /// the menu opened a vertical popup; the pill row keeps every
    /// section one tap away. Items stay dynamic from
    /// `settings.homeTabs` — nothing is hardcoded.
    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(availableSections) { section in
                    Button {
                        self.section = section
                    } label: {
                        Text(section.settingsTitle)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(
                        section == activeSection
                            ? .accentColor
                            : Color.secondary.opacity(0.14)
                    )
                    .foregroundStyle(
                        section == activeSection ? .white : .primary
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private func sectionContent(
        for section: AppTab
    ) -> some View {
        switch section {
        case .recommended:
            HomeRecommendedView()
        case .music:
            ExploreView(showsNavigationTitle: false)
        case .podcasts:
            PodcastHomeView(showsNavigationTitle: false)
        case .explore:
            ExploreView(showsNavigationTitle: false)
        case .library:
            LibraryView(showsNavigationTitle: false)
        case .librarySongs,
             .libraryPlaylists,
             .libraryAlbums,
             .libraryArtists,
             .libraryPodcasts,
             .libraryDownloads,
             .libraryCloud,
             .libraryHistory:
            if let page = section.libraryPage {
                LibraryView(
                    fixedPage: page,
                    showsNavigationTitle: false
                )
            }
        case .home,
             .search:
            EmptyView()
        }
    }
}
