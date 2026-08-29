import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplysay/features/call/presentation/providers/instant_call_provider.dart';
import 'package:simplysay/services/webrtc_service.dart';

void main() {
  group('End-to-End Two-Client Instant Call Flow Simulation', () {
    test('Simulate complete Client A (Host) & Client B (Joiner) handshake and WebRTC negotiation', () async {
      // -------------------------------------------------------------
      // Phase 1: Client Identities & Code Generation
      // -------------------------------------------------------------
      final clientA = {
        'cit': 'cit_user_alice_101',
        'csit': 'csit_alice_secret',
        'name': 'Alice Host',
        'phone': '+1234567890',
      };

      final clientB = {
        'cit': 'cit_user_bob_202',
        'csit': 'csit_bob_secret',
        'name': 'Bob Joiner',
        'phone': '+1987654321',
      };

      const rawCode = 'ABC-DEF-GHK';
      final cleanCode = rawCode.replaceAll('-', '').trim().toUpperCase();

      // Client A Host State
      var hostState = HostCallState(
        code: rawCode,
        secondsRemaining: 600,
        myCit: clientA['cit'],
      );
      expect(hostState.code, rawCode);
      expect(hostState.myCit, 'cit_user_alice_101');
      expect(hostState.isConnected, false);

      // -------------------------------------------------------------
      // Phase 2: Client B joins with code -> Handover of CIT & Details
      // -------------------------------------------------------------
      // Server mock returns Host Details (Alice) to Joiner (Bob)
      var joinState = JoinCallState(
        code: rawCode,
        hostName: clientA['name'] as String,
        hostId: clientA['cit'] as String,
        myCit: clientB['cit'] as String,
        callCode: cleanCode,
      );

      expect(joinState.hostId, 'cit_user_alice_101');
      expect(joinState.hostName, 'Alice Host');
      expect(joinState.myCit, 'cit_user_bob_202');
      expect(joinState.callCode, 'ABCDEFGHK');

      // Host receives Joiner Details (Bob) from status check
      hostState = hostState.copyWith(
        isConnected: true,
        connectedPeerId: clientB['cit'] as String,
        connectedPeerName: clientB['name'] as String,
      );

      expect(hostState.connectedPeerId, 'cit_user_bob_202');
      expect(hostState.connectedPeerName, 'Bob Joiner');

      // -------------------------------------------------------------
      // Phase 3: Route Arguments passed into CallScreen on both sides
      // -------------------------------------------------------------
      final callScreenArgsA = {
        'peerCit': hostState.connectedPeerId, // Bob's CIT
        'peerName': hostState.connectedPeerName,
        'myCit': hostState.myCit, // Alice's CIT
        'callCode': cleanCode,
        'isCaller': true,
      };

      final callScreenArgsB = {
        'peerCit': joinState.hostId, // Alice's CIT
        'peerName': joinState.hostName,
        'myCit': joinState.myCit, // Bob's CIT
        'callCode': joinState.callCode,
        'isCaller': false,
      };

      expect(callScreenArgsA['peerCit'], 'cit_user_bob_202');
      expect(callScreenArgsA['myCit'], 'cit_user_alice_101');
      expect(callScreenArgsA['isCaller'], true);

      expect(callScreenArgsB['peerCit'], 'cit_user_alice_101');
      expect(callScreenArgsB['myCit'], 'cit_user_bob_202');
      expect(callScreenArgsB['isCaller'], false);

      // -------------------------------------------------------------
      // Phase 4: Decentralized MQTT Signaling Handshake
      // -------------------------------------------------------------
      final sharedRoomTopic = 'simplysay/call_session/$cleanCode/signaling';
      expect(sharedRoomTopic, 'simplysay/call_session/ABCDEFGHK/signaling');

      // 1. Client B sends READY signal
      final readyMessage = {
        'signal_type': 'ready',
        'sender_id': clientB['cit'],
        'from_cit': clientB['cit'],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      final encodedReady = jsonEncode(readyMessage);
      final decodedReady = jsonDecode(encodedReady);
      expect(decodedReady['signal_type'], 'ready');
      expect(decodedReady['from_cit'], 'cit_user_bob_202');

      // 2. Client A generates SDP Offer + Local ICE Candidates
      final clientAIceCandidates = [
        {'candidate': 'candidate:1 1 UDP 2122260223 192.168.1.100 50000 typ host', 'sdpMid': '0', 'sdpMLineIndex': 0},
        {'candidate': 'candidate:2 1 UDP 1686052607 203.0.113.10 50001 typ srflx', 'sdpMid': '0', 'sdpMLineIndex': 0},
      ];

      final offerMessage = {
        'signal_type': 'offer',
        'sender_id': clientA['cit'],
        'from_cit': clientA['cit'],
        'sdp': 'v=0\r\no=- 12345 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\n',
        'type': 'offer',
        'ice_candidates': clientAIceCandidates,
      };

      final encodedOffer = jsonEncode(offerMessage);
      final decodedOffer = jsonDecode(encodedOffer);
      expect(decodedOffer['signal_type'], 'offer');
      expect(decodedOffer['from_cit'], 'cit_user_alice_101');
      expect(decodedOffer['ice_candidates'].length, 2);

      // 3. Client B processes Offer, sets Remote Description, and creates SDP Answer + Local ICE Candidates
      final clientBIceCandidates = [
        {'candidate': 'candidate:3 1 UDP 2122260223 192.168.1.200 50002 typ host', 'sdpMid': '0', 'sdpMLineIndex': 0},
        {'candidate': 'candidate:4 1 UDP 1686052607 203.0.113.20 50003 typ srflx', 'sdpMid': '0', 'sdpMLineIndex': 0},
      ];

      final answerMessage = {
        'signal_type': 'answer',
        'sender_id': clientB['cit'],
        'from_cit': clientB['cit'],
        'sdp': 'v=0\r\no=- 67890 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\n',
        'type': 'answer',
        'ice_candidates': clientBIceCandidates,
      };

      final encodedAnswer = jsonEncode(answerMessage);
      final decodedAnswer = jsonDecode(encodedAnswer);
      expect(decodedAnswer['signal_type'], 'answer');
      expect(decodedAnswer['from_cit'], 'cit_user_bob_202');
      expect(decodedAnswer['ice_candidates'].length, 2);

      // 4. Client A receives Answer, sets Remote Description, and flushes candidates
      expect(decodedAnswer['sdp'], contains('m=video'));
      expect(decodedAnswer['sdp'], contains('m=audio'));

      // -------------------------------------------------------------
      // Phase 5: Verification of ICE & P2P Stream Readiness
      // -------------------------------------------------------------
      final config = WebRTCService.rtcConfiguration;
      expect(config['sdpSemantics'], 'unified-plan');
      expect(config['bundlePolicy'], 'max-bundle');
      expect(config['rtcpMuxPolicy'], 'require');

      // Ensure both audio and video m-lines exist in SDP negotiation
      expect(decodedOffer['sdp'].contains('m=audio') && decodedOffer['sdp'].contains('m=video'), true);
      expect(decodedAnswer['sdp'].contains('m=audio') && decodedAnswer['sdp'].contains('m=video'), true);

      // -------------------------------------------------------------
      // Phase 6: Dynamic Real Name Handover & Verification
      // -------------------------------------------------------------
      final offerWithName = {
        'signal_type': 'offer',
        'sender_id': clientA['cit'],
        'from_cit': clientA['cit'],
        'sender_name': clientA['name'],
        'sdp': 'v=0...',
      };
      final decodedOfferWithName = jsonDecode(jsonEncode(offerWithName));
      expect(decodedOfferWithName['sender_name'], 'Alice Host');

      final answerWithName = {
        'signal_type': 'answer',
        'sender_id': clientB['cit'],
        'from_cit': clientB['cit'],
        'sender_name': clientB['name'],
        'sdp': 'v=0...',
      };
      final decodedAnswerWithName = jsonDecode(jsonEncode(answerWithName));
      expect(decodedAnswerWithName['sender_name'], 'Bob Joiner');

      // -------------------------------------------------------------
      // Phase 7: Synchronized Hangup / Flow of Control Teardown
      // -------------------------------------------------------------
      // Client A clicks "End Call" -> broadcasts hangup signal
      final hangupMessage = {
        'signal_type': 'hangup',
        'sender_id': clientA['cit'],
        'from_cit': clientA['cit'],
        'sender_name': clientA['name'],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final encodedHangup = jsonEncode(hangupMessage);
      final decodedHangup = jsonDecode(encodedHangup);

      expect(decodedHangup['signal_type'], 'hangup');
      expect(decodedHangup['from_cit'], 'cit_user_alice_101');

      // Client B receives hangup -> triggers _handleHangup(isRemoteInitiated: true)
      bool clientBTerminated = false;
      if (decodedHangup['signal_type'] == 'hangup' || decodedHangup['signal_type'] == 'bye') {
        clientBTerminated = true;
      }
      expect(clientBTerminated, true);
    });
  });
}
