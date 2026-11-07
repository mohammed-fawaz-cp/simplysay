import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';
import '../core/native/native_call_bridge.dart';
import '../database/db_helper.dart';
import '../firebase_options.dart';

/// Top-level background message handler for Data-Only FCM wakeups
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  developer.log('🔔 [FCM Background] Received data-only message in background/killed state: ${message.data}', name: 'FCMService');
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    developer.log('⚠️ [FCM Background] Error initializing Firebase: $e', name: 'FCMService');
  }

  final data = message.data;
  if (data['type'] == 'incoming_call') {
    final callerName = data['caller_name'] ?? 'Someone';
    final callCode = data['call_code'] ?? '';
    final callerCit = data['caller_cit'] ?? '';
    final sdpOffer = data['sdp_offer'];
    final callType = data['call_type'] ?? 'video';
    developer.log('📞 [FCM Background] Triggering Native Call Overlay for $callerName (code=$callCode, cit=$callerCit)', name: 'FCMService');

    await NativeCallBridge.instance.showIncomingCall(
      callerName: callerName,
      callerCit: callerCit,
      callCode: callCode,
      sdpOffer: sdpOffer,
      callType: callType,
    );

    try {
      if (callerCit.isNotEmpty) {
        await DatabaseHelper.instance.savePeer(peerId: callerCit, name: callerName);
      }
    } catch (_) {}
  }
}

class FCMService {
  FCMService._();
  static final FCMService instance = FCMService._();

  FirebaseMessaging? _customMessaging;
  FirebaseMessaging get _messaging => _customMessaging ??= FirebaseMessaging.instance;
  final StreamController<Map<String, dynamic>> _incomingCallStreamController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onIncomingCallData => _incomingCallStreamController.stream;

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      NativeCallBridge.instance.initialize();

      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      // Request notification permissions for mobile platforms
      if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
        final settings = await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        developer.log('📱 [FCMService] Notification permission status: ${settings.authorizationStatus}', name: 'FCMService');
      }

      // 1. Set background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // 2. Set foreground listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        developer.log('📩 [FCM Foreground] Received data message: ${message.data}', name: 'FCMService');
        if (message.data['type'] == 'incoming_call') {
          final data = message.data;
          NativeCallBridge.instance.showIncomingCall(
            callerName: data['caller_name'] ?? 'Someone',
            callerCit: data['caller_cit'] ?? '',
            callCode: data['call_code'] ?? '',
            sdpOffer: data['sdp_offer'],
            callType: data['call_type'] ?? 'video',
          );
        }
      });

      // 3. Obtain & sync device token
      await syncDeviceToken();

      // 4. Token refresh listener
      _messaging.onTokenRefresh.listen((newToken) async {
        developer.log('🔄 [FCMService] FCM Token refreshed: $newToken', name: 'FCMService');
        await _saveAndRegisterToken(newToken);
      });

      _isInitialized = true;
      developer.log('✅ [FCMService] Initialized successfully.', name: 'FCMService');
    } catch (e) {
      developer.log('⚠️ [FCMService] Error initializing FCM: $e', name: 'FCMService');
    }
  }

  Future<String?> getDeviceToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      developer.log('⚠️ [FCMService] Error getting device token: $e', name: 'FCMService');
      return null;
    }
  }

  Future<void> syncDeviceToken() async {
    final token = await getDeviceToken();
    if (token != null && token.isNotEmpty) {
      await _saveAndRegisterToken(token);
    }
  }

  Future<void> _saveAndRegisterToken(String token) async {
    try {
      final identity = await DatabaseHelper.instance.getClientIdentity();
      final cit = identity?['cit'] as String? ?? 'user_${DateTime.now().millisecondsSinceEpoch % 100000}';

      // Save token in local SQLite settings
      await DatabaseHelper.instance.setSetting('fcm_token', token);

      // Register token on backend
      final registerUrl = '${AppConfig.apiBaseUrl}/fcm/register-token';
      try {
        final res = await http.post(
          Uri.parse(registerUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'cit': cit,
            'fcm_token': token,
          }),
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200 || res.statusCode == 201) {
          developer.log('✅ [FCMService] Device token registered on backend ($registerUrl) for CIT=$cit', name: 'FCMService');
        } else {
          developer.log('⚠️ [FCMService] Backend returned ${res.statusCode} registering token: ${res.body}', name: 'FCMService');
        }
      } catch (e) {
        developer.log('⚠️ [FCMService] Network error registering token on $registerUrl: $e', name: 'FCMService');
      }
    } catch (e) {
      developer.log('⚠️ [FCMService] Error registering device token: $e', name: 'FCMService');
    }
  }

  /// Dispatches a high-priority Data-Only FCM push to the recipient
  Future<bool> sendDataCallPush({
    String? targetToken,
    String? targetCit,
    required String callerCit,
    required String callerName,
    required String callCode,
    String? sdpOffer,
    String callType = 'video',
  }) async {
    developer.log('🚀 [FCMService] Dispatching data-only call push to targetToken=$targetToken, targetCit=$targetCit (code=$callCode, caller=$callerName)...', name: 'FCMService');

    final sendUrl = '${AppConfig.apiBaseUrl}/fcm/send-call-push';
    try {
      final res = await http.post(
        Uri.parse(sendUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'target_token': targetToken ?? '',
          'target_cit': targetCit ?? '',
          'caller_cit': callerCit,
          'caller_name': callerName,
          'call_code': callCode,
          'sdp_offer': sdpOffer ?? '',
          'call_type': callType,
        }),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          developer.log('✅ [FCMService] Data-only call push delivered successfully via $sendUrl (message_id=${body['message_id']})', name: 'FCMService');
          return true;
        } else {
          developer.log('⚠️ [FCMService] Backend push reported failure: ${body['error']}', name: 'FCMService');
        }
      }
    } catch (e) {
      developer.log('⚠️ [FCMService] Error dispatching push via $sendUrl: $e', name: 'FCMService');
    }
    return false;
  }
}
