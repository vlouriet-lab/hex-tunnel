class InstalledApp {
  final String packageName;
  final String label;
  final bool systemApp;

  const InstalledApp({
    required this.packageName,
    required this.label,
    this.systemApp = false,
  });

  factory InstalledApp.fromJson(Map<String, dynamic> json) {
    return InstalledApp(
      packageName: json['packageName'] as String? ?? '',
      label: json['label'] as String? ?? '',
      systemApp: json['systemApp'] as bool? ?? false,
    );
  }
}
