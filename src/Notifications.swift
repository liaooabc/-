import Foundation
import UserNotifications

/// 系统通知：发现新版本时弹一条横幅，点它就把面板展开。
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private var granted = false
    private var asked = false
    var onOpen: (() -> Void)?

    var isAuthorized: Bool { granted }

    func setup() {
        guard !asked else { return }
        asked = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            Task { @MainActor in
                Notifier.shared.granted = ok
            }
        }
    }

    func post(title: String, body: String, id: String) {
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// App 在前台时也把横幅显示出来（默认会被吞掉）
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler:
                                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            Notifier.shared.onOpen?()
        }
        completionHandler()
    }
}
