import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import '../core/native/native_call_bridge.dart';
import '../core/routes/app_routes.dart';
import '../database/db_helper.dart';
import 'fcm_service.dart';
import 'mqtt_service.dart';

class CallSignalingService {
  CallSignalingService._();
  static final CallSignalingService instance = CallSignalingService._();

  StreamSubscription? _mqttSubscription;
  String? _currentListeningCit;
  bool _isListening = false;
  bool isCallActive = false;
  String? currentDialingPeerCit;
  DateTime? _lastCallTriggerTime;

  final StreamController<Map<String, dynamic>> _incomingCallStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onIncomingCallStream =>
      _incomingCallStreamController.stream;

  /// External trigger to broadcast an incoming call alert (e.g. from Instant Call Host)
  void notifyIncomingCall({
    required String callerName,
    required String callerCit,
    required String callCode,
    String callType = 'video',
  }) {
    developer.log('🔔 [CallSignalingService.notifyIncomingCall] Dispatching incoming call ($callerName, code=$callCode, type=$callType)...', name: 'CallSignalingService');
    _incomingCallStreamController.add({
      'type': 'incoming_call',
      'caller_name': callerName,
      'caller_cit': callerCit,
      'call_code': callCode,
      'call_type': callType,
    });
  }

  /// External trigger to dismiss active incoming call alert
  void notifyCallCancelled({
    required String callCode,
  }) {
    developer.log('🛑 [CallSignalingService.notifyCallCancelled] Cancelling call code=$callCode...', name: 'CallSignalingService');
    _incomingCallStreamController.add({
      'type': 'call_cancelled',
      'call_code': callCode,
    });
  }

  /// Initializes global MQTT subscription on the user's personal channel
  /// to receive incoming calls from Contacts and Recents while the app is active.
  Future<void> initGlobalIncomingCallListener() async {
    final identity = await DatabaseHelper.instance.getClientIdentity();
    final myCit = identity?['cit'] as String?;
    if (myCit == null || myCit.isEmpty) {
      developer.log('⚠️ [CallSignalingService] No client CIT found. Deferring global call listener.', name: 'CallSignalingService');
      return;
    }

    if (_isListening && _currentListeningCit == myCit && MQTTService.instance.isConnected) {
      return;
    }

    _currentListeningCit = myCit;
    developer.log('⚡ [CallSignalingService] Initializing global incoming call listener for CIT=$myCit...', name: 'CallSignalingService');

    // 1. Connect MQTT if disconnected
    if (!MQTTService.instance.isConnected) {
      await MQTTService.instance.initialize(cit: myCit);
    }

    // 2. Subscribe to personal direct incoming call topics
    final userCallTopic = 'simplysay/user/$myCit/incoming_call';
    final userInviteTopic = 'simplysay/call/invite/$myCit';
    MQTTService.instance.subscribe(userCallTopic);
    MQTTService.instance.subscribe(userInviteTopic);
    developer.log('⚡ [CallSignalingService] Subscribed to $userCallTopic and $userInviteTopic', name: 'CallSignalingService');

    _mqttSubscription?.cancel();
    _mqttSubscription = MQTTService.instance.messageStream.listen((msg) async {
      final topic = msg.topic;
      if (topic == userCallTopic || topic == userInviteTopic) {
        try {
          final recMsg = msg.payload as MqttPublishMessage;
          final payloadStr = MqttPublishPayload.bytesToStringAsString(recMsg.payload.message);
          final data = jsonDecode(payloadStr) as Map<String, dynamic>;

          developer.log('🔔 [CallSignalingService] Received direct call signaling on $topic: $data', name: 'CallSignalingService');

          final type = data['type'] as String?;
          if (type == 'incoming_call') {
            final callerName = (data['caller_name'] as String?)?.trim() ?? 'Someone';
            final callerCit = (data['caller_cit'] as String?)?.trim() ?? '';
            final callCode = (data['call_code'] as String?)?.trim() ?? '';
            final callType = (data['call_type'] as String?)?.trim() ?? 'video';

            if (callerCit.isEmpty || callCode.isEmpty) return;

            // 1. Check Busy State
            if (isCallActive) {
              developer.log('⚠️ [CallSignalingService] Device is busy in active call. Replying busy to $callerCit...', name: 'CallSignalingService');
              MQTTService.instance.publishMessage(
                'simplysay/user/$callerCit/incoming_call',
                jsonEncode({
                  'type': 'busy',
                  'call_code': callCode,
                  'from_cit': myCit,
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                }),
                qos: MqttQos.atLeastOnce,
              );
              await DatabaseHelper.instance.insertCallRecord(
                peerCit: callerCit,
                peerName: callerName,
                direction: 'incoming',
                status: 'MISSED',
              );
              return;
            }

            // 2. Glare / Collision Detection (both peers calling each other simultaneously)
            if (currentDialingPeerCit != null && currentDialingPeerCit == callerCit) {
              developer.log('⚔️ [CallSignalingService] Call collision detected with $callerCit.', name: 'CallSignalingService');
              if (myCit.compareTo(callerCit) < 0) {
                developer.log('⚔️ [CallSignalingService] Yielding to peer with higher CIT ($callerCit).', name: 'CallSignalingService');
                _incomingCallStreamController.add(data);
              } else {
                developer.log('⚔️ [CallSignalingService] Maintaining caller priority over $callerCit.', name: 'CallSignalingService');
                return;
              }
            }

            // Save peer in local SQLite
            await DatabaseHelper.instance.savePeer(peerId: callerCit, name: callerName);

            // Ring Android native CallStyle notification & overlay (shows across entire OS: lockscreen, background, other apps, foreground)
            NativeCallBridge.instance.showIncomingCall(
              callerName: callerName,
              callerCit: callerCit,
              callCode: callCode,
              callType: callType,
            );
          } else if (type == 'busy') {
            developer.log('🛑 [CallSignalingService] Remote peer reported busy.', name: 'CallSignalingService');
            _incomingCallStreamController.add(data);
          } else if (type == 'call_cancelled') {
            developer.log('🛑 [CallSignalingService] Remote caller cancelled call.', name: 'CallSignalingService');
            NativeCallBridge.instance.dismissIncomingCall();
            _incomingCallStreamController.add(data);
          }
        } catch (e) {
          developer.log('⚠️ [CallSignalingService] Error handling incoming call message: $e', name: 'CallSignalingService');
        }
      }
    });

    _isListening = true;
  }

  /// Initiates a direct P2P call from Contacts or Recent Calls.
  Future<void> startDirectCall({
    required BuildContext context,
    required String peerCit,
    required String peerName,
  }) async {
    // 0. Debounce rapid double-taps
    final now = DateTime.now();
    if (_lastCallTriggerTime != null && now.difference(_lastCallTriggerTime!).inMilliseconds < 1000) {
      developer.log('⚠️ [CallSignalingService.startDirectCall] Debounced duplicate tap.', name: 'CallSignalingService');
      return;
    }
    _lastCallTriggerTime = now;

    developer.log('🚀 [CallSignalingService.startDirectCall] Calling peer $peerName (peerCit=$peerCit)...', name: 'CallSignalingService');

    final identity = await DatabaseHelper.instance.getClientIdentity();
    final myCit = identity?['cit'] as String? ?? 'user_${DateTime.now().millisecondsSinceEpoch % 100000}';
    final myName = identity?['display_name'] as String? ?? 'Caller';

    // 1. Resolve target peer CIT if missing or numeric
    String targetCit = peerCit.trim();
    if (targetCit.isEmpty || targetCit.startsWith('contact_') || int.tryParse(targetCit) != null) {
      final peers = await DatabaseHelper.instance.getPeers();
      for (final p in peers) {
        final pName = (p['name'] ?? p['display_name'] ?? '').toString().trim().toLowerCase();
        if (pName.isNotEmpty && pName == peerName.trim().toLowerCase()) {
          final resolved = (p['peer_id'] ?? p['id'] ?? '').toString().trim();
          if (resolved.isNotEmpty) {
            targetCit = resolved;
            break;
          }
        }
      }
      if (targetCit.isEmpty && peers.isNotEmpty) {
        // Fallback to most recent peer
        targetCit = (peers.first['peer_id'] ?? peers.first['id'] ?? '').toString().trim();
      }
    }

    if (targetCit.isEmpty) {
      targetCit = 'peer_${peerName.replaceAll(' ', '_')}';
    }

    currentDialingPeerCit = targetCit;

    // 2. Generate clean session code: e.g. "SS" + 7 digits
    final rand = DateTime.now().millisecondsSinceEpoch;
    final cleanCode = 'SS${((rand % 9000000) + 1000000)}';

    // 3. Connect MQTT if needed
    if (!MQTTService.instance.isConnected) {
      try {
        await MQTTService.instance.initialize(cit: myCit);
      } catch (e) {
        developer.log('⚠️ [CallSignalingService.startDirectCall] Reconnect attempt failed: $e', name: 'CallSignalingService');
      }
    }

    // 4. Save peer to SQLite
    await DatabaseHelper.instance.savePeer(peerId: targetCit, name: peerName);

    // 5. Broadcast real-time incoming_call invite over MQTT directly to peer's personal topic
    final invitePayload = jsonEncode({
      'type': 'incoming_call',
      'caller_cit': myCit,
      'caller_name': myName,
      'call_code': cleanCode,
      'call_type': 'video',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    MQTTService.instance.publishMessage(
      'simplysay/user/$targetCit/incoming_call',
      invitePayload,
      qos: MqttQos.atLeastOnce,
    );
    MQTTService.instance.publishMessage(
      'simplysay/call/invite/$targetCit',
      invitePayload,
      qos: MqttQos.atLeastOnce,
    );
    developer.log('📤 [CallSignalingService] Published direct call invite to simplysay/user/$targetCit/incoming_call (code=$cleanCode)', name: 'CallSignalingService');

    // 6. Also dispatch background FCM push as fallback
    FCMService.instance.sendDataCallPush(
      targetCit: targetCit,
      callerCit: myCit,
      callerName: myName,
      callCode: cleanCode,
      callType: 'video',
    );

    // 7. Navigate Caller to CallScreen
    if (context.mounted) {
      Navigator.of(context).pushNamed(
        AppRoutes.call,
        arguments: {
          'peerName': peerName,
          'peerCit': targetCit,
          'myCit': myCit,
          'callCode': cleanCode,
          'isCaller': true,
        },
      );
    }
  }

  /// Callee declines direct incoming call
  Future<void> declineDirectCall({
    required String callCode,
    required String callerCit,
  }) async {
    await NativeCallBridge.instance.dismissIncomingCall();
    final identity = await DatabaseHelper.instance.getClientIdentity();
    final myCit = identity?['cit'] as String? ?? 'callee';

    await DatabaseHelper.instance.insertCallRecord(
      peerCit: callerCit,
      peerName: 'Peer User',
      direction: 'incoming',
      status: 'REJECTED',
    );

    final hangupPayload = jsonEncode({
      'type': 'hangup',
      'signal_type': 'hangup',
      'sender_id': myCit,
      'from_cit': myCit,
      'call_code': callCode,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    if (callCode.isNotEmpty) {
      MQTTService.instance.publishMessage(
        'simplysay/call_session/$callCode/signaling',
        hangupPayload,
        qos: MqttQos.atLeastOnce,
      );
    }

    if (callerCit.isNotEmpty) {
      MQTTService.instance.publishMessage(
        'simplysay/webrtc/live/hangup/$callerCit',
        hangupPayload,
        qos: MqttQos.atLeastOnce,
      );
      MQTTService.instance.publishMessage(
        'simplysay/user/$callerCit/incoming_call',
        hangupPayload,
        qos: MqttQos.atLeastOnce,
      );
    }
    developer.log('🛑 [CallSignalingService] Published hangup to call_session, live/hangup, and user topic for caller $callerCit', name: 'CallSignalingService');
  }

  void dispose() {
    _mqttSubscription?.cancel();
    _isListening = false;
  }
}

