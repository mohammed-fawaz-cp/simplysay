import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import '../../../../core/config/app_config.dart';
import '../../../../database/db_helper.dart';
import '../../../../services/mqtt_service.dart';

class HostCallState {
  final String code; // e.g. "K7P-9W2-M4X"
  final int secondsRemaining; // 600 max (10 minutes)
  final bool isConnected;
  final bool isExpired;
  final String connectedPeerName;
  final String? connectedPeerId;
  final String? myCit;

  const HostCallState({
    required this.code,
    required this.secondsRemaining,
    this.isConnected = false,
    this.isExpired = false,
    this.connectedPeerName = 'Peer User',
    this.connectedPeerId,
    this.myCit,
  });

  HostCallState copyWith({
    String? code,
    int? secondsRemaining,
    bool? isConnected,
    bool? isExpired,
    String? connectedPeerName,
    String? connectedPeerId,
    String? myCit,
  }) {
    return HostCallState(
      code: code ?? this.code,
      secondsRemaining: secondsRemaining ?? this.secondsRemaining,
      isConnected: isConnected ?? this.isConnected,
      isExpired: isExpired ?? this.isExpired,
      connectedPeerName: connectedPeerName ?? this.connectedPeerName,
      connectedPeerId: connectedPeerId ?? this.connectedPeerId,
      myCit: myCit ?? this.myCit,
    );
  }
}

class HostCallNotifier extends StateNotifier<HostCallState> {
  Timer? _timer;
  Timer? _statusPollTimer;
  StreamSubscription? _mqttSubscription;
  String? _subscribedTopic;

  HostCallNotifier()
      : super(HostCallState(
          code: _generateCode(),
          secondsRemaining: 600, // 10 minutes
        )) {
    _startSession();
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
    _startStatusPolling();
    _registerOnBackendAndMqtt();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.secondsRemaining <= 1) {
        timer.cancel();
        _statusPollTimer?.cancel();
        state = state.copyWith(secondsRemaining: 0, isExpired: true);
      } else {
        state = state.copyWith(secondsRemaining: state.secondsRemaining - 1);
      }
    });
  }

  void _startStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (state.isConnected || state.isExpired) {
        _statusPollTimer?.cancel();
        return;
      }
      final cleanCode = state.code.replaceAll('-', '').trim().toUpperCase();
      final statusUrls = [
        'http://127.0.0.1:8000/api/v1/instant-call/status/$cleanCode',
        'http://localhost:8000/api/v1/instant-call/status/$cleanCode',
        '${AppConfig.apiBaseUrl}/instant-call/status/$cleanCode',
      ];
      for (final url in statusUrls) {
        try {
          final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 2));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            if (data['status'] == 'joined') {
              _statusPollTimer?.cancel();
              _timer?.cancel();
              final peerName = data['joiner_name'] ?? 'Peer User';
              final peerId = data['joiner_id'] ?? 'joiner_peer_${Random().nextInt(9999)}';
              developer.log('🎉 [InstantCallHost] Joiner connection detected! Peer: $peerName ($peerId)', name: 'HostCallNotifier');
              await DatabaseHelper.instance.savePeer(peerId: peerId, name: peerName);
              if (mounted) {
                state = state.copyWith(
                  isConnected: true,
                  connectedPeerName: peerName,
                  connectedPeerId: peerId,
                );
              }
              break;
            }
          }
        } catch (_) {}
      }
    });
  }

  Future<void> _registerOnBackendAndMqtt() async {
    final identity = await DatabaseHelper.instance.getClientIdentity();
    final myDisplayName = (identity?['display_name'] as String?)?.trim();
    final hostName = (myDisplayName != null && myDisplayName.isNotEmpty) ? myDisplayName : 'Host User';
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

    final cleanCode = state.code.replaceAll('-', '').trim().toUpperCase();
    _subscribedTopic = 'simplysay/instant_call/$cleanCode';
    final roomSignalingTopic = 'simplysay/call_session/$cleanCode/signaling';

    if (mounted) {
      state = state.copyWith(myCit: hostId);
    }

    // 1. One-shot registration on FastAPI backend (Creates initial session entry)
    final endpoints = [
      'http://127.0.0.1:8000/api/v1/instant-call/create',
      'http://localhost:8000/api/v1/instant-call/create',
      '${AppConfig.apiBaseUrl}/instant-call/create',
    ];

    for (final url in endpoints) {
      try {
        final res = await http
            .post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'code': cleanCode,
                'host_id': hostId,
                'host_name': hostName,
              }),
            )
            .timeout(const Duration(seconds: 2));
        if (res.statusCode == 200) {
          developer.log('✅ [InstantCallHost] Registered session $cleanCode on backend ($url) as hostName=$hostName', name: 'HostCallNotifier');
          break;
        }
      } catch (e) {
        // Fallback to next endpoint
      }
    }

    // 2. Subscribe to MQTT topics for zero-polling real-time push events & early WebRTC signaling
    MQTTService.instance.subscribe(_subscribedTopic!);
    MQTTService.instance.subscribe(roomSignalingTopic);
    developer.log('⚡ [InstantCallHost] Subscribed to MQTT topics: $_subscribedTopic & $roomSignalingTopic', name: 'HostCallNotifier');

    _mqttSubscription?.cancel();
    _mqttSubscription = MQTTService.instance.messageStream.listen((msg) async {
      if (msg.topic == _subscribedTopic) {
        try {
          final recMsg = msg.payload as MqttPublishMessage;
          final payloadStr =
              MqttPublishPayload.bytesToStringAsString(recMsg.payload.message);
          final data = jsonDecode(payloadStr);
          if (data['type'] == 'JOINED') {
            final peerName = data['peer_name'] ?? 'Peer User';
            final peerId = data['peer_id'] ?? 'joiner_peer_${Random().nextInt(9999)}';
            developer.log('🎉 [InstantCallHost] Real-time JOINED event received via MQTT! Peer: $peerName ($peerId)', name: 'HostCallNotifier');
            _timer?.cancel();
            _statusPollTimer?.cancel();

            // Save connected peer into local storage & contacts
            await DatabaseHelper.instance.savePeer(peerId: peerId, name: peerName);

            if (mounted) {
              state = state.copyWith(
                isConnected: true,
                connectedPeerName: peerName,
                connectedPeerId: peerId,
                myCit: hostId,
              );
            }
          }
        } catch (e) {
          developer.log('⚠️ [InstantCallHost] Error parsing MQTT message: $e', name: 'HostCallNotifier');
        }
      }
    });
  }

  void refreshCode() {
    _statusPollTimer?.cancel();
    state = HostCallState(
      code: _generateCode(),
      secondsRemaining: 600,
    );
    _startSession();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _statusPollTimer?.cancel();
    _mqttSubscription?.cancel();
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
  final String? errorMessage;
  final String hostName;
  final String? hostId;
  final String? myCit;
  final String? callCode;

  const JoinCallState({
    this.code = '',
    this.isConnecting = false,
    this.errorMessage,
    this.hostName = 'Host User',
    this.hostId,
    this.myCit,
    this.callCode,
  });

  JoinCallState copyWith({
    String? code,
    bool? isConnecting,
    String? errorMessage,
    String? hostName,
    String? hostId,
    String? myCit,
    String? callCode,
  }) {
    return JoinCallState(
      code: code ?? this.code,
      isConnecting: isConnecting ?? this.isConnecting,
      errorMessage: errorMessage,
      hostName: hostName ?? this.hostName,
      hostId: hostId ?? this.hostId,
      myCit: myCit ?? this.myCit,
      callCode: callCode ?? this.callCode,
    );
  }
}

class JoinCallNotifier extends StateNotifier<JoinCallState> {
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

    state = state.copyWith(isConnecting: true, errorMessage: null);

    final identity = await DatabaseHelper.instance.getClientIdentity();
    final myDisplayName = (identity?['display_name'] as String?)?.trim();
    final joinerName = (myDisplayName != null && myDisplayName.isNotEmpty) ? myDisplayName : 'Joiner User';
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

    // 1. Verify code with FastAPI backend
    final endpoints = [
      'http://127.0.0.1:8000/api/v1/instant-call/join',
      'http://localhost:8000/api/v1/instant-call/join',
      '${AppConfig.apiBaseUrl}/instant-call/join',
    ];

    String hostName = 'Host User';
    String hostId = 'host_user_${Random().nextInt(9999)}';

    for (final url in endpoints) {
      try {
        final res = await http
            .post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'code': cleanCode,
                'joiner_id': joinerId,
                'joiner_name': joinerName,
              }),
            )
            .timeout(const Duration(seconds: 2));

        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          hostName = body['host_name'] ?? 'Host User';
          hostId = body['host_id'] ?? hostId;
          developer.log('✅ [InstantCallJoin] Verified & joined code $cleanCode on backend ($url) as $joinerName', name: 'JoinCallNotifier');
          break;
        } else if (res.statusCode == 404 || res.statusCode == 410) {
          state = state.copyWith(
            isConnecting: false,
            errorMessage: 'Invalid or expired Instant Call code.',
          );
          return false;
        }
      } catch (e) {
        // Try fallback endpoint
      }
    }

    // Save Host to local DB & Contacts & Recent Calls
    await DatabaseHelper.instance.savePeer(peerId: hostId, name: hostName);

    // Pre-subscribe to the room signaling topic
    final roomSignalingTopic = 'simplysay/call_session/$cleanCode/signaling';
    MQTTService.instance.subscribe(roomSignalingTopic);

    // Publish MQTT event as secondary signal
    final topic = 'simplysay/instant_call/$cleanCode';
    final payload = jsonEncode({
      'type': 'JOINED',
      'peer_id': joinerId,
      'peer_name': joinerName,
      'host_name': hostName,
    });

    MQTTService.instance.publishMessage(topic, payload);
    developer.log('⚡ [InstantCallJoin] Published JOINED message to MQTT topic $topic and subscribed to $roomSignalingTopic', name: 'JoinCallNotifier');

    state = state.copyWith(
      isConnecting: false,
      hostName: hostName,
      hostId: hostId,
      myCit: joinerId,
      callCode: cleanCode,
    );
    return true;
  }
}

final joinCallProvider =
    StateNotifierProvider.autoDispose<JoinCallNotifier, JoinCallState>((ref) {
  return JoinCallNotifier();
});
