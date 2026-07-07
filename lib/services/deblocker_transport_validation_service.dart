import 'dart:async';
import 'dart:io';

import '../models/deblocker_runtime_bundle.dart';

enum DeblockerTransportValidationSeverity {
  error,
  warning,
}

class DeblockerTransportValidationIssue {
  final DeblockerTransportValidationSeverity severity;
  final String code;
  final String message;

  const DeblockerTransportValidationIssue({
    required this.severity,
    required this.code,
    required this.message,
  });
}

class DeblockerTransportValidationResult {
  final List<DeblockerTransportValidationIssue> issues;
  final bool edgeReachable;

  const DeblockerTransportValidationResult({
    required this.issues,
    required this.edgeReachable,
  });

  bool get isValid => issues.every(
        (issue) => issue.severity != DeblockerTransportValidationSeverity.error,
      );
}

class DeblockerTransportValidationService {
  static const Set<String> _supportedTransports = <String>{
    'ws',
    'httpupgrade',
    'grpc',
    'h2',
  };
  static const Set<String> _supportedOutboundTypes = <String>{
    'trojan',
    'vless',
  };

  const DeblockerTransportValidationService();

  DeblockerTransportValidationResult validateConfig(
    DeblockerIngressConfig config,
  ) {
    final issues = <DeblockerTransportValidationIssue>[];
    final outboundType = config.outboundType.trim().toLowerCase();
    final transport = config.transport.trim().toLowerCase();

    if (!_supportedOutboundTypes.contains(outboundType)) {
      issues.add(
        DeblockerTransportValidationIssue(
          severity: DeblockerTransportValidationSeverity.error,
          code: 'unsupported_outbound_type',
          message: 'Ingress outbound type $outboundType is not supported',
        ),
      );
    }

    if (!_supportedTransports.contains(transport)) {
      issues.add(
        DeblockerTransportValidationIssue(
          severity: DeblockerTransportValidationSeverity.error,
          code: 'unsupported_transport',
          message: 'Ingress transport $transport is not supported',
        ),
      );
    }

    if (config.edgeHost.trim().isEmpty) {
      issues.add(
        const DeblockerTransportValidationIssue(
          severity: DeblockerTransportValidationSeverity.error,
          code: 'missing_edge_host',
          message: 'Ingress edge host is empty',
        ),
      );
    }

    if (config.edgePort < 1 || config.edgePort > 65535) {
      issues.add(
        DeblockerTransportValidationIssue(
          severity: DeblockerTransportValidationSeverity.error,
          code: 'invalid_edge_port',
          message: 'Ingress edge port ${config.edgePort} is out of range',
        ),
      );
    }

    if (transport != 'grpc' && config.path.trim().isEmpty) {
      issues.add(
        DeblockerTransportValidationIssue(
          severity: DeblockerTransportValidationSeverity.warning,
          code: 'missing_transport_path',
          message: 'Ingress path is empty and will default to /',
        ),
      );
    }

    if (transport == 'grpc' && config.grpcServiceName.trim().isEmpty) {
      issues.add(
        const DeblockerTransportValidationIssue(
          severity: DeblockerTransportValidationSeverity.error,
          code: 'missing_grpc_service',
          message: 'gRPC ingress requires grpcServiceName',
        ),
      );
    }

    if (outboundType == 'trojan' && config.password.trim().isEmpty) {
      issues.add(
        const DeblockerTransportValidationIssue(
          severity: DeblockerTransportValidationSeverity.error,
          code: 'missing_trojan_password',
          message: 'Trojan ingress requires password',
        ),
      );
    }

    if (outboundType == 'vless' && config.uuid.trim().isEmpty) {
      issues.add(
        const DeblockerTransportValidationIssue(
          severity: DeblockerTransportValidationSeverity.error,
          code: 'missing_vless_uuid',
          message: 'VLESS ingress requires uuid',
        ),
      );
    }

    if (config.hostHeader.trim().isEmpty) {
      issues.add(
        const DeblockerTransportValidationIssue(
          severity: DeblockerTransportValidationSeverity.warning,
          code: 'missing_host_header',
          message: 'Host header is empty and will fall back to edgeHost',
        ),
      );
    }

    if (config.sni.trim().isEmpty) {
      issues.add(
        const DeblockerTransportValidationIssue(
          severity: DeblockerTransportValidationSeverity.warning,
          code: 'missing_sni',
          message: 'SNI is empty and will fall back to edgeHost',
        ),
      );
    }

    return DeblockerTransportValidationResult(
      issues: issues,
      edgeReachable: false,
    );
  }

  Future<bool> probeEdgeReachability(
    DeblockerIngressConfig config, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        config.edgeHost.trim(),
        config.edgePort,
        timeout: timeout,
      );
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    } finally {
      await socket?.close();
    }
  }
}
