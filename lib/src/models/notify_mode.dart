/// How a peripheral pushes characteristic values.
enum NotifyMode {
  /// Notification when the characteristic supports it, otherwise
  /// indication.
  auto,

  /// Unacknowledged pushes.
  notification,

  /// Pushes the central acknowledges: slower, but none are lost.
  indication,
}
