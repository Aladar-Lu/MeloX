import SwiftUI

/// The 收藏歌单 page, Apple Music 资料库 style.
///
/// Overview (`filter == nil`): pinned playlists as a large-cover
/// grid at the top, then three reorderable sub-menu rows
/// (listening rank, own playlists, collected playlists).
/// Sub-page (`filter == .own` / `.collected`): those playlists as
/// a large-cover grid. A pinned playlist also stays in its own
/// section list — pinning is a shortcut, not a move.
struct LibraryPlaylistsView: View {
    let searchQuery: String
    let filter: LibraryPlaylistSection?

    @Environment(LibraryStore.self) private var library
    @Environment(NeteaseAPI.self) private var api
    @Environment(PlayerStore.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(\.openMusicRoute) private var openMusicRoute

    @State private var showsCreation = false
    @State private var pendingDeletion: Playlist?
    @State private var isDeletingPlaylist = false
    @State private var deletionError: String?
    @State private var playbackErrorMessage: String?
    @State private var isReorderingSections = false

    init(
        searchQuery: String,
        filter: LibraryPlaylistSection? = nil
    ) {
        self.searchQuery = searchQuery
        self.filter = filter
    }

    var body: some View {
        List {
            if isSearching {
                searchResultsSection
            } else if let filter {
                playlistGridSection(for: filter)
            } else {
                overviewSections
            }
        }
        .listStyle(.plain)
        .disabled(isDeletingPlaylist)
        .environment(
            \.editMode,
            isReorderingSections
                ? .constant(.active)
                : .constant(.inactive)
        )
        .onChange(of: isSearching) { _, searching in
            // Swipe actions only work outside reorder mode; leave
            // reorder mode before the search results appear.
            if searching {
                isReorderingSections = false
            }
        }
        .confirmationDialog(
            "ui.playlists.delete.title",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { playlist in
            Button("ui.playlists.delete.action", role: .destructive) {
                Task { await deletePlaylist(playlist) }
            }
            Button("ui.common.cancel", role: .cancel) {}
        } message: { playlist in
            Text(L10n.format("ui.playlists.delete.message", playlist.name))
        }
        .alert("ui.library.error.title", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("ui.common.ok", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "")
        }
        .alert("ui.library.error.title", isPresented: Binding(
            get: { playbackErrorMessage != nil },
            set: { if !$0 { playbackErrorMessage = nil } }
        )) {
            Button("ui.common.ok", role: .cancel) {
                playbackErrorMessage = nil
            }
        } message: {
            Text(playbackErrorMessage ?? "")
        }
        .toolbar {
            if filter == nil {
                if isReorderingSections {
                    ToolbarItem(placement: .topBarTrailing) {
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
                    }
                } else {
                    // Create + sort in one capsule, Apple Music style.
                    ToolbarItemGroup(placement: .topBarTrailing) {
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
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        "ui.playlists.create.title",
                        systemImage: "plus"
                    ) {
                        showsCreation = true
                    }
                    .disabled(!library.isLoggedIn)
                }
            }
        }
        .sheet(isPresented: $showsCreation) {
            PlaylistCreationSheet { name, isPrivate in
                try await library.createPlaylist(name: name, isPrivate: isPrivate)
            }
            .presentationDetents([.medium])
        }
        .refreshable {
            await library.refresh(force: true)
        }
        .overlay {
            Group {
                if visiblePlaylists.isEmpty {
                    if isSearching {
                        ContentUnavailableView.search(
                            text: normalizedSearchQuery
                        )
                    } else if filter != nil {
                        ContentUnavailableView(
                            "ui.library.no_favorite_playlists",
                            systemImage: "music.note.list",
                            description: Text(
                                "ui.library.no_favorite_playlists.message"
                            )
                        )
                    }
                    // Overview with no playlists shows just the
                    // three rows (the rank link still works).
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Overview

    @ViewBuilder
    private var overviewSections: some View {
        if !pinnedPlaylists.isEmpty {
            Section("ui.library.playlists.pinned") {
                pinnedGrid
                    .listRowInsets(
                        EdgeInsets(
                            top: 8,
                            leading: 16,
                            bottom: 12,
                            trailing: 16
                        )
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .deleteDisabled(true)
                    .moveDisabled(true)
            }
        }

        Section {
            ForEach(settings.libraryPlaylistSectionOrder) { section in
                sectionRow(for: section)
                    .deleteDisabled(true)
            }
            .onMove(perform: moveSections)
        }
    }

    private var pinnedGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
            ],
            alignment: .leading,
            spacing: 24
        ) {
            ForEach(pinnedPlaylists) { playlist in
                playlistCard(for: playlist)
            }
        }
    }

    @ViewBuilder
    private func sectionRow(
        for section: LibraryPlaylistSection
    ) -> some View {
        switch section {
        case .listeningRank:
            if let userID = library.profile?.id {
                NavigationLink {
                    UserListeningRankView(userID: userID)
                } label: {
                    Label(
                        "ui.library.my_listening_rank",
                        systemImage: "chart.bar.xaxis"
                    )
                }
                .accessibilityHint("ui.library.my_listening_rank.hint")
            }
        case .own:
            NavigationLink {
                LibraryPlaylistsView(
                    searchQuery: searchQuery,
                    filter: .own
                )
                .navigationTitle(
                    L10n.string("ui.library.playlists.own")
                )
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label(
                    "ui.library.playlists.own",
                    systemImage: "music.note.list"
                )
            }
        case .collected:
            NavigationLink {
                LibraryPlaylistsView(
                    searchQuery: searchQuery,
                    filter: .collected
                )
                .navigationTitle(
                    L10n.string("ui.library.playlists.collected")
                )
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label(
                    "ui.library.playlists.collected",
                    systemImage: "heart"
                )
            }
        }
    }

    private func moveSections(
        from source: IndexSet,
        to destination: Int
    ) {
        var order = settings.libraryPlaylistSectionOrder
        order.move(fromOffsets: source, toOffset: destination)
        settings.setLibraryPlaylistSectionOrder(order)
    }

    // MARK: - Sub-page grid

    @ViewBuilder
    private func playlistGridSection(
        for section: LibraryPlaylistSection
    ) -> some View {
        Section {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                ],
                alignment: .leading,
                spacing: 24
            ) {
                ForEach(playlists(for: section)) { playlist in
                    playlistCard(for: playlist)
                }
            }
            .listRowInsets(
                EdgeInsets(
                    top: 8,
                    leading: 16,
                    bottom: 12,
                    trailing: 16
                )
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .deleteDisabled(true)
            .moveDisabled(true)
        }
    }

    /// A plain Button + programmatic navigation, NOT a
    /// NavigationLink. The grid is one List row holding many
    /// cards, and a List draws its disclosure chevron (">") on
    /// every NavigationLink row — meaningless beside a big
    /// square cover — and the links in that shared row all
    /// fired together: tapping one card pushed every playlist
    /// in the grid onto the stack. A Button gets no chevron,
    /// and one tap appends exactly one route, so one tap
    /// opens exactly one playlist. Context menu and the zoom
    /// transition are unchanged; search-result rows keep
    /// their NavigationLinks (and chevrons) as before.
    private func playlistCard(for playlist: Playlist) -> some View {
        Button {
            openMusicRoute(.playlist(playlist))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ArtworkImage(url: playlist.artworkURL, cornerRadius: 10)
                Text(playlist.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .musicMatchedTransitionSource(for: MusicRoute.playlist(playlist))
        .contextMenu {
            Button {
                Task { await playPlaylist(playlist, shuffled: false) }
            } label: {
                Label("ui.common.play", systemImage: "play.fill")
            }
            Button {
                Task { await playPlaylist(playlist, shuffled: true) }
            } label: {
                Label("ui.player.shuffle", systemImage: "shuffle")
            }
            Button {
                settings.setPlaylistPinned(
                    playlist.id,
                    pinned: !settings.isPlaylistPinned(playlist.id)
                )
            } label: {
                Label(
                    settings.isPlaylistPinned(playlist.id)
                        ? "ui.library.playlists.unpin"
                        : "ui.library.playlists.pin",
                    systemImage: settings.isPlaylistPinned(playlist.id)
                        ? "pin.slash"
                        : "pin"
                )
            }
        }
    }

    /// Same entry point as `PlaylistDetailView.playAll`: load the
    /// playlist's songs, then start playback from the player.
    private func playPlaylist(
        _ playlist: Playlist,
        shuffled: Bool
    ) async {
        do {
            let trackIDs = playlist.trackIDs.map(\.id)
            let songs = if trackIDs.isEmpty {
                playlist.tracks
            } else {
                try await api.songDetailsCollection(
                    ids: trackIDs,
                    prefetched: playlist.tracks
                )
            }
            guard !songs.isEmpty else { return }
            await player.playAll(
                shuffled ? songs.shuffled() : songs,
                sourceID: playlist.id
            )
        } catch {
            playbackErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Search results

    private var searchResultsSection: some View {
        Section(L10n.string("ui.common.search_results")) {
            ForEach(displayedPlaylists) { playlist in
                NavigationLink(value: MusicRoute.playlist(playlist)) {
                    LibraryPlaylistRow(playlist: playlist)
                }
                .musicMatchedTransitionSource(
                    for: MusicRoute.playlist(playlist)
                )
                .swipeActions(edge: .trailing) {
                    if library.canDelete(playlist) {
                        Button(role: .destructive) { pendingDeletion = playlist } label: {
                            Label("ui.playlists.delete.action", systemImage: "trash")
                        }
                    } else if library.canUnsubscribe(playlist) {
                        Button(role: .destructive) {
                            library.toggle(playlist: playlist)
                        } label: {
                            Label(
                                L10n.string("ui.common.unfavorite"),
                                systemImage: "heart.slash"
                            )
                        }
                    }
                }
            }
        }
    }

    private func deletePlaylist(_ playlist: Playlist) async {
        isDeletingPlaylist = true
        defer { isDeletingPlaylist = false }
        do {
            try await library.deletePlaylist(playlist)
        } catch {
            deletionError = error.localizedDescription
        }
    }

    // MARK: - Derived data

    private var normalizedSearchQuery: String {
        normalizedLibrarySearchQuery(searchQuery)
    }

    private var isSearching: Bool {
        !normalizedSearchQuery.isEmpty
    }

    private var displayedPlaylists: [Playlist] {
        filterLibraryPlaylists(
            library.favoritePlaylists,
            query: normalizedSearchQuery
        )
    }

    private var visiblePlaylists: [Playlist] {
        if isSearching {
            displayedPlaylists
        } else if let filter {
            playlists(for: filter)
        } else {
            displayedPlaylists
        }
    }

    private var pinnedPlaylists: [Playlist] {
        let byID = Dictionary(
            uniqueKeysWithValues: library.favoritePlaylists.map {
                ($0.id, $0)
            }
        )
        return settings.pinnedLibraryPlaylistIDs.compactMap {
            byID[$0]
        }
    }

    private func playlists(
        for section: LibraryPlaylistSection
    ) -> [Playlist] {
        // Explicit type: without it the empty-array branch makes
        // the compiler infer `base` as [Any] (the switch gives the
        // `[]` literal no element type to inherit).
        let base: [Playlist] = switch section {
        case .own:
            library.favoritePlaylists.filter(library.canDelete)
        case .collected:
            library.favoritePlaylists.filter(library.canUnsubscribe)
        case .listeningRank:
            []
        }
        return filterLibraryPlaylists(
            base,
            query: normalizedSearchQuery
        )
    }
}

private struct LibraryPlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(url: playlist.artworkURL, cornerRadius: 7)
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .lineLimit(1)
                Text(L10n.format("ui.common.song_count", playlist.trackCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
