import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplysay/features/call/presentation/providers/instant_call_provider.dart';
import 'package:simplysay/services/webrtc_service.dart';

void main() {
  group('Instant Call State & Validation Tests', () {
    test('HostCallState initialization and copyWith', () {
      const state = HostCallState(
        code: 'ABC-DEF-GHK',
        secondsRemaining: 600,
        myCit: 'host_cit_123',
      );

      expect(state.code, 'ABC-DEF-GHK');
      expect(state.secondsRemaining, 600);
      expect(state.isConnected, false);
      expect(state.isExpired, false);
      expect(state.myCit, 'host_cit_123');

      final updated = state.copyWith(
        isConnected: true,
        connectedPeerName: 'Alice',
        connectedPeerId: 'peer_456',
      );

      expect(updated.isConnected, true);
      expect(updated.connectedPeerName, 'Alice');
      expect(updated.connectedPeerId, 'peer_456');
      expect(updated.myCit, 'host_cit_123');
    });

    test('JoinCallState initialization and validation', () {
      const state = JoinCallState(
        code: 'XYZ-123-456',
        hostName: 'Host User',
        hostId: 'host_id_999',
        myCit: 'joiner_id_888',
        callCode: 'XYZ123456',
      );

      expect(state.code, 'XYZ-123-456');
      expect(state.hostName, 'Host User');
      expect(state.hostId, 'host_id_999');
      expect(state.myCit, 'joiner_id_888');
      expect(state.callCode, 'XYZ123456');
      expect(state.isConnecting, false);
      expect(state.errorMessage, null);
    });
  });

  group('WebRTC Service & Signaling Tests', () {
    test('WebRTC STUN/TURN configuration is hardened', () {
      final config = WebRTCService.rtcConfiguration;
      expect(config['sdpSemantics'], 'unified-plan');
      expect(config['bundlePolicy'], 'max-bundle');
      expect(config['rtcpMuxPolicy'], 'require');

      final iceServers = config['iceServers'] as List;
      expect(iceServers.isNotEmpty, true);

      // Verify Google STUN servers exist
      final googleStun = iceServers.firstWhere(
        (s) => (s['urls'] as List).any((u) => u.toString().contains('google.com')),
      );
      expect(googleStun, isNotNull);

      // Verify TURN servers exist with username & credentials
      final turnServer = iceServers.firstWhere(
        (s) => s.containsKey('username') && s.containsKey('credential'),
      );
      expect(turnServer['username'], 'openrelayproject');
      expect(turnServer['credential'], 'openrelayproject');
      expect((turnServer['urls'] as List).any((u) => u.toString().contains('turn:')), true);
    });

    test('Signaling payload serialization: READY handshake', () {
      final readyPayload = {
        'signal_type': 'ready',
        'sender_id': 'joiner_user_1',
        'from_cit': 'joiner_user_1',
        'timestamp': 1700000000,
      };

      final encoded = jsonEncode(readyPayload);
      final decoded = jsonDecode(encoded);

      expect(decoded['signal_type'], 'ready');
      expect(decoded['sender_id'], 'joiner_user_1');
    });

    test('Signaling payload serialization: SDP Offer with bundled ICE candidates', () {
      final offerPayload = {
        'signal_type': 'offer',
        'sender_id': 'host_user_1',
        'from_cit': 'host_user_1',
        'sdp': 'v=0\r\no=- 12345 2 IN IP4 127.0.0.1\r\ns=-\r\n',
        'type': 'offer',
        'ice_candidates': [
          {
            'candidate': 'candidate:1 1 UDP 2122260223 192.168.1.50 50000 typ host',
            'sdpMid': '0',
            'sdpMLineIndex': 0,
          },
          {
            'candidate': 'candidate:2 1 UDP 1686052607 203.0.113.1 50001 typ srflx',
            'sdpMid': '0',
            'sdpMLineIndex': 0,
          }
        ],
      };

      final encoded = jsonEncode(offerPayload);
      final decoded = jsonDecode(encoded);

      expect(decoded['signal_type'], 'offer');
      expect(decoded['type'], 'offer');
      expect(decoded['sdp'], contains('v=0'));
      expect((decoded['ice_candidates'] as List).length, 2);
    });

    test('Signaling payload serialization: SDP Answer with bundled ICE candidates', () {
      final answerPayload = {
        'signal_type': 'answer',
        'sender_id': 'joiner_user_1',
        'from_cit': 'joiner_user_1',
        'sdp': 'v=0\r\no=- 67890 2 IN IP4 127.0.0.1\r\ns=-\r\n',
        'type': 'answer',
        'ice_candidates': [
          {
            'candidate': 'candidate:3 1 UDP 2122260223 192.168.1.60 50002 typ host',
            'sdpMid': '0',
            'sdpMLineIndex': 0,
          }
        ],
      };

      final encoded = jsonEncode(answerPayload);
      final decoded = jsonDecode(encoded);

      expect(decoded['signal_type'], 'answer');
      expect(decoded['type'], 'answer');
      expect((decoded['ice_candidates'] as List).length, 1);
    });
  });
}
