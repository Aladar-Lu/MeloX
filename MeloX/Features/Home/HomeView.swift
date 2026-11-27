import SwiftUI

struct HomeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library

    /// Opens the account / Settings sheet. ContentView passes the
    /// action that presents its Settings sheet.
    let onAccountTap: () -> Void
    /// Opens private messages / song recognition. ContentView
    /// passes the navigation actions; the buttons live in the
    /// header row, not in a toolbar (see headerRow).
    let onMessagesTap: () -> Void
    let onRecognitionTap: () -> Void

    @State private var section = AppTab.recommended

    init(
        onAccountTap: @escaping () -> Void = {},
        onMessagesTap: @escaping () -> Void = {},
        onRecognitionTap: @escaping () -> Void = {}
    ) {
        self.onAccountTap = onAccountTap
        self.onMessagesTap = onMessagesTap
        self.onRecognitionTap = onRecognitionTap
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
            // One-line header: the title on the left, the
            // buttons on the right, on the SAME line — plain
            // views in the content, NOT the navigation bar.
            // The bar splits them into two rows (buttons in
            // the bar row, title below it), and a toolbar Text
            // collapses into a "..." button, so both earlier
            // approaches failed. The navigation bar is hidden;
            // this row IS the header. The avatar and the
            // messages + recognition capsule are regular views
            // here, so iOS cannot merge them into one pill
            // (it merges only toolbar items — that is why the
            // avatar split kept failing in 9110403/9110405).
            headerRow

            if availableSections.count > 1 {
                sectionPicker
            }

            sectionContent(for: activeSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentMargins(.top, 0, for: .scrollContent)
        }
        // The two nested scroll views below (the pill picker's
        // horizontal ScrollView and the section content's
        // vertical ScrollView) must NOT inherit the top content
        // inset. They sit below the header, so the inset
        // double-counts: in 9110405 it left a ~130pt dead band
        // between the title and the pills and another ~130pt
        // between the pills and the cards (measured on-device:
        // title 120-160, pills 296-323, cards 460+). Zeroing
        // the top scroll-content margin here removes both
        // voids.
        .contentMargins(.top, 0, for: .scrollContent)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: availableSections) { _, sections in
            guard !sections.contains(section) else { return }
            section = sections.first ?? .recommended
        }
    }

    /// The one-line header: large 首页 on the left, the
    /// messages + recognition capsule and the avatar on the
    /// right, vertically centred on one row. Pinned above the
    /// scrolling content, with the frosted bar background so
    /// content sliding under it fades like under a nav bar.
    private var headerRow: some View {
        HStack {
            Text("ui.navigation.home")
                .font(.largeTitle.bold())
            Spacer()
            messagesCapsule
            Button {
                onAccountTap()
            } label: {
                accountButtonLabel
            }
            .accessibilityLabel(accountToolbarAccessibilityLabel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Private messages + song recognition in one glass
    /// capsule. A plain view in the header row — NOT a toolbar
    /// item — so it stays its own capsule next to the avatar.
    private var messagesCapsule: some View {
        HStack(spacing: 16) {
            if library.isLoggedIn {
                Button {
                    onMessagesTap()
                } label: {
                    Label("ui.messages.private.title", systemImage: "bubble.left.and.bubble.right")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("ui.messages.private.title")
                .accessibilityHint("ui.messages.private.open_hint")
            }

            Button {
                onRecognitionTap()
            } label: {
                Label("ui.recognition.title", systemImage: "waveform")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("ui.recognition.title")
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    @ViewBuilder
    private var accountButtonLabel: some View {
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
