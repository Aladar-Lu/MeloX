import SwiftUI

struct HomeView: View {
    @Environment(AppSettings.self) private var settings

    /// When provided (the Home tab root), the page uses its own
    /// one-line header — large 首页 + the trio on a single row —
    /// and hides the nav bar. Nested uses pass nil and keep the
    /// stock behaviour.
    let topBarActions: TopBarActions?

    @State private var section = AppTab.recommended

    init(topBarActions: TopBarActions? = nil) {
        self.topBarActions = topBarActions
    }

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
            if let actions = topBarActions {
                PageHeader(title: L10n.string("ui.navigation.home")) {
                    HeaderTrioButtons(actions: actions)
                }
            }

            if availableSections.count > 1 {
                sectionPicker
            }

            sectionContent(for: activeSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The section content is a ScrollView inside this
                // NavigationStack. With the nav bar hidden the
                // stack still hands every ScrollView a ~150pt top
                // safe-area inset (the large-title bar height) —
                // that was the void under the header and under the
                // picker in the earlier one-line attempt. The
                // plain header and the Picker take no such inset,
                // only the scrolling content does, so only it
                // ignores the top safe area — and only when the
                // header is shown (with the stock large title the
                // inset is the correct spacing).
                .ignoresSafeArea(
                    .container,
                    edges: topBarActions == nil ? [] : .top
                )
        }
        .navigationTitle("ui.navigation.home")
        // Large only for the stock layout. With the one-line
        // header the nav bar is hidden, so a large title would
        // only inflate the stack's top safe area (the void).
        .navigationBarTitleDisplayMode(
            topBarActions == nil ? .large : .inline
        )
        .toolbar(topBarActions == nil ? .visible : .hidden, for: .navigationBar)
        .onChange(of: availableSections) { _, sections in
            guard !sections.contains(section) else { return }
            section = sections.first ?? .recommended
        }
    }

    @ViewBuilder
    private var sectionPicker: some View {
        if availableSections.count <= 4 {
            Picker("ui.home.section_picker", selection: $section) {
                ForEach(availableSections) { section in
                    Text(section.settingsTitle)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.background)
        } else {
            Picker("ui.home.section_picker", selection: $section) {
                ForEach(availableSections) { section in
                    Label(
                        section.settingsTitle,
                        systemImage: section.systemImage
                    )
                    .tag(section)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
        }
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
