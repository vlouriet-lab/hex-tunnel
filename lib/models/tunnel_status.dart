import 'routing_mode.dart';

enum TunnelState {
  stopped,
  connecting,
  connected,
  error,
}

extension TunnelStateExt on TunnelState {
  String get label {
    switch (this) {
      case TunnelState.stopped:
        return 'Отключено';
      case TunnelState.connecting:
        return 'Подключение…';
      case TunnelState.connected:
        return 'Подключено';
      case TunnelState.error:
        return 'Ошибка';
    }
  }

  bool get isActive =>
      this == TunnelState.connected || this == TunnelState.connecting;
}

class TunnelStatus {
  final TunnelState state;
  final String statusText;
  final String activeProtocol;
  final String activeServer;
  final String activeProfileName;
  final int latencyMs; // -1 = не измерена
  final RoutingMode routingMode;
  final String errorMessage;
  final String errorCode;
  final String stage;
  final int networkEventId;
  final String networkInterface;
  final String networkTransport;
  final String networkOperator;

  const TunnelStatus({
    this.state = TunnelState.stopped,
    this.statusText = '',
    this.activeProtocol = '',
    this.activeServer = '',
    this.activeProfileName = '',
    this.latencyMs = -1,
    this.routingMode = RoutingMode.bypassLan,
    this.errorMessage = '',
    this.errorCode = '',
    this.stage = '',
    this.networkEventId = 0,
    this.networkInterface = '',
    this.networkTransport = '',
    this.networkOperator = '',
  });

  TunnelStatus copyWith({
    TunnelState? state,
    String? statusText,
    String? activeProtocol,
    String? activeServer,
    String? activeProfileName,
    int? latencyMs,
    RoutingMode? routingMode,
    String? errorMessage,
    String? errorCode,
    String? stage,
    int? networkEventId,
    String? networkInterface,
    String? networkTransport,
    String? networkOperator,
  }) {
    return TunnelStatus(
      state: state ?? this.state,
      statusText: statusText ?? this.statusText,
      activeProtocol: activeProtocol ?? this.activeProtocol,
      activeServer: activeServer ?? this.activeServer,
      activeProfileName: activeProfileName ?? this.activeProfileName,
      latencyMs: latencyMs ?? this.latencyMs,
      routingMode: routingMode ?? this.routingMode,
      errorMessage: errorMessage ?? this.errorMessage,
      errorCode: errorCode ?? this.errorCode,
      stage: stage ?? this.stage,
      networkEventId: networkEventId ?? this.networkEventId,
      networkInterface: networkInterface ?? this.networkInterface,
      networkTransport: networkTransport ?? this.networkTransport,
      networkOperator: networkOperator ?? this.networkOperator,
    );
  }

  factory TunnelStatus.fromStatusString(
    String status, {
    String error = '',
    RoutingMode routingMode = RoutingMode.bypassLan,
    String activeServer = '',
    String activeProtocol = '',
    int latencyMs = -1,
    String errorCode = '',
    String stage = '',
    int networkEventId = 0,
    String networkInterface = '',
    String networkTransport = '',
    String networkOperator = '',
  }) {
    TunnelState state;
    switch (status) {
      case 'connected':
        state = TunnelState.connected;
        break;
      case 'connecting':
        state = TunnelState.connecting;
        break;
      case 'error':
        state = TunnelState.error;
        break;
      default:
        state = TunnelState.stopped;
    }
    return TunnelStatus(
      state: state,
      statusText: state.label,
      activeServer: activeServer,
      activeProtocol: activeProtocol,
      latencyMs: latencyMs,
      errorMessage: error,
      errorCode: errorCode,
      stage: stage,
      routingMode: routingMode,
      networkEventId: networkEventId,
      networkInterface: networkInterface,
      networkTransport: networkTransport,
      networkOperator: networkOperator,
    );
  }
}
