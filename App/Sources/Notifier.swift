// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation
import UserNotifications
import AppKit

/// System notifications of download completion. Clicking the notification
/// reveals the file in Finder.
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

    /// Request authorization on first launch (silent if refused).
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    /// Post a "download complete" notification.
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

    // Show the banner even if the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Click on notification → reveal the file in Finder.
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
