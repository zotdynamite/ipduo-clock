import SwiftUI
import UIKit
import UserNotifications

enum AppIdentity {
    /// Working name. Change this, the display name, and the bundle id together.
    static let name = "Ipduo Clock"
}

@main
struct IpduoClockApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var playback = PlaybackCenter()
    @StateObject private var podcasts = PodcastClient()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(playback)
                .environmentObject(podcasts)
                .tint(model.accentColor)
                .preferredColorScheme(model.preferredScheme)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Screenshot runs lock portrait or landscape. Everyday launches allow both.
    static var orientationMask: UIInterfaceOrientationMask = .all

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationBridge.shared
        NotificationBridge.shared.registerCategories()
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationMask
    }
}

extension Notification.Name {
    static let ipduoAlarm = Notification.Name("ipduo.alarm")
}

enum AlarmNotificationAction {
    static let category = "IPDUO_ALARM"
    static let snooze = "SNOOZE"
    static let stop = "STOP"
    static let alarmID = "alarmID"
}

final class NotificationBridge: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationBridge()

    func registerCategories() {
        let snooze = UNNotificationAction(identifier: AlarmNotificationAction.snooze, title: "Snooze", options: [])
        let stop = UNNotificationAction(
            identifier: AlarmNotificationAction.stop,
            title: "Stop",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: AlarmNotificationAction.category,
            actions: [snooze, stop],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let id = notification.request.content.userInfo[AlarmNotificationAction.alarmID] as? String
        await MainActor.run {
            NotificationCenter.default.post(
                name: .ipduoAlarm,
                object: nil,
                userInfo: ["alarmID": id ?? "", "action": UNNotificationDefaultActionIdentifier]
            )
        }
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.content.userInfo[AlarmNotificationAction.alarmID] as? String
        await MainActor.run {
            NotificationCenter.default.post(
                name: .ipduoAlarm,
                object: nil,
                userInfo: ["alarmID": id ?? "", "action": response.actionIdentifier]
            )
        }
    }
}
