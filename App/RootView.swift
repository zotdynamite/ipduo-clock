import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackCenter
    @EnvironmentObject private var podcasts: PodcastClient

    var body: some View {
        TabView(selection: $model.tab) {
            ClockScreen()
                .tabItem { Label(AppTab.clock.title, systemImage: AppTab.clock.symbol) }
                .tag(AppTab.clock)
            AlarmsScreen()
                .tabItem { Label(AppTab.alarms.title, systemImage: AppTab.alarms.symbol) }
                .tag(AppTab.alarms)
            TimersScreen()
                .tabItem { Label(AppTab.timers.title, systemImage: AppTab.timers.symbol) }
                .tag(AppTab.timers)
            WorldClockScreen()
                .tabItem { Label(AppTab.world.title, systemImage: AppTab.world.symbol) }
                .tag(AppTab.world)
            ListenScreen()
                .tabItem { Label(AppTab.listen.title, systemImage: AppTab.listen.symbol) }
                .tag(AppTab.listen)
        }
        .duoPrefersTabBar()
        .safeAreaInset(edge: .bottom, spacing: 8) {
            if playback.showsMiniPlayer {
                MiniPlayer()
                    .padding(.horizontal)
            }
        }
        .sheet(isPresented: $model.settingsPresented) {
            SettingsScreen()
        }
        .sheet(isPresented: $model.nowPlayingPresented) {
            NavigationStack {
                NowPlayingView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                model.nowPlayingPresented = false
                            } label: {
                                Label("Close", systemImage: "xmark")
                            }
                        }
                        .duoPriorityHigh()
                    }
            }
        }
        .fullScreenCover(isPresented: $model.standByPresented) {
            StandByView()
        }
        .fullScreenCover(item: $model.ringingAlarm) { alarm in
            RingingView(alarm: alarm)
        }
        .screenshotMarker()
        .onAppear {
            playback.prepare(rate: model.playbackRate)
            playback.bindProgress { id, seconds, duration in
                model.rememberPlayback(id: id, seconds: seconds, duration: duration)
            }
            Task { await model.rescheduleAlarms() }
        }
        .task {
            await ScreenshotDirector.prepare(model: model, playback: playback, podcasts: podcasts)
        }
        .onChange(of: model.tab) { _, _ in
            model.touch()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                model.persist()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ipduoAlarm)) { note in
            let id = note.userInfo?["alarmID"] as? String ?? ""
            let action = note.userInfo?["action"] as? String ?? ""
            model.handleAlarm(id: id, action: action, playback: playback)
        }
    }
}
