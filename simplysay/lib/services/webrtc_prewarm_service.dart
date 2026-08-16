import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mqtt_client/mqtt_client.dart';
import '../database/db_helper.dart';
import 'mqtt_service.dart';

/// WebRTCPrewarmService handles pre-exchange of SDP Offers and ICE candidates over MQTT.
/// 
/// 🚨 STRICT GUARANTEE:
/// This service NEVER auto-starts audio/video calls, NEVER opens microphone/camera hardware,
/// and NEVER triggers call screens. It purely pre-warms SDP tokens & ICE candidates in local SQLite
/// so that when a user explicitly taps the Call button, call establishment is near-instantaneous.
class WebRTCPrewarmService {
  static final WebRTCPrewarmService instance = WebRTCPrewarmService._init();
  bool _isListening = false;
  String? _myCit;

  WebRTCPrewarmService._init();

  /// Map of STUN servers for WebRTC ICE candidate discovery
  static const Map<String, dynamic> _rtcConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  /// Initializes MQTT subscription for pre-warm SDP exchanges
  Future<void> initialize() async {
    if (_isListening) return;

    final identity = await DatabaseHelper.instance.getClientIdentity();
    if (identity == null || identity['cit'] == null) {
      developer.log('⚠️ [WebRTCPrewarmService] Client identity not available yet.', name: 'WebRTCPrewarmService');
      return;
    }

    _myCit = identity['cit'] as String;
    developer.log('⚡ [WebRTCPrewarmService.initialize] Starting WebRTC pre-warm listener for CIT=$_myCit...', name: 'WebRTCPrewarmService');

    final mqtt = MQTTService.instance;
    if (!mqtt.isConnected) {
      await mqtt.initialize(cit: _myCit!);
    }

    mqtt.subscribe('simplysay/webrtc/offer/$_myCit');
    mqtt.subscribe('simplysay/webrtc/answer/$_myCit');

    mqtt.messageStream.listen(_handleSingleMqttMessage);
    _isListening = true;
    developer.log('✅ [WebRTCPrewarmService.initialize] Subscribed to WebRTC pre-warm topics.', name: 'WebRTCPrewarmService');
  }

  /// Pre-warms an SDP Offer and exchanges ICE candidates with a target peer
  Future<void> prewarmSessionWithPeer(String peerCit) async {
    if (_myCit == null) {
      final identity = await DatabaseHelper.instance.getClientIdentity();
      if (identity != null) _myCit = identity['cit'];
    }
    if (_myCit == null) return;

    developer.log('⚡ [WebRTCPrewarmService.prewarmSessionWithPeer] Generating pre-warmed SDP offer for peer CIT=$peerCit (NO AUDIO/VIDEO STARTED)...', name: 'WebRTCPrewarmService');

    RTCPeerConnection? pc;
    try {
      pc = await createPeerConnection(_rtcConfig);
      
      // Create data channel to allow candidate gathering without audio/video hardware
      await pc.createDataChannel('simplysay_prewarm', RTCDataChannelInit());

      final List<Map<String, dynamic>> iceCandidatesList = [];
      pc.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null) {
          iceCandidatesList.add(candidate.toMap());
        }
      };

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      // Brief delay to allow ICE candidate gathering
      await Future.delayed(const Duration(milliseconds: 300));

      final payload = jsonEncode({
        'from_cit': _myCit,
        'sdp': offer.sdp,
        'type': offer.type,
        'ice_candidates': iceCandidatesList,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final topic = 'simplysay/webrtc/offer/$peerCit';
      MQTTService.instance.publishMessage(topic, payload);
      developer.log('📤 [WebRTCPrewarmService.prewarmSessionWithPeer] Pre-warmed offer published to $topic', name: 'WebRTCPrewarmService');

      // Save generated offer locally
      await DatabaseHelper.instance.saveCallSession(
        peerCit: peerCit,
        sdpOffer: offer.sdp ?? '',
        iceCandidates: jsonEncode(iceCandidatesList),
      );

      await pc.close();
    } catch (e) {
      developer.log('⚠️ [WebRTCPrewarmService.prewarmSessionWithPeer] Pre-warm failed for $peerCit: $e', name: 'WebRTCPrewarmService');
      pc?.close();
    }
  }

  /// Listens to single incoming pre-warm WebRTC message
  void _handleSingleMqttMessage(MqttReceivedMessage<MqttMessage> message) {
    final recMsg = message.payload as MqttPublishMessage;
    final payloadStr = MqttPublishPayload.bytesToStringAsString(recMsg.payload.message);
    final topic = message.topic;

    try {
      final data = jsonDecode(payloadStr) as Map<String, dynamic>;

      if (topic.startsWith('simplysay/webrtc/offer/')) {
        _processIncomingOffer(data);
      } else if (topic.startsWith('simplysay/webrtc/answer/')) {
        _processIncomingAnswer(data);
      }
    } catch (e) {
      developer.log('⚠️ [WebRTCPrewarmService] Error handling MQTT WebRTC message: $e', name: 'WebRTCPrewarmService');
    }
  }

  /// Processes incoming SDP Offer and saves pre-warmed session to local SQLite
  Future<void> _processIncomingOffer(Map<String, dynamic> data) async {
    final peerCit = data['from_cit'] as String?;
    final sdpStr = data['sdp'] as String?;
    final candidates = data['ice_candidates'];

    if (peerCit == null || sdpStr == null) return;

    developer.log('⚡ [WebRTCPrewarmService._processIncomingOffer] Saving pre-warmed SDP offer from peer CIT=$peerCit to SQLite (NO AUTO-CALL)...', name: 'WebRTCPrewarmService');

    await DatabaseHelper.instance.saveCallSession(
      peerCit: peerCit,
      sdpOffer: sdpStr,
      iceCandidates: jsonEncode(candidates ?? []),
    );

    // Generate pre-warmed SDP answer in background
    _generateAndSendAnswer(peerCit, sdpStr, candidates);
  }

  /// Generates and sends SDP Answer over MQTT
  Future<void> _generateAndSendAnswer(String peerCit, String offerSdp, dynamic incomingCandidates) async {
    RTCPeerConnection? pc;
    try {
      pc = await createPeerConnection(_rtcConfig);
      await pc.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));

      final List<Map<String, dynamic>> answerIceCandidates = [];
      pc.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null) {
          answerIceCandidates.add(candidate.toMap());
        }
      };

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      await Future.delayed(const Duration(milliseconds: 300));

      final payload = jsonEncode({
        'from_cit': _myCit,
        'sdp': answer.sdp,
        'type': answer.type,
        'ice_candidates': answerIceCandidates,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final topic = 'simplysay/webrtc/answer/$peerCit';
      MQTTService.instance.publishMessage(topic, payload);
      developer.log('📤 [WebRTCPrewarmService._generateAndSendAnswer] Pre-warmed answer sent to $topic', name: 'WebRTCPrewarmService');

      await pc.close();
    } catch (e) {
      developer.log('⚠️ [WebRTCPrewarmService._generateAndSendAnswer] Error generating answer: $e', name: 'WebRTCPrewarmService');
      pc?.close();
    }
  }

  /// Saves incoming SDP Answer to local SQLite
  Future<void> _processIncomingAnswer(Map<String, dynamic> data) async {
    final peerCit = data['from_cit'] as String?;
    final sdpStr = data['sdp'] as String?;
    final candidates = data['ice_candidates'];

    if (peerCit == null || sdpStr == null) return;

    developer.log('⚡ [WebRTCPrewarmService._processIncomingAnswer] Saving pre-warmed SDP answer from CIT=$peerCit...', name: 'WebRTCPrewarmService');

    final existingSession = await DatabaseHelper.instance.getCallSession(peerCit);
    final offerSdp = existingSession?['sdp_offer'] as String? ?? sdpStr;

    await DatabaseHelper.instance.saveCallSession(
      peerCit: peerCit,
      sdpOffer: offerSdp,
      iceCandidates: jsonEncode(candidates ?? []),
    );
    developer.log('✅ [WebRTCPrewarmService._processIncomingAnswer] Pre-warmed session fully ready in SQLite.', name: 'WebRTCPrewarmService');
  }
}
