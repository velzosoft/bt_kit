/// A device that stayed while the devices around it were replaced.
final class StayedDevice {
  const StayedDevice({
    required this.id,
    required this.firstSeen,
    required this.stays,
    required this.flaggedAt,
  });

  final String id;

  /// The first snapshot that included the device.
  final DateTime firstSeen;

  /// How many changes of surroundings it stayed through.
  final int stays;

  /// When it reached [StayDetector.staysToFlag] stays within
  /// [StayDetector.flagWithin], if it has.
  final DateTime? flaggedAt;

  bool get isFlagged => flaggedAt != null;
}

/// Finds devices that stay with you while your surroundings change, from
/// periodic snapshots of the device ids heard nearby. It needs no location.
///
/// The surroundings change (a churn event) when at least [churnShare] of
/// the other devices in the reference snapshot are gone. Each device present
/// on both sides of the change stayed through it. A device that stays
/// through [staysToFlag] changes within [flagWithin] is flagged, and stays
/// flagged.
final class StayDetector {
  static const churnShare = 0.8;

  /// A reference with fewer other devices than this is too small to judge.
  static const minimumOthers = 5;
  static const staysToFlag = 3;
  static const flagWithin = Duration(hours: 1);

  ({DateTime at, Set<String> ids})? _reference;
  final _firstSeen = <String, DateTime>{};
  final _lastSeen = <String, DateTime>{};
  final _records = <String, _StayRecord>{};
  var _churnEvents = 0;

  int get churnEvents => _churnEvents;

  /// Flagged devices, most stays first.
  List<StayedDevice> get flagged =>
      [
        for (final MapEntry(key: id, value: record) in _records.entries)
          if (record.flaggedAt != null) record.toStayed(id),
      ]..sort((a, b) {
        final byStays = b.stays.compareTo(a.stays);
        return byStays != 0 ? byStays : a.flaggedAt!.compareTo(b.flaggedAt!);
      });

  /// Devices that stayed through at least one change but are not flagged.
  int get unflaggedStayers =>
      _records.values.where((record) => record.flaggedAt == null).length;

  int staysOf(String id) => _records[id]?.total ?? 0;

  /// Adds the ids heard around [at] and returns whether the surroundings
  /// changed since the reference snapshot. An empty snapshot says nothing
  /// about the surroundings and is ignored.
  bool addSnapshot(DateTime at, Set<String> ids) {
    if (ids.isEmpty) return false;
    _remember(at, ids);
    final reference = _reference;
    if (reference == null || reference.ids.length - 1 < minimumOthers) {
      _reference = (at: at, ids: ids);
      return false;
    }
    final stayed = reference.ids.intersection(ids);
    final departed = reference.ids.length - stayed.length;
    final others = reference.ids.length - 1;
    if (departed < churnShare * others) return false;

    _churnEvents++;
    for (final id in stayed) {
      _records.putIfAbsent(id, () => _StayRecord(_firstSeen[id]!)).stayed(at);
    }
    _reference = (at: at, ids: ids);
    return true;
  }

  void _remember(DateTime at, Set<String> ids) {
    for (final id in ids) {
      _firstSeen.putIfAbsent(id, () => at);
      _lastSeen[id] = at;
    }
    final cutoff = at.subtract(flagWithin);
    _lastSeen.removeWhere((id, last) {
      final forget = last.isBefore(cutoff) && !_records.containsKey(id);
      if (forget) _firstSeen.remove(id);
      return forget;
    });
  }
}

final class _StayRecord {
  _StayRecord(this.firstSeen);

  final DateTime firstSeen;
  final _recent = <DateTime>[];
  var total = 0;
  DateTime? flaggedAt;

  void stayed(DateTime at) {
    total++;
    _recent
      ..add(at)
      ..removeWhere((stay) => at.difference(stay) > StayDetector.flagWithin);
    if (_recent.length >= StayDetector.staysToFlag) flaggedAt ??= at;
  }

  StayedDevice toStayed(String id) => StayedDevice(
    id: id,
    firstSeen: firstSeen,
    stays: total,
    flaggedAt: flaggedAt,
  );
}
