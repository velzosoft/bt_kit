/// Trade-off between latency and power on a connection (Android).
enum ConnectionPriority {
  balanced,

  /// Short connection interval: low latency and high throughput.
  high,

  lowPower,
}
