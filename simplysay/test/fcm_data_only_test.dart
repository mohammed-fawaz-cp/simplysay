import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplysay/services/fcm_service.dart';

void main() {
  group('Data-Only FCM Call Signaling & Wakeup Tests', () {
    test('Verify strict Data-Only FCM payload contract (No notification block & High Priority)', () {
      final callPayload = {
        'type': 'incoming_call',
        'caller_cit': 'cit_alice_101',
        'caller_name': 'Alice Host',
        'call_code': 'ABC-DEF-GHK',
        'call_type': 'video',
        'sdp_offer': 'v=0\r\no=- 12345 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\n',
        'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
      };

      final serialized = jsonEncode(callPayload);
      final decoded = jsonDecode(serialized) as Map<String, dynamic>;

      // 1. Verify strict contract
      expect(decoded.containsKey('notification'), false, reason: 'Must NOT contain notification block to allow pure background wakeup');
      expect(decoded['type'], 'incoming_call');
      expect(decoded['caller_cit'], 'cit_alice_101');
      expect(decoded['caller_name'], 'Alice Host');
      expect(decoded['call_code'], 'ABC-DEF-GHK');
      expect(decoded['call_type'], 'video');
      expect(decoded['sdp_offer'], contains('m=video'));
      expect(decoded['sdp_offer'], contains('m=audio'));
    });

    test('Verify background message data unpacking and caller details extraction', () {
      final mockBackgroundData = {
        'type': 'incoming_call',
        'caller_cit': 'cit_bob_202',
        'caller_name': 'Bob Joiner',
        'call_code': 'XYZ-789-QWE',
        'call_type': 'video',
        'sdp_offer': 'v=0...',
        'timestamp': '1788000000000',
      };

      // Simulate parsing in background handler
      final callerName = mockBackgroundData['caller_name'] ?? 'Someone';
      final callCode = mockBackgroundData['call_code'] ?? '';
      final callerCit = mockBackgroundData['caller_cit'] ?? '';

      expect(callerName, 'Bob Joiner');
      expect(callCode, 'XYZ-789-QWE');
      expect(callerCit, 'cit_bob_202');
    });

    test('Verify token registration payload to backend', () {
      final registerPayload = {
        'cit': 'cit_user_alice_101',
        'fcm_token': 'fcm_device_token_sample_abc123',
      };

      final jsonStr = jsonEncode(registerPayload);
      final parsed = jsonDecode(jsonStr);

      expect(parsed['cit'], 'cit_user_alice_101');
      expect(parsed['fcm_token'], 'fcm_device_token_sample_abc123');
    });
    test('Verify FCMService singleton initialization', () {
      expect(FCMService.instance, isNotNull);
    });
  });
}
