import AloftStrap
import UserNotifications

/// Posts the morning line once a finished night is on the phone. This is not
/// an alarm: it is not scheduled for the wake time, and nothing sounds if the
/// strap misses its buzz.
enum RecapNotifier {
    static func post(_ recap: MorningRecap) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let content = UNMutableNotificationContent()
        content.title = recap.notificationTitle
        content.body = recap.notificationBody
        let id = "aloft.recap.\(recap.onsetMs ?? 0)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await center.add(request)
    }
}
