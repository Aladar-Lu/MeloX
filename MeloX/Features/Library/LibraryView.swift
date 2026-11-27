import SwiftUI

struct LibraryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings

    private let fixedPage: LibraryPage?
    private let showsNavigationTitle: Bool
    /// When provided (the 收藏歌单 tab root), the page uses its
    /// own one-line header — large title + buttons on a single
    /// row — and hides the nav bar. Nested uses and fixed pages
    /// pass nil and keep the stock behaviour.
    let topBarActions: TopBarActions?

    @State private var section: LibraryPage
    @State private var hasAppliedInitialPage = false
    @State private var showsLogin = false
    @State private var searchQuery = ""
    /// The playlists create / sort state, owned here so the
    /// one-line header (not a toolbar) can drive it. Passed
    /// down to the playlists overview; sub-pages keep their own
    /// local copy.
    @State private var isReorderingSections = false
    @State private var showsCreation = false
    @FocusState private var isSearchFieldFocused: Bool

    init(
        fixedPage: LibraryPage? = nil,
        showsNavigationTitle: Bool = true,
        topBarActions: TopBarActions? = nil
    ) {
        let resolvedFixedPage = fixedPage.flatMap { page in
            LibraryPage.availableCases.contains(page) ? page : nil
        }
        self.fixedPage = resolvedFixedPage
        self.showsNavigationTitle = showsNavigationTitle
        self.topBarActions = topBarActions
        _section = State(initialValue: resolvedFixedPage ?? .songs)
    }

    private var availablePages: [LibraryPage] {
        fixedPage.map { [$0] } ?? settings.embeddedLibraryPages
    }

    /// The main tab root (no fixed page, header actions given).
    /// Only it gets the one-line header; fixed pages and nested
    /// uses keep the nav bar.
    private var isMainTabRoot: Bool {
        fixedPage == nil && topBarActions != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if isMainTabRoot, let actions = topBarActions {
                PageHeader(title: L10n.string("ui.navigation.library")) {
                    libraryHeaderButtons(actions: actions)
                }

                if canSearchCurrentPage {
                    librarySearchField
                }

                if availablePages.count > 1 {
                    Group {
                        if availablePages.count > 4, horizontalSizeClass == .compact {
                            pagePicker.pickerStyle(.menu)
                        } else {
                            pagePicker.pickerStyle(.segmented)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.background)
                }
            } else if !showsNavigationTitle, fixedPage == nil, availablePages.count > 1 {
                Group {
                    if availablePages.count > 4, horizontalSizeClass == .compact {
                        pagePicker.pickerStyle(.menu)
                    } else {
                        pagePicker.pickerStyle(.segmented)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.background)
            }

            Group {
                if availablePages.isEmpty {
                    ContentUnavailableView(
                        "ui.library.pages_separated.title",
                        systemImage: "rectangle.3.group",
                        description: Text("ui.library.pages_separated.message")
                    )
                } else if section == .downloads {
                    LibraryDownloadsView(searchQuery: searchQuery)
                } else if !library.isLoggedIn {
                    loginUnavailableView
                } else if section == .cloud {
                    CloudMusicView(searchQuery: searchQuery)
                } else {
                    libraryContent
                }
            }
            // The section views are ScrollViews / Lists inside
            // this NavigationStack. With the nav bar hidden the
            // stack still hands them a ~150pt top safe-area inset
            // (the large-title bar height) — the void under the
            // header. The header, search field and picker above
            // are plain rows and take no such inset. Fixed pages
            // keep a visible large title, so their inset is the
            // correct spacing and is left alone.
            .ignoresSafeArea(
                .container,
                edges: (isMainTabRoot || !showsNavigationTitle) ? .top : []
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .libraryNavigationTitle(
            fixedPage.map { AppTab(libraryPage: $0).title }
                ?? L10n.string("ui.navigation.library"),
            isPresented: showsNavigationTitle && !isMainTabRoot,
            usesInlineTitle: fixedPage == nil
        )
        .librarySearchable(
            text: $searchQuery,
            prompt: searchPrompt,
            isEnabled: canSearchCurrentPage && !isMainTabRoot
        )
        .toolbar {
            if showsNavigationTitle, fixedPage == nil, availablePages.count > 1, !isMainTabRoot {
                ToolbarTitleMenu {
                    pagePicker.pickerStyle(.inline)
                }
            }
        }
        .toolbar(isMainTabRoot ? .hidden : .visible, for: .navigationBar)
        .onAppear {
            guard !hasAppliedInitialPage else { return }
            hasAppliedInitialPage = true
            if let fixedPage {
                section = fixedPage
            } else {
                section = availablePages.contains(settings.initialLibraryPage)
                    ? settings.initialLibraryPage
                    : availablePages.first ?? .songs
            }
        }
        .onChange(of: section) { _, page in
            if fixedPage == nil {
                settings.lastLibraryPage = page
            }
        }
        .onChange(of: availablePages) { _, pages in
            guard fixedPage == nil,
                  let firstPage = pages.first,
                  !pages.contains(section) else {
                return
            }
            section = firstPage
        }
        .sheet(isPresented: $showsLogin) {
            NavigationStack {
                NeteaseLoginView()
            }
        }
        .task(id: settings.cookie) {
            await library.refresh()
        }
        .alert(
            "ui.library.error.title",
            isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { presented in
                    if !presented {
                        library.clearError()
                    }
                }
            )
        ) {
            Button("ui.common.ok", role: .cancel) {
                library.clearError()
            }
        } message: {
            Text(library.errorMessage ?? L10n.string("ui.common.unknown_error"))
        }
    }

    private var pagePicker: some View {
        Picker("ui.library.category_picker", selection: $section) {
            ForEach(availablePages) { item in
                Text(item.title).tag(item)
            }
        }
    }

    /// The header's right side for the main tab root: the trio
    /// plus the playlists create / sort buttons in ONE capsule,
    /// exactly as the nav bar merged them. The create / sort
    /// pair only appears on the playlists overview; while
    /// reordering, the checkmark replaces them.
    @ViewBuilder
    private func libraryHeaderButtons(actions: TopBarActions) -> some View {
        HeaderPill {
            HeaderTrioContent(actions: actions)

            if section == .playlists {
                if isReorderingSections {
                    Button {
                        isReorderingSections = false
                    } label: {
                        Label(
                            "ui.common.done",
                            systemImage: "checkmark.circle.fill"
                        )
                        .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("ui.common.done")
                } else {
                    Button(
                        "ui.playlists.create.title",
                        systemImage: "plus"
                    ) {
                        showsCreation = true
                    }
                    .disabled(!library.isLoggedIn)

                    Menu {
                        Button("ui.library.playlists.sort") {
                            isReorderingSections = true
                        }
                    } label: {
                        Label(
                            "ui.library.playlists.sort",
                            systemImage: "arrow.up.arrow.down"
                        )
                        .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("ui.library.playlists.sort")
                }
            }
        }
        .foregroundStyle(.red)
    }

    /// The library filter field, as a plain TextField. The nav
    /// bar is hidden on the main tab root, so `.searchable`
    /// (which lives in the nav bar drawer) cannot be used here.
    /// It binds to the same `searchQuery` the section views
    /// filter on, so filtering works exactly as before. Unlike
    /// the drawer's `.automatic` field it stays visible; the
    /// field is small and always useful.
    private var librarySearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("", text: $searchQuery, prompt: Text(searchPrompt))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFieldFocused)
                .onSubmit { isSearchFieldFocused = false }
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            .secondary.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var loginUnavailableView: some View {
        ContentUnavailableView {
            Label("ui.account.login_required", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text(
                AppFeatureAvailability.downloads
                    ? L10n.string("ui.library.login_message.downloads")
                    : L10n.string("ui.library.login_message")
            )
        } actions: {
            Button("ui.account.login_netease") {
                showsLogin = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        switch library.phase {
        case .loading where library.profile == nil:
            ProgressView("ui.library.loading")
        case .failed(let message) where library.profile == nil:
            ConnectionUnavailableView(message: message) {
                Task { await library.refresh(force: true) }
            }
        default:
            switch section {
            case .songs:
                LibrarySongsView(searchQuery: searchQuery)
            case .playlists:
                // On the main tab root the header owns the
                // create / sort state, so the overview shares
                // it. Everywhere else (fixed page, nested,
                // sub-page) the overview keeps its own.
                if isMainTabRoot {
                    LibraryPlaylistsView(
                        searchQuery: searchQuery,
                        isReorderingSections: $isReorderingSections,
                        showsCreation: $showsCreation
                    )
                } else {
                    LibraryPlaylistsView(searchQuery: searchQuery)
                }
            case .artists:
                LibraryArtistsView(searchQuery: searchQuery)
            case .albums:
                LibraryAlbumsView(searchQuery: searchQuery)
            case .podcasts:
                SubscribedPodcastsView(searchQuery: searchQuery)
            case .downloads:
                LibraryDownloadsView(searchQuery: searchQuery)
            case .cloud:
                CloudMusicView(searchQuery: searchQuery)
            case .history:
                LibraryHistoryView(searchQuery: searchQuery)
            }
        }
    }

    private var canSearchCurrentPage: Bool {
        !availablePages.isEmpty
            && (section == .downloads || library.isLoggedIn)
    }

    private var searchPrompt: String {
        switch section {
        case .songs:
            L10n.string("ui.library.search.favorite_songs")
        case .playlists:
            L10n.string("ui.library.search.favorite_playlists")
        case .artists:
            L10n.string("ui.library.artists.search")
        case .albums:
            L10n.string("ui.library.search.favorite_albums")
        case .podcasts:
            L10n.string("ui.library.search.subscribed_podcasts")
        case .downloads:
            AppFeatureAvailability.downloads
                ? L10n.string("ui.library.search.downloads")
                : L10n.string("ui.library.search.songs")
        case .cloud:
            L10n.string("ui.library.search.cloud")
        case .history:
            L10n.string("ui.library.search.history")
        }
    }
}

private extension View {
    /// Tab root: inline title, always. The title then shares
    /// the bar row with the current section's buttons (the
    /// playlists + / sort pill) — one line, no empty white band
    /// above it. A large title would put the title on its own
    /// row below an empty bar row. Fixed pages (a single library
    /// section opened on its own) keep the large title.
    @ViewBuilder
    func libraryNavigationTitle(
        _ title: String,
        isPresented: Bool,
        usesInlineTitle: Bool
    ) -> some View {
        if isPresented {
            navigationTitle(title)
                .navigationBarTitleDisplayMode(usesInlineTitle ? .inline : .automatic)
        } else {
            self
        }
    }

    @ViewBuilder
    func librarySearchable(
        text: Binding<String>,
        prompt: String,
        isEnabled: Bool
    ) -> some View {
        if isEnabled {
            searchable(
                text: text,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: Text(prompt)
            )
        } else {
            self
        }
    }
}
