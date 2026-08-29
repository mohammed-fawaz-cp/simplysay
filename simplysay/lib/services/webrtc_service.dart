import 'package:flutter_webrtc/flutter_webrtc.dart';

/// WebRTC Service setup with multiple open source STUN & TURN servers.
/// Objective: Once connected, SDP and ICE candidates are exchanged automatically 
/// while keeping call state uninitiated until explicitly triggered.
class WebRTCService {
  RTCPeerConnection? _peerConnection;

  // Open-source STUN/TURN Server Configuration with robust fallback
  static final Map<String, dynamic> rtcConfiguration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302',
          'stun:stun3.l.google.com:19302',
          'stun:stun4.l.google.com:19302',
        ],
      },
      {
        'urls': [
          'stun:global.stun.twilio.com:3478',
          'stun:stun.services.mozilla.com',
          'stun:stun.cloudflare.com:3478',
        ],
      },
      {
        'urls': [
          'turn:openrelay.metered.ca:80?transport=udp',
          'turn:openrelay.metered.ca:80?transport=tcp',
          'turn:openrelay.metered.ca:443?transport=tcp',
          'turns:openrelay.metered.ca:443?transport=tcp',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'sdpSemantics': 'unified-plan',
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
  };

  Function(RTCIceCandidate candidate)? onIceCandidateDiscovered;
  Function(RTCSessionDescription sdp)? onSdpCreated;

  Future<void> initializePeerConnection() async {
    _peerConnection = await createPeerConnection(rtcConfiguration);

    // Automatically capture and emit ICE candidates for peer exchange
    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      onIceCandidateDiscovered?.call(candidate);
    };

    _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      // Monitor P2P connectivity state
    };
  }

  /// Prepare connection and share SDP offer without initiating call audio/video
  Future<RTCSessionDescription?> createAndShareSdpOffer() async {
    if (_peerConnection == null) return null;
    
    RTCSessionDescription offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': false,
      'offerToReceiveVideo': false,
    });
    
    await _peerConnection!.setLocalDescription(offer);
    onSdpCreated?.call(offer);
    return offer;
  }

  /// Process incoming candidate from remote peer
  Future<void> addRemoteIceCandidate(RTCIceCandidate candidate) async {
    await _peerConnection?.addCandidate(candidate);
  }

  /// Process incoming remote SDP description
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    await _peerConnection?.setRemoteDescription(description);
  }

  Future<void> dispose() async {
    await _peerConnection?.close();
    _peerConnection = null;
  }
}
