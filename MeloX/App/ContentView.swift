import SwiftUI

private enum ContentSheet: String, Identifiable {
    case settings

    var id: String { rawValue }
}

private enum ContentRoute: Hashable {
    case privateMessages
    case songRecognition
}

private struct HeartModeLaunchReadiness: Equatable {
    let hasRestoredPlayback: Bool
    let isLoggedIn: Bool
    let canStartHeartMode: Bool
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PlayerStore.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(DownloadStore.self) private var downloads
    @Environment(LyricsStore.self) private var lyrics
    @Environment(FloatingLyricsController.self) private var floatingLyrics

    @State private var selectedTab: AppTab
    @State private var navigationPaths = Dictionary(
        uniqueKeysWithValues: AppTab.allCases.map {
            ($0, NavigationPath())
        }
    )
    @State private var presentedSheet: ContentSheet?
    @State private var playerPresentation: PlayerPresentation?
    @State private var neteaseSharePresentation: NeteaseSharePresentation?
    @State private var nowPlayingSharePresentation: NeteaseSharePresentation?
    @State private var pendingMusicRoute: MusicRoute?
    @State private var isTabViewBottomAccessorySuppressed = false

    /// Durable "open Now Playing" request from MeloXApp (Live
    /// Activity / Dynamic Island tap). A plain flag instead of the
    /// old fire-and-forget notification: if the app cold-starts
    /// from the deep link, the flag is still set when this view
    /// appears, so the request cannot be lost.
    @Binding private var openNowPlaying: Bool
    @State private var hasRestoredPlayback = false
    @State private var hasHandledHeartModeLaunch = false
    @State private var heartModeLaunchErrorMessage: String?
    @Namespace private var playerTransitionNamespace
    @Namespace private var musicNavigationNamespace

    private let playerTransitionID = "now-playing"

    init(
        initialTab: AppTab = .home,
        openNowPlaying: Binding<Bool> = .constant(false)
    ) {
        _selectedTab = State(initialValue: initialTab)
        _openNowPlaying = openNowPlaying
    }

    var body: some View {
        Group {
            if settings.hasCompletedOnboarding {
                mainExperience
            } else {
                OnboardingView()
            }
        }
    }

    private var mainExperience: some View {
        playerAwareTabView
            .environment(
                \.openMusicRoute,
                OpenMusicRouteAction(action: openMusicRoute)
            )
            .environment(
                \.openNeteaseShare,
                OpenNeteaseShareAction(action: openNeteaseShare)
            )
            .environment(
                \.setTabViewBottomAccessorySuppressed,
                SetTabViewBottomAccessorySuppressedAction {
                    isTabViewBottomAccessorySuppressed = $0
                }
            )
            .fullScreenCover(
                item: $playerPresentation,
                onDismiss: finishPendingSongNavigation
            ) { destination in
                switch destination {
                case .nowPlaying:
                    NowPlayingView(initialPage: initialNowPlayingPage)
                        .environment(
                            \.openMusicRoute,
                            OpenMusicRouteAction(action: openMusicRoute)
                        )
                        .environment(
                            \.openNeteaseShare,
                            OpenNeteaseShareAction { presentation in
                                presentNeteaseShare(
                                    presentation,
                                    fromNowPlaying: true
                                )
                            }
                        )
                        .sheet(item: $nowPlayingSharePresentation) {
                            presentation in
                            NeteaseShareSheet(presentation: presentation)
                        }
                        .presentationBackground(.clear)
                        .presentationContentInteraction(.resizes)
                        .navigationTransition(
                            .zoom(
                                sourceID: playerTransitionID,
                                in: playerTransitionNamespace
                            )
                        )
                }
            }
            .sheet(item: $neteaseSharePresentation) { presentation in
                NeteaseShareSheet(presentation: presentation)
            }
            .sheet(item: $presentedSheet) { destination in
                switch destination {
                case .settings:
                    NavigationStack {
                        SettingsView()
                            .musicDestinations(
                                in: musicNavigationNamespace
                            )
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(32)
                }
            }
            .task {
                await player.restore()
                guard !Task.isCancelled else { return }
                hasRestoredPlayback = true
            }
            .task(
                id: HeartModeLaunchReadiness(
                    hasRestoredPlayback: hasRestoredPlayback,
                    isLoggedIn: library.isLoggedIn,
                    canStartHeartMode: library.canStartHeartMode
                )
            ) {
                await startHeartModeOnLaunchIfNeeded()
            }
            .task(id: player.currentSong?.id) {
                await synchronizeLyrics()
            }
            .onChange(of: settings.lyricsSourcePreference) { _, _ in
                Task { await synchronizeLyrics() }
            }
            .task {
                await floatingLyrics.monitor()
            }
            .task(id: settings.cookie) {
                await library.refresh()
            }
            .background(alignment: .topLeading) {
                FloatingLyricsPictureInPictureSource(
                    controller: floatingLyrics
                )
                .frame(
                    width:
                        FloatingLyricsPictureInPictureSource
                            .sourceSize.width,
                    height:
                        FloatingLyricsPictureInPictureSource
                            .sourceSize.height
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onChange(of: selectedTab) { _, tab in
                settings.lastSelectedTab = tab
            }
            .onChange(of: settings.visibleTabs) { _, tabs in
                guard !tabs.contains(selectedTab) else { return }
                if settings.homeTabs.contains(selectedTab),
                   tabs.contains(.home) {
                    selectedTab = .home
                } else if selectedTab.libraryPage != nil,
                   tabs.contains(.library) {
                    selectedTab = .library
                } else {
                    selectedTab = settings.fallbackNavigationTab
                }
            }
            .onChange(of: scenePhase) { _, phase in
                player.refreshLyricsNotification()
                guard phase == .active else { return }
                player.refreshLyricsLiveActivity()
            }
            .onChange(of: openNowPlaying) { _, shouldOpen in
                guard shouldOpen else { return }
                // Live Activity / Dynamic Island tap: open the app
                // on the Now Playing screen. No current-song guard
                // here — playback may still be restoring after a
                // cold start, and NowPlayingView handles a nil song.
                openNowPlaying = false
                playerPresentation = .nowPlaying
            }
            .onAppear {
                // Cold start from a Live Activity tap: the flag may
                // already be set before this view appeared, so the
                // onChange above never fires for it.
                guard openNowPlaying else { return }
                openNowPlaying = false
                playerPresentation = .nowPlaying
            }
            .onChange(of: floatingLyrics.restorationRequestID) {
                guard floatingLyrics.restorationRequestID > 0,
                      player.currentSong != nil else {
                    floatingLyrics.completeRestoration(success: false)
                    return
                }

                playerPresentation = .nowPlaying
                Task { @MainActor in
                    await Task.yield()
                    floatingLyrics.completeRestoration(success: true)
                }
            }
            .alert(
                "ui.error.playback.title",
                isPresented: Binding(
                    get: { player.playbackIssue != nil },
                    set: { isPresented in
                        if !isPresented {
                            player.dismissPlaybackIssue()
                        }
                    }
                )
            ) {
                if player.canPlayNext {
                    Button("ui.player.play_next") {
                        player.dismissPlaybackIssue()
                        Task { await player.next() }
                    }
                }
                Button("ui.common.ok", role: .cancel) {
                    player.dismissPlaybackIssue()
                }
            } message: {
                Text(player.playbackIssue?.message ?? L10n.string("ui.error.playback.current_unavailable"))
            }
            .alert(
                "ui.error.heart_mode_launch.title",
                isPresented: Binding(
                    get: { heartModeLaunchErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            heartModeLaunchErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("ui.common.ok", role: .cancel) {
                    heartModeLaunchErrorMessage = nil
                }
            } message: {
                Text(heartModeLaunchErrorMessage ?? L10n.string("ui.error.try_again_later"))
            }
            .alert(
                "ui.error.download.title",
                isPresented: Binding(
                    get: {
                        AppFeatureAvailability.downloads
                            && downloads.errorMessage != nil
                    },
                    set: { isPresented in
                        if !isPresented {
                            downloads.clearError()
                        }
                    }
                )
            ) {
                Button("ui.common.ok", role: .cancel) {
                    downloads.clearError()
                }
            } message: {
                Text(downloads.errorMessage ?? L10n.string("ui.error.download.operation_failed"))
            }
            .alert(
                "ui.error.floating_lyrics.title",
                isPresented: Binding(
                    get: { floatingLyrics.errorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            floatingLyrics.dismissError()
                        }
                    }
                )
            ) {
                Button("ui.common.ok", role: .cancel) {
                    floatingLyrics.dismissError()
                }
            } message: {
                Text(
                    floatingLyrics.errorMessage
                        ?? L10n.string("ui.error.picture_in_picture.unavailable")
                )
            }
            .coordinateListenTogether()
            .recognizesClipboardLinksOnLaunch { song in
                openMusicRoute(.song(song))
            }
            .appLaunchExperience()
    }

    private func synchronizeLyrics() async {
        let song = player.currentSong
        let lyricSong = song?.isPodcastProgram == true ? nil : song
        await lyrics.load(for: lyricSong)
        guard !Task.isCancelled else { return }
        player.setNowPlayingLyrics(lyrics.lyrics, for: lyricSong?.id)
    }

    private func startHeartModeOnLaunchIfNeeded() async {
        guard !hasHandledHeartModeLaunch,
              hasRestoredPlayback else {
            return
        }
        guard settings.startsHeartModeOnLaunch else {
            hasHandledHeartModeLaunch = true
            return
        }
        guard library.isLoggedIn else {
            hasHandledHeartModeLaunch = true
            return
        }
        guard library.canStartHeartMode,
              let playlistID = library.likedPlaylistID,
              let seedSongID = library.randomHeartModeSeedSongID() else {
            return
        }

        hasHandledHeartModeLaunch = true
        do {
            try await player.playHeartMode(
                playlistID: playlistID,
                seedSongID: seedSongID
            )
        } catch is CancellationError {
            return
        } catch {
            heartModeLaunchErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var playerAwareTabView: some View {
        if player.currentSong != nil {
            if #available(iOS 26.1, *) {
                tabs
                    .tabViewBottomAccessory(
                        isEnabled: !isTabViewBottomAccessorySuppressed
                    ) {
                        miniPlayer
                    }
            } else {
                tabs
                    .tabViewBottomAccessory {
                        if !isTabViewBottomAccessorySuppressed {
                            miniPlayer
                        }
                    }
            }
        } else {
            tabs
        }
    }

    private var miniPlayer: some View {
        MiniPlayerView(
            artworkTransitionID: playerTransitionID,
            artworkTransitionNamespace:
                playerTransitionNamespace
        ) {
            playerPresentation = .nowPlaying
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            ForEach(settings.visibleTabs) { tab in
                Tab(
                    tab.title,
                    systemImage: tab.systemImage,
                    value: tab,
                    role: tab == .search ? .search : nil
                ) {
                    if tab == .home {
                        // The messages + recognition capsule
                        // floats in the Home bar row (see
                        // homeMessagesCapsule). It needs the
                        // safe-area top to sit centred in the
                        // bar row, next to the avatar button.
                        GeometryReader { geometry in
                            navigationStack(for: tab)
                                .overlay(alignment: .topTrailing) {
                                    if navigationPaths[.home]?.isEmpty == true {
                                        homeMessagesCapsule
                                            .padding(
                                                .top,
                                                geometry.safeAreaInsets.top + 4
                                            )
                                            .padding(.trailing, 72)
                                    }
                                }
                        }
                    } else {
                        navigationStack(for: tab)
                    }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(\.musicNavigationNamespace, musicNavigationNamespace)
    }

    private func navigationStack(for tab: AppTab) -> some View {
        NavigationStack(
            path: navigationPathBinding(for: tab)
        ) {
            tabRoot(for: tab)
                .navigationDestination(
                    for: ContentRoute.self
                ) { route in
                    contentDestination(for: route)
                }
                .musicDestinations(
                    in: musicNavigationNamespace
                )
        }
    }

    /// Private messages + song recognition as a floating glass
    /// capsule in the Home bar row, to the left of the avatar
    /// button. They CANNOT live in the toolbar: iOS 27 merges
    /// every .topBarTrailing item — from any view, at any level
    /// — into a single pill, so the avatar split kept failing
    /// (9110403 and 9110405 both showed one merged capsule).
    /// The avatar stays in HomeView's toolbar, alone in its own
    /// circular button at the far right; this capsule sits 72pt
    /// from the right edge, clearing it with an 8-12pt gap.
    /// Hidden whenever the Home stack has pushed a page, so it
    /// never covers a detail page's own bar buttons.
    private var homeMessagesCapsule: some View {
        HStack(spacing: 16) {
            if library.isLoggedIn {
                Button {
                    navigate(to: .privateMessages, in: .home)
                } label: {
                    Label("ui.messages.private.title", systemImage: "bubble.left.and.bubble.right")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("ui.messages.private.title")
                .accessibilityHint("ui.messages.private.open_hint")
            }

            Button {
                navigate(to: .songRecognition, in: .home)
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
    private func tabRoot(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(onAccountTap: { presentedSheet = .settings })
        case .recommended:
            HomeRecommendedView()
                .navigationTitle("ui.navigation.recommended")
        case .music:
            ExploreView(navigationTitle: L10n.string("ui.navigation.music"))
        case .podcasts:
            PodcastHomeView()
        case .explore:
            ExploreView()
        case .library:
            LibraryView()
        case .search:
            SearchView()
        case .librarySongs,
             .libraryPlaylists,
             .libraryAlbums,
             .libraryArtists,
             .libraryPodcasts,
             .libraryDownloads,
             .libraryCloud,
             .libraryHistory:
            if let page = tab.libraryPage {
                LibraryView(fixedPage: page)
            }
        }
    }

    @ViewBuilder
    private func contentDestination(
        for route: ContentRoute
    ) -> some View {
        switch route {
        case .privateMessages:
            NeteasePrivateMessagesView()
        case .songRecognition:
            SongRecognitionView()
        }
    }

    private func navigationPathBinding(
        for tab: AppTab
    ) -> Binding<NavigationPath> {
        Binding(
            get: {
                navigationPaths[tab] ?? NavigationPath()
            },
            set: {
                navigationPaths[tab] = $0
            }
        )
    }

    private var initialNowPlayingPage: NowPlayingPage {
        guard settings.rememberNowPlayingPage else { return .artwork }
        return NowPlayingPage(rawValue: settings.rememberedNowPlayingPage) ?? .artwork
    }

    private func openMusicRoute(_ route: MusicRoute) {
        guard playerPresentation == nil else {
            pendingMusicRoute = route
            playerPresentation = nil
            return
        }
        navigate(to: route)
    }

    private func openNeteaseShare(
        _ presentation: NeteaseSharePresentation
    ) {
        presentNeteaseShare(presentation, fromNowPlaying: false)
    }

    private func presentNeteaseShare(
        _ presentation: NeteaseSharePresentation,
        fromNowPlaying: Bool
    ) {
        Task { @MainActor in
            // Menu actions can fire before the system has completed
            // dismissing the menu. Present on the next settled UI turn.
            try? await Task.sleep(for: .milliseconds(140))
            if fromNowPlaying {
                nowPlayingSharePresentation = presentation
            } else {
                neteaseSharePresentation = presentation
            }
        }
    }

    private func finishPendingSongNavigation() {
        guard let route = pendingMusicRoute else { return }
        pendingMusicRoute = nil
        navigate(to: route)
    }

    private func navigate(
        to route: ContentRoute,
        in tab: AppTab
    ) {
        var path = navigationPaths[tab] ?? NavigationPath()
        path.append(route)
        navigationPaths[tab] = path
    }

    private func navigate(to route: MusicRoute) {
        var path = navigationPaths[selectedTab] ?? NavigationPath()
        path.append(route)
        navigationPaths[selectedTab] = path
    }
}
