import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart';
import '../../../../core/native/native_call_bridge.dart';
import '../../../../database/db_helper.dart';
import '../../../../services/call_signaling_service.dart';
import '../../../../services/mqtt_service.dart';

class HostCallState {
  final String code; // e.g. "K7P-9W2-M4X"
  final int secondsRemaining; // 600 max (10 minutes)
  final bool isConnected;
  final bool isExpired;
  final bool hasIncomingRequest;
  final String? incomingPeerName;
  final String? incomingPeerId;
  final String connectedPeerName;
  final String? connectedPeerId;
  final String? myCit;

  const HostCallState({
    required this.code,
    required this.secondsRemaining,
    this.isConnected = false,
    this.isExpired = false,
    this.hasIncomingRequest = false,
    this.incomingPeerName,
    this.incomingPeerId,
    this.connectedPeerName = 'Peer User',
    this.connectedPeerId,
    this.myCit,
  });

  HostCallState copyWith({
    String? code,
    int? secondsRemaining,
    bool? isConnected,
    bool? isExpired,
    bool? hasIncomingRequest,
    String? incomingPeerName,
    String? incomingPeerId,
    String? connectedPeerName,
    String? connectedPeerId,
    String? myCit,
  }) {
    return HostCallState(
      code: code ?? this.code,
      secondsRemaining: secondsRemaining ?? this.secondsRemaining,
      isConnected: isConnected ?? this.isConnected,
      isExpired: isExpired ?? this.isExpired,
      hasIncomingRequest: hasIncomingRequest ?? this.hasIncomingRequest,
      incomingPeerName: incomingPeerName ?? this.incomingPeerName,
      incomingPeerId: incomingPeerId ?? this.incomingPeerId,
      connectedPeerName: connectedPeerName ?? this.connectedPeerName,
      connectedPeerId: connectedPeerId ?? this.connectedPeerId,
      myCit: myCit ?? this.myCit,
    );
  }
}

class HostCallNotifier extends StateNotifier<HostCallState> {
  Timer? _timer;
  StreamSubscription? _mqttSubscription;
  StreamSubscription? _nativeCallSubscription;
  late final String _subscribedTopic;
  late final String _cleanCode;

  HostCallNotifier()
      : super(HostCallState(
          code: _generateCode(),
          secondsRemaining: 600, // 10 minutes
        )) {
    _cleanCode = state.code.replaceAll('-', '').trim().toUpperCase();
    _subscribedTopic = 'simplysay/instant_call/$_cleanCode';
    _startSession();
    _listenToNativeCallActions();
  }

  void _listenToNativeCallActions() {
    _nativeCallSubscription = NativeCallBridge.instance.onCallActionStream.listen((event) {
      final action = event['event'] as String?;
      developer.log('⚡ [HostCallNotifier] Native call action received: $action', name: 'HostCallNotifier');
      if (action == 'call_accepted') {
        if (state.hasIncomingRequest) {
          acceptIncomingCall();
        }
      } else if (action == 'call_declined') {
        if (state.hasIncomingRequest) {
          declineIncomingCall();
        }
      }
    });
  }

  static String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Avoid ambiguous 0/O, 1/I
    final rnd = Random();
    String s1 = List.generate(3, (_) => chars[rnd.nextInt(chars.length)]).join();
    String s2 = List.generate(3, (_) => chars[rnd.nextInt(chars.length)]).join();
    String s3 = List.generate(3, (_) => chars[rnd.nextInt(chars.length)]).join();
    return '$s1-$s2-$s3';
  }

  void _startSession() {
    _startTimer();
    _registerOnMqtt();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.secondsRemaining <= 1) {
        timer.cancel();
        state = state.copyWith(secondsRemaining: 0, isExpired: true);
      } else {
        state = state.copyWith(secondsRemaining: state.secondsRemaining - 1);
      }
    });
  }

  Future<void> _registerOnMqtt() async {
    final identity = await DatabaseHelper.instance.getClientIdentity();
    String hostName = (identity?['display_name'] as String?)?.trim() ?? '';
    if (hostName.isEmpty) {
      final phone = (identity?['phone_number'] as String?)?.trim() ?? '';
      if (phone.isNotEmpty && phone != '+1000000000') {
        hostName = 'User ($phone)';
      } else {
        final deviceId = identity?['device_id'] as String? ?? '';
        hostName = deviceId.isNotEmpty ? 'User ${deviceId.substring(0, min(5, deviceId.length))}' : 'Host';
      }
    }
    String hostId = identity?['cit'] as String? ?? '';

    if (hostId.isEmpty) {
      hostId = 'host_user_${Random().nextInt(999999)}';
      await DatabaseHelper.instance.saveClientIdentity(
        cit: hostId,
        csit: 'csit_$hostId',
        deviceId: 'device_$hostId',
        phoneNumber: '+1000000000',
        displayName: hostName,
      );
    }

    final roomSignalingTopic = 'simplysay/call_session/$_cleanCode/signaling';

    if (mounted) {
      state = state.copyWith(myCit: hostId);
    }

    // Subscribe immediately to decentralized MQTT session topics
    MQTTService.instance.subscribe(_subscribedTopic);
    MQTTService.instance.subscribe(roomSignalingTopic);
    developer.log('⚡ [InstantCallHost] Subscribed to decentralized topics: $_subscribedTopic & $roomSignalingTopic', name: 'HostCallNotifier');

    _mqttSubscription?.cancel();
    _mqttSubscription = MQTTService.instance.messageStream.listen((msg) async {
      if (msg.topic == _subscribedTopic) {
        try {
          final recMsg = msg.payload as MqttPublishMessage;
          final payloadStr =
              MqttPublishPayload.bytesToStringAsString(recMsg.payload.message);
          final data = jsonDecode(payloadStr);

          if (data['type'] == 'JOIN_REQUEST') {
            final peerName = (data['peer_name'] as String?)?.trim() ?? 'Peer User';
            final peerId = (data['peer_id'] ?? data['peer_cit'] as String?)?.trim() ?? 'joiner_peer_${Random().nextInt(9999)}';
            developer.log('🔔 [InstantCallHost] Incoming Join Request via MQTT: $peerName ($peerId). Triggering ringing notification...', name: 'HostCallNotifier');
            _timer?.cancel();

            await DatabaseHelper.instance.savePeer(peerId: peerId, name: peerName);

            // Trigger Android native CallStyle incoming notification with ringtone
            NativeCallBridge.instance.showIncomingCall(
              callerName: peerName,
              callerCit: peerId,
              callCode: _cleanCode,
              callType: 'instant_call',
            );

            if (mounted) {
              state = state.copyWith(
                hasIncomingRequest: true,
                incomingPeerName: peerName,
                incomingPeerId: peerId,
                connectedPeerName: peerName,
                connectedPeerId: peerId,
                myCit: hostId,
              );
            }
          } else if (data['type'] == 'CALL_CANCELLED') {
            developer.log('⚠️ [InstantCallHost] Joiner cancelled call request.', name: 'HostCallNotifier');
            NativeCallBridge.instance.dismissIncomingCall();
            CallSignalingService.instance.notifyCallCancelled(callCode: _cleanCode);
            if (mounted) {
              state = state.copyWith(
                hasIncomingRequest: false,
                incomingPeerName: null,
                incomingPeerId: null,
              );
              _startTimer();
            }
          }
        } catch (e) {
          developer.log('⚠️ [InstantCallHost] Error parsing MQTT message: $e', name: 'HostCallNotifier');
        }
      }
    });
  }

  /// Host accepts incoming instant call request
  Future<void> acceptIncomingCall() async {
    await NativeCallBridge.instance.dismissIncomingCall();
    final identity = await DatabaseHelper.instance.getClientIdentity();
    final myCit = identity?['cit'] as String? ?? state.myCit ?? 'host_user';
    final myName = identity?['display_name'] as String? ?? 'Host';

    // Broadcast ACCEPTED signal over MQTT so Joiner connects
    MQTTService.instance.publishMessage(
      _subscribedTopic,
      jsonEncode({
        'type': 'CALL_ACCEPTED',
        'host_id': myCit,
        'host_name': myName,
        'call_code': _cleanCode,
      }),
      qos: MqttQos.atLeastOnce,
    );

    if (mounted) {
      state = state.copyWith(
        hasIncomingRequest: false,
        isConnected: true,
      );
    }
  }

  /// Host declines incoming instant call request
  Future<void> declineIncomingCall() async {
    await NativeCallBridge.instance.dismissIncomingCall();

    // Broadcast DECLINED signal over MQTT
    MQTTService.instance.publishMessage(
      _subscribedTopic,
      jsonEncode({
        'type': 'CALL_DECLINED',
        'call_code': _cleanCode,
      }),
      qos: MqttQos.atLeastOnce,
    );

    if (mounted) {
      state = state.copyWith(
        hasIncomingRequest: false,
        incomingPeerName: null,
        incomingPeerId: null,
      );
      _startTimer();
    }
  }

  void refreshCode() {
    NativeCallBridge.instance.dismissIncomingCall();
    final newCode = _generateCode();
    _cleanCode = newCode.replaceAll('-', '').trim().toUpperCase();
    _subscribedTopic = 'simplysay/instant_call/$_cleanCode';
    state = HostCallState(
      code: newCode,
      secondsRemaining: 600,
    );
    _startSession();
  }

  @override
  void dispose() {
    NativeCallBridge.instance.dismissIncomingCall();
    _timer?.cancel();
    _mqttSubscription?.cancel();
    _nativeCallSubscription?.cancel();
    super.dispose();
  }
}

final hostCallProvider =
    StateNotifierProvider.autoDispose<HostCallNotifier, HostCallState>((ref) {
  return HostCallNotifier();
});

class JoinCallState {
  final String code;
  final bool isConnecting;
  final bool isWaitingForHost;
  final bool isAccepted;
  final String? errorMessage;
  final String hostName;
  final String? hostId;
  final String? myCit;
  final String? callCode;

  const JoinCallState({
    this.code = '',
    this.isConnecting = false,
    this.isWaitingForHost = false,
    this.isAccepted = false,
    this.errorMessage,
    this.hostName = 'Host User',
    this.hostId,
    this.myCit,
    this.callCode,
  });

  JoinCallState copyWith({
    String? code,
    bool? isConnecting,
    bool? isWaitingForHost,
    bool? isAccepted,
    String? errorMessage,
    String? hostName,
    String? hostId,
    String? myCit,
    String? callCode,
  }) {
    return JoinCallState(
      code: code ?? this.code,
      isConnecting: isConnecting ?? this.isConnecting,
      isWaitingForHost: isWaitingForHost ?? this.isWaitingForHost,
      isAccepted: isAccepted ?? this.isAccepted,
      errorMessage: errorMessage,
      hostName: hostName ?? this.hostName,
      hostId: hostId ?? this.hostId,
      myCit: myCit ?? this.myCit,
      callCode: callCode ?? this.callCode,
    );
  }
}

class JoinCallNotifier extends StateNotifier<JoinCallState> {
  StreamSubscription? _mqttSubscription;

  JoinCallNotifier() : super(const JoinCallState());

  void setCode(String code) {
    state = state.copyWith(code: code, errorMessage: null);
  }

  Future<bool> joinCall() async {
    final cleanCode = state.code.replaceAll('-', '').trim().toUpperCase();
    if (cleanCode.length != 9) {
      state = state.copyWith(errorMessage: 'Please enter a complete 9-character code.');
      return false;
    }

    state = state.copyWith(isConnecting: true, isWaitingForHost: false, errorMessage: null);

    final identity = await DatabaseHelper.instance.getClientIdentity();
    String joinerName = (identity?['display_name'] as String?)?.trim() ?? '';
    if (joinerName.isEmpty) {
      final phone = (identity?['phone_number'] as String?)?.trim() ?? '';
      if (phone.isNotEmpty && phone != '+1000000000') {
        joinerName = 'User ($phone)';
      } else {
        final deviceId = identity?['device_id'] as String? ?? '';
        joinerName = deviceId.isNotEmpty ? 'User ${deviceId.substring(0, min(5, deviceId.length))}' : 'Joiner';
      }
    }
    String joinerId = identity?['cit'] as String? ?? '';

    if (joinerId.isEmpty) {
      joinerId = 'joiner_user_${Random().nextInt(999999)}';
      await DatabaseHelper.instance.saveClientIdentity(
        cit: joinerId,
        csit: 'csit_$joinerId',
        deviceId: 'device_$joinerId',
        phoneNumber: '+1000000000',
        displayName: joinerName,
      );
    }

    // 1. Subscribe to decentralized MQTT topics for this instant call session
    final topic = 'simplysay/instant_call/$cleanCode';
    final roomSignalingTopic = 'simplysay/call_session/$cleanCode/signaling';
    MQTTService.instance.subscribe(topic);
    MQTTService.instance.subscribe(roomSignalingTopic);

    _mqttSubscription?.cancel();
    _mqttSubscription = MQTTService.instance.messageStream.listen((msg) async {
      if (msg.topic == topic) {
        try {
          final recMsg = msg.payload as MqttPublishMessage;
          final payloadStr =
              MqttPublishPayload.bytesToStringAsString(recMsg.payload.message);
          final data = jsonDecode(payloadStr);

          if (data['type'] == 'CALL_ACCEPTED') {
            developer.log('🎉 [InstantCallJoin] Host accepted call request! Connecting to call screen...', name: 'JoinCallNotifier');
            final confirmedHostName = (data['host_name'] as String?)?.trim() ?? state.hostName;
            final confirmedHostId = (data['host_id'] as String?)?.trim() ?? state.hostId ?? '';

            if (confirmedHostId.isNotEmpty) {
              await DatabaseHelper.instance.savePeer(peerId: confirmedHostId, name: confirmedHostName);
            }

            if (mounted) {
              state = state.copyWith(
                isConnecting: false,
                isWaitingForHost: false,
                isAccepted: true,
                hostName: confirmedHostName,
                hostId: confirmedHostId,
                callCode: cleanCode,
              );
            }
          } else if (data['type'] == 'CALL_DECLINED') {
            developer.log('⚠️ [InstantCallJoin] Host declined call request.', name: 'JoinCallNotifier');
            if (mounted) {
              state = state.copyWith(
                isConnecting: false,
                isWaitingForHost: false,
                errorMessage: 'Host declined the call request.',
              );
            }
          }
        } catch (e) {
          developer.log('⚠️ [InstantCallJoin] Error parsing response: $e', name: 'JoinCallNotifier');
        }
      }
    });

    // 2. Publish JOIN_REQUEST directly to host over MQTT
    final payload = jsonEncode({
      'type': 'JOIN_REQUEST',
      'peer_id': joinerId,
      'peer_cit': joinerId,
      'peer_name': joinerName,
      'call_code': cleanCode,
    });
    MQTTService.instance.publishMessage(topic, payload, qos: MqttQos.atLeastOnce);
    developer.log('⚡ [InstantCallJoin] Published JOIN_REQUEST to $topic. Waiting for host to accept...', name: 'JoinCallNotifier');

    state = state.copyWith(
      isConnecting: false,
      isWaitingForHost: true,
      myCit: joinerId,
      callCode: cleanCode,
    );
    return true;
  }

  void cancelCall() {
    final cleanCode = state.code.replaceAll('-', '').trim().toUpperCase();
    final topic = 'simplysay/instant_call/$cleanCode';
    try {
      MQTTService.instance.publishMessage(
        topic,
        jsonEncode({'type': 'CALL_CANCELLED', 'call_code': cleanCode}),
        qos: MqttQos.atLeastOnce,
      );
    } catch (_) {}
    state = state.copyWith(
      isConnecting: false,
      isWaitingForHost: false,
      isAccepted: false,
    );
  }

  @override
  void dispose() {
    _mqttSubscription?.cancel();
    super.dispose();
  }
}

final joinCallProvider =
    StateNotifierProvider.autoDispose<JoinCallNotifier, JoinCallState>((ref) {
  return JoinCallNotifier();
});
