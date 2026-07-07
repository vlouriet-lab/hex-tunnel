import 'package:flutter_test/flutter_test.dart';
import 'package:hex_decensor/services/singbox_service.dart';

void main() {
  group('ConnectivityProbeResult reasonDescription', () {
    test('returns offline description', () {
      final text = ConnectivityProbeResult.reasonDescription(
        'offline',
        requiresGovProbe: false,
      );

      expect(text, contains('устройство без стабильного интернета'));
    });

    test('returns gov-specific description for gov_blocked', () {
      final text = ConnectivityProbeResult.reasonDescription(
        'gov_blocked',
        requiresGovProbe: true,
      );

      expect(text, contains('gov-ресурсам'));
    });

    test('returns fallback description for unknown code', () {
      final text = ConnectivityProbeResult.reasonDescription(
        'mystery_code',
        requiresGovProbe: false,
      );

      expect(text, contains('не определена'));
    });
  });
}
