import 'package:flutter_webrtc/flutter_webrtc.dart';

/// WebRTC Service setup with multiple open source STUN & TURN servers.
/// Objective: Once connected, SDP and ICE candidates are exchanged automatically 
/// while keeping call state uninitiated until explicitly triggered.
class WebRTCService {
  RTCPeerConnection? _peerConnection;

  // Open-source STUN/TURN Server Configuration
  static final Map<String, dynamic> rtcConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
      {'urls': 'stun:stun.services.mozilla.com'},
      // Open-source public TURN fallback configuration
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject'
      },
      {
        'urls': 'turn:openrelay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject'
      }
    ],
    'sdpSemantics': 'unified-plan',
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
