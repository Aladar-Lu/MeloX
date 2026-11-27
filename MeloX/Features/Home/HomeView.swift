import SwiftUI

struct HomeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library

    /// Opens the account / Settings sheet. ContentView passes the
    /// action that presents its Settings sheet.
    let onAccountTap: () -> Void

    @State private var section = AppTab.recommended

    init(onAccountTap: @escaping () -> Void = {}) {
        self.onAccountTap = onAccountTap
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
            if availableSections.count > 1 {
                sectionPicker
            }

            sectionContent(for: activeSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentMargins(.top, 0, for: .scrollContent)
        }
        // The two nested scroll views below (the pill picker's
        // horizontal ScrollView and the section content's
        // vertical ScrollView) must NOT inherit the navigation
        // bar's top content inset. They sit BELOW the bar, so
        // the ~130pt inset double-counts: in 9110405 it left a
        // ~130pt dead band between the title and the pills and
        // another ~130pt between the pills and the cards (measured
        // on-device: title 120-160, pills 296-323, cards 460+).
        // Discover proves the rule: its single root ScrollView
        // gets the inset once, correctly, and has no gap. Zeroing
        // the top scroll-content margin here removes both voids;
        // the content still slides under the bar with the frosted
        // mask when scrolled, like the other pages.
        .contentMargins(.top, 0, for: .scrollContent)
        // Plain large title, like the original app and like the
        // target screenshot: the big 首页 sits below the bar,
        // the pills below it, content directly below the pills.
        // The one-line inline header (empty title + a leading
        // Text item) collapsed into a "..." button and left a
        // dead band, so it is gone.
        .navigationTitle("ui.navigation.home")
        .navigationBarTitleDisplayMode(.large)
        // The avatar lives in THIS view's own .toolbar modifier,
        // and it is the ONLY trailing toolbar item on the Home
        // tab — so it renders as its own circular glass button
        // at the far right. Private messages + song recognition
        // are NOT in any toolbar: iOS 27 merges every
        // .topBarTrailing item, from any view at any level, into
        // a single pill, which is why the split kept failing
        // (9110403 and 9110405 both showed one merged capsule).
        // Those two live in a floating capsule in ContentView
        // instead, sitting in the bar row to the left of this
        // avatar button.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onAccountTap()
                } label: {
                    accountToolbarLabel
                }
                .accessibilityLabel(accountToolbarAccessibilityLabel)
            }
        }
        .onChange(of: availableSections) { _, sections in
            guard !sections.contains(section) else { return }
            section = sections.first ?? .recommended
        }
    }

    @ViewBuilder
    private var accountToolbarLabel: some View {
        if let profile = library.profile {
            AsyncImage(url: profile.artworkURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            .background(.quaternary, in: .circle)
            .clipShape(.circle)
        } else {
            Image(
                systemName: library.isLoggedIn
                    ? "person.crop.circle.fill"
                    : "person.crop.circle"
            )
        }
    }

    private var accountToolbarAccessibilityLabel: String {
        if let profile = library.profile {
            return L10n.format("ui.account.settings_for_user", profile.nickname)
        }
        return library.isLoggedIn
            ? L10n.string("ui.account.settings")
            : L10n.string("ui.account.login_settings")
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
        // See the note on the body VStack: this horizontal
        // ScrollView must not inherit the navigation bar's top
        // inset, or the pills drop ~130pt below the title.
        .contentMargins(.top, 0, for: .scrollContent)
        .padding(.vertical, 8)
        .background(.background)
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
