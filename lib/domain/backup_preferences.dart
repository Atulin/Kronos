enum BackupFrequency {
  daily(Duration(days: 1), 'Daily'),
  weekly(Duration(days: 7), 'Weekly'),
  monthly(Duration(days: 30), 'Every 30 days');

  const BackupFrequency(this.interval, this.label);

  final Duration interval;
  final String label;

  static BackupFrequency parse(String? value) => switch (value) {
    'daily' => BackupFrequency.daily,
    'monthly' => BackupFrequency.monthly,
    _ => BackupFrequency.weekly,
  };
}

class BackupPreferences {
  const BackupPreferences({
    this.enabled = true,
    this.frequency = BackupFrequency.weekly,
    this.directoryUri,
    this.directoryName,
    this.lastBackupAt,
  });

  final bool enabled;
  final BackupFrequency frequency;
  final String? directoryUri;
  final String? directoryName;
  final DateTime? lastBackupAt;

  bool get hasCustomDirectory => directoryUri != null;
}
