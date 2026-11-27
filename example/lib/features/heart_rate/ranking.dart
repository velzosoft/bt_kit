/// [players] from the highest current heart rate to the lowest. Players
/// without a current reading go last; ties keep the given order.
List<T> rankByBpm<T>(List<T> players, int? Function(T player) bpmOf) {
  final entries = [
    for (final (index, player) in players.indexed)
      (index: index, bpm: bpmOf(player), player: player),
  ];
  entries.sort((a, b) {
    final (aBpm, bBpm) = (a.bpm, b.bpm);
    if (aBpm == bBpm) return a.index.compareTo(b.index);
    if (aBpm == null) return 1;
    if (bBpm == null) return -1;
    return bBpm.compareTo(aBpm);
  });
  return [for (final entry in entries) entry.player];
}
