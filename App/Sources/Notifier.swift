import UserNotifications

/// Sends the notifications a person asked for. None is sent unless alerts are switched on.
enum Notifier {
  /// Asks for permission to notify, once. Returns whether it is granted.
  static func askPermission() async -> Bool {
    (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert]))
      ?? false
  }

  /// - Parameter id: Names what the notification is about, so that a later one about the
  ///   same thing replaces it instead of piling up.
  static func post(_ text: String, id: String) {
    let content = UNMutableNotificationContent()
    content.title = "Still using CPU"
    content.body = text
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: id, content: content, trigger: nil))
  }
}
