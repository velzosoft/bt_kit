/// A running test's live status line, and how far along it is (null when
/// unknown).
final class TestProgress {
  const TestProgress(this.summary, {this.fraction});

  final String summary;
  final double? fraction;
}
