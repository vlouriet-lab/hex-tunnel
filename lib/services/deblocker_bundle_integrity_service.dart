import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/deblocker_runtime_bundle.dart';

enum DeblockerBundleIntegrityStatus {
  valid,
  missingChecksum,
  checksumMismatch,
  unsupportedSignature,
}

extension DeblockerBundleIntegrityStatusExt on DeblockerBundleIntegrityStatus {
  String get key {
    switch (this) {
      case DeblockerBundleIntegrityStatus.valid:
        return 'valid';
      case DeblockerBundleIntegrityStatus.missingChecksum:
        return 'missing_checksum';
      case DeblockerBundleIntegrityStatus.checksumMismatch:
        return 'checksum_mismatch';
      case DeblockerBundleIntegrityStatus.unsupportedSignature:
        return 'unsupported_signature';
    }
  }
}

class DeblockerBundleIntegrityResult {
  final DeblockerBundleIntegrityStatus status;
  final String? declaredChecksum;
  final String? actualChecksum;

  const DeblockerBundleIntegrityResult({
    required this.status,
    this.declaredChecksum,
    this.actualChecksum,
  });

  bool get isValid => status == DeblockerBundleIntegrityStatus.valid;
}

class DeblockerBundleIntegrityService {
  const DeblockerBundleIntegrityService();

  DeblockerRuntimeBundle attachIntegrityMetadata(
    DeblockerRuntimeBundle bundle, {
    bool includeDetachedSignature = true,
  }) {
    final checksum = computeChecksum(bundle);
    return bundle.copyWith(
      checksum: checksum,
      signature:
          includeDetachedSignature ? 'sha256:$checksum' : bundle.signature,
    );
  }

  DeblockerBundleIntegrityResult validate(DeblockerRuntimeBundle bundle) {
    final declaredChecksum = bundle.checksum?.trim() ?? '';
    if (declaredChecksum.isEmpty) {
      return const DeblockerBundleIntegrityResult(
        status: DeblockerBundleIntegrityStatus.missingChecksum,
      );
    }

    final actualChecksum = computeChecksum(bundle);
    if (actualChecksum != declaredChecksum) {
      return DeblockerBundleIntegrityResult(
        status: DeblockerBundleIntegrityStatus.checksumMismatch,
        declaredChecksum: declaredChecksum,
        actualChecksum: actualChecksum,
      );
    }

    final signature = bundle.signature?.trim() ?? '';
    if (signature.isNotEmpty && signature != 'sha256:$declaredChecksum') {
      return DeblockerBundleIntegrityResult(
        status: DeblockerBundleIntegrityStatus.unsupportedSignature,
        declaredChecksum: declaredChecksum,
        actualChecksum: actualChecksum,
      );
    }

    return DeblockerBundleIntegrityResult(
      status: DeblockerBundleIntegrityStatus.valid,
      declaredChecksum: declaredChecksum,
      actualChecksum: actualChecksum,
    );
  }

  String computeChecksum(DeblockerRuntimeBundle bundle) {
    final canonicalJson = jsonEncode(_canonicalize(bundle.toIntegrityJson()));
    return sha256.convert(utf8.encode(canonicalJson)).toString();
  }

  dynamic _canonicalize(dynamic value) {
    if (value is Map<String, dynamic>) {
      final keys = value.keys.toList(growable: false)..sort();
      return <String, dynamic>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is Map) {
      final normalizedMap = <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _canonicalize(entry.value),
      };
      return _canonicalize(normalizedMap);
    }
    if (value is List) {
      return value.map(_canonicalize).toList(growable: false);
    }
    return value;
  }
}
