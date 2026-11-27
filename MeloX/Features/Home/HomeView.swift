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
        sectionContent(for: activeSection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The picker lives in the scroll content's top
            // safe-area inset instead of a fixed VStack row above
            // it. A fixed row broke the scroll behaviour every
            // other tab root has: the section content never
            // reached the navigation bar, so on scroll nothing
            // slid under a frosted mask and the top stayed a
            // static band with no clear boundary. As an inset,
            // the picker stays pinned and one tap away, but the
            // content now scrolls under it (and the nav bar) like
            // Search / Discover / Library — the opaque frosted
            // mask with a clear boundary iOS 27 shows there.
            .safeAreaInset(edge: .top, spacing: 0) {
                if availableSections.count > 1 {
                    sectionPicker
                }
            }
            .tabRootHeaderTitle(L10n.string("ui.navigation.home"))
            // The avatar lives in THIS view's own .toolbar
            // modifier — not in ContentView's primaryToolbar,
            // and not in a second .toolbar modifier on the same
            // view there. iOS renders each view's toolbar as its
            // own glass pill (the Library "+" stands alone
            // because it comes from LibraryView's own toolbar),
            // while two groups — or two .toolbar modifiers — on
            // one view merge into a single capsule, the way the
            // trio merged in 9110403. Trailing order: the outer
            // (ContentView) messages + recognition pill sits
            // left, this inner item lands at the far right —
            // the same order the original app showed (trio left,
            // Library "+" far right).
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
        .padding(.vertical, 8)
        .background(.bar)
        // Crisp bottom edge for the frosted strip: over a black
        // background the .bar material alone has no visible
        // boundary, which is what made the Home header read as
        // one flat band. The other tab roots get this edge from
        // the navigation bar itself.
        .overlay(alignment: .bottom) {
            Divider()
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
