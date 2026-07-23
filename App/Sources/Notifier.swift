import Foundation
import UserNotifications
import AppKit

/// Notifications système de fin de téléchargement. Un clic sur la notification
/// révèle le fichier dans le Finder.
final class Notifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = Notifier()

    private let center = UNUserNotificationCenter.current()
    private let lock = NSLock()
    private var _authorized = false
    private var authorized: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _authorized }
        set { lock.lock(); _authorized = newValue; lock.unlock() }
    }
    private let filePathKey = "filePath"

    private override init() {
        super.init()
        center.delegate = self
    }

    /// Demande l'autorisation au premier lancement (silencieux si refusé).
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    /// Poste une notification « téléchargement terminé ».
    func downloadFinished(title: String, fileURL: URL?) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Download complete"
        content.body = title
        content.sound = .default
        if let path = fileURL?.path { content.userInfo = [filePathKey: path] }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    // Affiche la bannière même si l'app est au premier plan.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Clic sur la notification → révèle le fichier dans le Finder.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let path = response.notification.request.content.userInfo[filePathKey] as? String {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
        completionHandler()
    }
}
