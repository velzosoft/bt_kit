enum LabMode {
  quick('Quick'),
  full('Full');

  const LabMode(this.label);

  final String label;
}

/// How long and how hard each Lab test runs. [LabMode.full] is the complete
/// validation run; [LabMode.quick] is a smoke run.
final class LabPlan {
  const LabPlan._({
    required this.mode,
    required this.cycles,
    required this.soakDuration,
    required this.scanResults,
    required this.scanTimeLimit,
    required this.bursts,
    this.includePairing = false,
  });

  factory LabPlan(LabMode mode, {bool includePairing = false}) =>
      switch (mode) {
        LabMode.full => LabPlan._(
          mode: mode,
          cycles: 500,
          soakDuration: const Duration(minutes: 10),
          scanResults: 10000,
          scanTimeLimit: const Duration(minutes: 30),
          bursts: 50,
          includePairing: includePairing,
        ),
        LabMode.quick => LabPlan._(
          mode: mode,
          cycles: 50,
          soakDuration: const Duration(minutes: 1),
          scanResults: 2000,
          scanTimeLimit: const Duration(minutes: 5),
          bursts: 10,
          includePairing: includePairing,
        ),
      };

  final LabMode mode;
  final int cycles;
  final Duration soakDuration;
  final int scanResults;
  final Duration scanTimeLimit;
  final int bursts;

  /// Whether to read the encrypted characteristic, which makes both phones
  /// ask to pair.
  final bool includePairing;

  final soakRateHz = 50;
  final burstSize = 20;
  final connectTimeout = const Duration(seconds: 10);
  final cyclePause = const Duration(milliseconds: 250);

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'cycles': cycles,
    'soakSeconds': soakDuration.inSeconds,
    'soakRateHz': soakRateHz,
    'scanResults': scanResults,
    'scanTimeLimitSeconds': scanTimeLimit.inSeconds,
    'bursts': bursts,
    'burstSize': burstSize,
    'includePairing': includePairing,
  };
}
