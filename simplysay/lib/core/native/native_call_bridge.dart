import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../database/db_helper.dart';

/// Flutter Bridge to Android Native Call Notification & Full-Screen UI subsystem
class NativeCallBridge {
  NativeCallBridge._();
  static final NativeCallBridge instance = NativeCallBridge._();

  static const MethodChannel _methodChannel = MethodChannel('com.comlabs.simplysay/call_bridge');
  static const EventChannel _eventChannel = EventChannel('com.comlabs.simplysay/call_events');

  final StreamController<Map<String, dynamic>> _callActionStreamController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onCallActionStream => _callActionStreamController.stream;

  void dispatchCallEvent(Map<String, dynamic> data) {
    developer.log('⚡ [NativeCallBridge] Dispatching manual call event: $data', name: 'NativeCallBridge');
    _callActionStreamController.add(data);
  }

  bool _isListening = false;

  void initialize() {
    if (_isListening) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        _eventChannel.receiveBroadcastStream().listen(
          (dynamic event) {
            if (event is Map) {
              final mapped = Map<String, dynamic>.from(event);
              developer.log('⚡ [NativeCallBridge] Received native call event: $mapped', name: 'NativeCallBridge');
              _callActionStreamController.add(mapped);

              final action = mapped['action'] ?? mapped['type'];
              if (action == 'call_missed') {
                final callerCit = (mapped['caller_cit'] ?? '').toString();
                final callerName = (mapped['caller_name'] ?? 'Peer User').toString();
                if (callerCit.isNotEmpty) {
                  DatabaseHelper.instance.insertCallRecord(
                    peerCit: callerCit,
                    peerName: callerName,
                    direction: 'incoming',
                    status: 'MISSED',
                    durationSeconds: 0,
                  );
                }
              }
            }
          },
          onError: (dynamic error) {
            developer.log('⚠️ [NativeCallBridge] EventChannel error: $error', name: 'NativeCallBridge');
          },
        );
        _isListening = true;
        developer.log('✅ [NativeCallBridge] Initialized and listening for native call events.', name: 'NativeCallBridge');
      } catch (e) {
        developer.log('⚠️ [NativeCallBridge] Error initializing EventChannel: $e', name: 'NativeCallBridge');
      }
    }
  }

  /// Displays the native Heads-Up CallStyle Banner / Full-Screen Activity
  Future<bool> showIncomingCall({
    required String callerName,
    required String callerCit,
    required String callCode,
    String? sdpOffer,
    String callType = 'video',
  }) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final res = await _methodChannel.invokeMethod<bool>('showIncomingCall', {
          'caller_name': callerName,
          'caller_cit': callerCit,
          'call_code': callCode,
          'sdp_offer': sdpOffer,
          'call_type': callType,
        });
        return res ?? true;
      } catch (e) {
        developer.log('⚠️ [NativeCallBridge] Error showing native call notification: $e', name: 'NativeCallBridge');
        return false;
      }
    }
    return false;
  }

  /// Plays the system incoming call ringtone (used when app is in foreground)
  Future<bool> playRingtone() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final res = await _methodChannel.invokeMethod<bool>('playRingtone');
        return res ?? true;
      } catch (e) {
        developer.log('⚠️ [NativeCallBridge] Error playing ringtone: $e', name: 'NativeCallBridge');
        return false;
      }
    }
    return false;
  }

  /// Stops any actively playing incoming call ringtone
  Future<bool> stopRingtone() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final res = await _methodChannel.invokeMethod<bool>('stopRingtone');
        return res ?? true;
      } catch (e) {
        developer.log('⚠️ [NativeCallBridge] Error stopping ringtone: $e', name: 'NativeCallBridge');
        return false;
      }
    }
    return false;
  }

  /// Dismisses the native call notification and stops ringing
  Future<bool> dismissIncomingCall() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await stopRingtone();
        final res = await _methodChannel.invokeMethod<bool>('dismissIncomingCall');
        return res ?? true;
      } catch (e) {
        developer.log('⚠️ [NativeCallBridge] Error dismissing native call notification: $e', name: 'NativeCallBridge');
        return false;
      }
    }
    return false;
  }
}
