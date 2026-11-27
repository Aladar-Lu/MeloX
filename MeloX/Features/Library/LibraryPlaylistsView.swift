import SwiftUI
import UniformTypeIdentifiers

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

    @State private var pendingDeletion: Playlist?
    @State private var isDeletingPlaylist = false
    @State private var deletionError: String?
    @State private var playbackErrorMessage: String?
    @State private var draggedSection: LibraryPlaylistSection?

    /// Create / sort state. The 收藏歌单 tab root passes its own
    /// bindings (owned by LibraryView, driven by the one-line
    /// header); every other use (fixed page, sub-page) passes
    /// nothing and keeps local state.
    private let isReorderingSectionsBinding: Binding<Bool>?
    private let showsCreationBinding: Binding<Bool>?
    @State private var localIsReorderingSections = false
    @State private var localShowsCreation = false

    /// The create / sort state: the tab root's binding when one
    /// was passed, otherwise this view's own local state.
    private var reordering: Binding<Bool> {
        isReorderingSectionsBinding ?? $localIsReorderingSections
    }
    private var creation: Binding<Bool> {
        showsCreationBinding ?? $localShowsCreation
    }

    init(
        searchQuery: String,
        filter: LibraryPlaylistSection? = nil,
        isReorderingSections: Binding<Bool>? = nil,
        showsCreation: Binding<Bool>? = nil
    ) {
        self.searchQuery = searchQuery
        self.filter = filter
        self.isReorderingSectionsBinding = isReorderingSections
        self.showsCreationBinding = showsCreation
    }

    var body: some View {
        // The grids live in a ScrollView, NOT in a List. A grid
        // inside a List is one List row holding many cards, so a
        // long-press lifts the whole grid as one image (and the
        // List drew a ">" on every NavigationLink card). In a
        // ScrollView each card is its own view: long-press lifts
        // only that card, and a Button gets no chevron. The
        // search results are the one place a List is still
        // right — they are proper rows, with swipe actions.
        Group {
            if isSearching {
                List {
                    searchResultsSection
                }
                .listStyle(.plain)
            } else if let filter {
                ScrollView {
                    playlistGrid(for: filter)
                }
            } else {
                ScrollView {
                    overviewContent
                }
            }
        }
        .disabled(isDeletingPlaylist)
        .onChange(of: isSearching) { _, searching in
            // Leave reorder mode before the search results
            // appear; the reorder drag handles only exist on
            // the overview rows.
            if searching {
                reordering.wrappedValue = false
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
            // On the main tab root the one-line header (in
            // LibraryView) owns the create / sort buttons, so
            // this toolbar stays empty there. Fixed pages and
            // sub-pages keep their toolbar buttons.
            if isReorderingSectionsBinding == nil {
                if filter == nil {
                if reordering.wrappedValue {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            reordering.wrappedValue = false
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
                            creation.wrappedValue = true
                        }
                        .disabled(!library.isLoggedIn)

                        Menu {
                            Button("ui.library.playlists.sort") {
                                reordering.wrappedValue = true
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
                        creation.wrappedValue = true
                    }
                    .disabled(!library.isLoggedIn)
                }
            }
            }
        }
        .sheet(isPresented: creation) {
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

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !pinnedPlaylists.isEmpty {
                Text("ui.library.playlists.pinned")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                pinnedGrid
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }

            VStack(spacing: 0) {
                ForEach(visibleSections) { section in
                    sectionRow(for: section)
                    if section != visibleSections.last {
                        Divider()
                            // Under the row text, not under the
                            // icon: text starts at 16 (edge
                            // padding) + ~22 (icon) + 12 (gap).
                            .padding(.leading, 50)
                    }
                }
            }
            .padding(.top, pinnedPlaylists.isEmpty ? 8 : 16)
        }
        .padding(.bottom, 12)
    }

    /// The three rows that have something to show. The
    /// listening-rank row needs a logged-in profile; when it
    /// is hidden the other two still reorder around it.
    private var visibleSections: [LibraryPlaylistSection] {
        settings.libraryPlaylistSectionOrder.filter { section in
            if section == .listeningRank {
                library.profile?.id != nil
            } else {
                true
            }
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

    /// In reorder mode the row is plain (no NavigationLink, so
    /// a tap cannot navigate away mid-drag) and draggable; the
    /// drag handle replaces the chevron. Outside reorder mode
    /// it is a NavigationLink with an explicit chevron — a
    /// NavigationLink in a ScrollView gets no automatic one.
    @ViewBuilder
    private func sectionRow(
        for section: LibraryPlaylistSection
    ) -> some View {
        if reordering.wrappedValue {
            sectionRowLabel(for: section)
                .onDrag {
                    draggedSection = section
                    return NSItemProvider(
                        object: section.id as NSString
                    )
                }
                .onDrop(
                    of: [.text],
                    delegate: SectionReorderDropDelegate(
                        targetSection: section,
                        draggedSection: $draggedSection,
                        settings: settings
                    )
                )
        } else {
            switch section {
            case .listeningRank:
                if let userID = library.profile?.id {
                    NavigationLink {
                        UserListeningRankView(userID: userID)
                    } label: {
                        sectionRowLabel(for: section)
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
                    sectionRowLabel(for: section)
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
                    sectionRowLabel(for: section)
                }
            }
        }
    }

    private func sectionRowLabel(
        for section: LibraryPlaylistSection
    ) -> some View {
        HStack(spacing: 12) {
            Label(section.title, systemImage: sectionIcon(for: section))
            Spacer()
            if reordering.wrappedValue {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .contentShape(.rect)
    }

    private func sectionIcon(
        for section: LibraryPlaylistSection
    ) -> String {
        switch section {
        case .listeningRank:
            "chart.bar.xaxis"
        case .own:
            "music.note.list"
        case .collected:
            "heart"
        }
    }

    // MARK: - Sub-page grid

    private func playlistGrid(
        for section: LibraryPlaylistSection
    ) -> some View {
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
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// A plain Button + programmatic navigation, NOT a
    /// NavigationLink. The grid is a ScrollView of standalone
    /// cards now (it used to be one List row holding many
    /// cards, which is why a List drew a ">" on every card
    /// and a long-press lifted the whole grid as one image).
    /// A Button in a ScrollView gets no chevron, one tap
    /// appends exactly one route, and a long-press lifts only
    /// the card pressed. Context menu and the zoom transition
    /// are unchanged; search-result rows keep their
    /// NavigationLinks (and chevrons) as before.
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

/// Drag-to-reorder for the three overview rows, which live in
/// a ScrollView now (List .onMove only works in a List). The
/// dragged row is tracked in the view's state; dropping it on
/// another row moves it there in the persisted order.
private struct SectionReorderDropDelegate: DropDelegate {
    let targetSection: LibraryPlaylistSection
    @Binding var draggedSection: LibraryPlaylistSection?
    let settings: AppSettings

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedSection,
              dragged != targetSection
        else { return }
        var order = settings.libraryPlaylistSectionOrder
        guard let from = order.firstIndex(of: dragged),
              let to = order.firstIndex(of: targetSection)
        else { return }
        order.move(
            fromOffsets: IndexSet(integer: from),
            toOffset: to > from ? to + 1 : to
        )
        settings.setLibraryPlaylistSectionOrder(order)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedSection = nil
        return true
    }
}
