import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Flutter Bridge to Android Native Call Notification & Full-Screen UI subsystem
class NativeCallBridge {
  NativeCallBridge._();
  static final NativeCallBridge instance = NativeCallBridge._();

  static const MethodChannel _methodChannel = MethodChannel('com.comlabs.simplysay/call_bridge');
  static const EventChannel _eventChannel = EventChannel('com.comlabs.simplysay/call_events');

  final StreamController<Map<String, dynamic>> _callActionStreamController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onCallActionStream => _callActionStreamController.stream;

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

  /// Dismisses the native call notification and stops ringing
  Future<bool> dismissIncomingCall() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
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
