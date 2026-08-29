import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../database/db_helper.dart';
import '../../../services/mqtt_service.dart';
import '../../../services/webrtc_service.dart';
import 'providers/call_screen_provider.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String? peerName;
  final String? peerPhone;
  final String? peerCit;
  final String? myCit;
  final String? callCode;
  final bool? isCaller;

  const CallScreen({
    super.key,
    this.peerName,
    this.peerPhone,
    this.peerCit,
    this.myCit,
    this.callCode,
    this.isCaller,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCPeerConnection? _peerConnection;
  StreamSubscription? _mqttSubscription;
  Timer? _offerRetryTimer;

  bool _isRendererInitialized = false;
  String? _myCit;
  String? _peerCit;
  String _peerName = 'Peer User';
  String? _myDisplayName;
  String? _callCode;
  bool _isCaller = true;
  String _connectionStatusText = 'Connecting...';
  bool _isConnected = false;
  bool _isEndingCall = false;

  final List<RTCIceCandidate> _pendingIceCandidates = [];
  final List<Map<String, dynamic>> _localIceCandidatesBuffer = [];
  bool _isRemoteDescriptionSet = false;
  int _offerRetryCount = 0;

  @override
  void initState() {
    super.initState();
    _initCallSession();
  }

  Future<void> _initCallSession() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      if (mounted) {
        setState(() {
          _isRendererInitialized = true;
        });
      }
      await _requestPermissions();
      await _startLocalCamera();
      await _initWebRTC();
    } catch (e) {
      developer.log('⚠️ Error initializing WebRTC call session: $e', name: 'CallScreen');
    }
  }

  Future<void> _requestPermissions() async {
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        await [Permission.camera, Permission.microphone].request();
      } catch (e) {
        developer.log('⚠️ Permission request error: $e', name: 'CallScreen');
      }
    }
  }

  Future<void> _startLocalCamera() async {
    try {
      Map<String, dynamic> mediaConstraints;
      final isDesktop = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.linux);

      if (isDesktop) {
        mediaConstraints = <String, dynamic>{
          'audio': true,
          'video': true,
        };
      } else {
        mediaConstraints = <String, dynamic>{
          'audio': true,
          'video': {
            'facingMode': 'user',
            'width': {'ideal': 1280},
            'height': {'ideal': 720},
          },
        };
      }

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      if (mounted) {
        setState(() {
          _localRenderer.srcObject = _localStream;
        });
      }
    } catch (e) {
      developer.log('⚠️ Error capturing local camera with ideal constraints: $e, falling back to basic video/audio...', name: 'CallScreen');
      try {
        _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': true});
        if (mounted) {
          setState(() {
            _localRenderer.srcObject = _localStream;
          });
        }
      } catch (e2) {
        developer.log('⚠️ Critical error capturing media: $e2', name: 'CallScreen');
      }
    }
  }

  Future<void> _initWebRTC() async {
    try {
      final identity = await DatabaseHelper.instance.getClientIdentity();
      if (!mounted) return;
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

      _myCit = widget.myCit ?? args?['myCit'] as String? ?? identity?['cit'] as String?;
      _peerCit = widget.peerCit ?? args?['peerCit'] as String?;
      final initialPeerName = widget.peerName ?? args?['peerName'] as String?;
      if (initialPeerName != null && initialPeerName.isNotEmpty) {
        _peerName = initialPeerName;
      }
      _myDisplayName = (identity?['display_name'] as String?)?.trim();
      if (_myDisplayName == null || _myDisplayName!.isEmpty) {
        final phone = (identity?['phone_number'] as String?)?.trim() ?? '';
        _myDisplayName = phone.isNotEmpty && phone != '+1000000000' ? 'User ($phone)' : 'User';
      }

      _callCode = widget.callCode ?? args?['callCode'] as String?;
      _isCaller = widget.isCaller ?? args?['isCaller'] as bool? ?? true;

      // Ensure fallback identity exists
      if (_myCit == null || _myCit!.isEmpty) {
        _myCit = 'user_${DateTime.now().millisecondsSinceEpoch % 100000}';
        await DatabaseHelper.instance.saveClientIdentity(
          cit: _myCit!,
          csit: 'csit_$_myCit',
          deviceId: 'device_$_myCit',
          phoneNumber: '+1000000000',
        );
      }

      if (_peerCit == null || _peerCit!.isEmpty) {
        final peers = await DatabaseHelper.instance.getPeers();
        if (peers.isNotEmpty) {
          _peerCit = peers.first['peer_id'] as String?;
        }
      }

      developer.log('🚀 [CallScreen] WebRTC initializing: myCit=$_myCit, peerCit=$_peerCit, code=$_callCode, isCaller=$_isCaller', name: 'CallScreen');

      if (!MQTTService.instance.isConnected && _myCit != null) {
        await MQTTService.instance.initialize(cit: _myCit!);
      }

      // Create Peer Connection with robust STUN/TURN
      _peerConnection = await createPeerConnection(WebRTCService.rtcConfiguration);

      // Connection state listeners
      _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
        developer.log('❄️ [CallScreen] ICE Connection State: $state', name: 'CallScreen');
        if (mounted) {
          setState(() {
            if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
                state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
              _isConnected = true;
              _connectionStatusText = 'Connected (P2P Direct)';
              _enableSpeakerphone();
            } else if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
              _connectionStatusText = 'Negotiating connection...';
            } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
                state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
              _connectionStatusText = 'Reconnecting...';
            }
          });
        }
      };

      _peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
        developer.log('🤝 [CallScreen] Peer Connection State: $state', name: 'CallScreen');
        if (mounted) {
          setState(() {
            if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
              _isConnected = true;
              _connectionStatusText = 'Connected (Live Media)';
              _enableSpeakerphone();
            }
          });
        }
      };

      // 1. Add local audio & video tracks
      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          await _peerConnection?.addTrack(track, _localStream!);
        }
      }

      // 2. Bind remote streams & tracks
      _peerConnection?.onTrack = (RTCTrackEvent event) {
        developer.log('📹 [CallScreen] Remote track received: ${event.track.kind}, streams: ${event.streams.length}', name: 'CallScreen');
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          _remoteRenderer.srcObject = _remoteStream;
          if (mounted) {
            setState(() {
              _isConnected = true;
              _connectionStatusText = 'Connected (Live Media)';
            });
          }
        }
      };

      _peerConnection?.onAddStream = (MediaStream stream) {
        developer.log('📹 [CallScreen] Remote stream added: ${stream.id}', name: 'CallScreen');
        _remoteStream = stream;
        _remoteRenderer.srcObject = _remoteStream;
        if (mounted) {
          setState(() {
            _isConnected = true;
            _connectionStatusText = 'Connected (Live Media)';
          });
        }
      };

      // 3. Capture & Broadcast ICE Candidates
      _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null) {
          final candMap = candidate.toMap();
          _localIceCandidatesBuffer.add(candMap);
          _broadcastSignalingMessage(
            signalType: 'ice',
            payload: {
              'from_cit': _myCit,
              'candidate': candMap,
            },
          );
        }
      };

      // 4. Subscriptions to MQTT topics
      if (_callCode != null && _callCode!.isNotEmpty) {
        MQTTService.instance.subscribe('simplysay/call_session/$_callCode/signaling');
      }
      if (_myCit != null) {
        MQTTService.instance.subscribe('simplysay/webrtc/live/ready/$_myCit');
        MQTTService.instance.subscribe('simplysay/webrtc/live/offer/$_myCit');
        MQTTService.instance.subscribe('simplysay/webrtc/live/answer/$_myCit');
        MQTTService.instance.subscribe('simplysay/webrtc/live/ice/$_myCit');
        MQTTService.instance.subscribe('simplysay/webrtc/live/hangup/$_myCit');
        MQTTService.instance.subscribe('simplysay/webrtc/live/bye/$_myCit');
      }

      _mqttSubscription = MQTTService.instance.messageStream.listen(_handleMqttSignalingMessage);

      // 5. Start Negotiation Protocol
      if (!_isCaller) {
        // Callee emits READY ping to let caller know Callee is in CallScreen
        developer.log('👂 [CallScreen] Callee broadcasting READY ping...', name: 'CallScreen');
        _broadcastSignalingMessage(
          signalType: 'ready',
          payload: {
            'from_cit': _myCit,
            'sender_name': _myDisplayName,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        );
      } else {
        // Caller generates and sends SDP Offer with periodic retry
        await _generateAndSendOffer();
        _startOfferRetryLoop();
      }
    } catch (e) {
      developer.log('⚠️ [CallScreen] WebRTC setup error: $e', name: 'CallScreen');
    }
  }

  void _enableSpeakerphone() {
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        Helper.setSpeakerphoneOn(true);
      } catch (e) {
        developer.log('⚠️ Error setting speakerphone: $e', name: 'CallScreen');
      }
    }
  }

  Future<void> _generateAndSendOffer() async {
    if (_peerConnection == null || _isRemoteDescriptionSet) return;
    try {
      final sdpConstraints = <String, dynamic>{
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': true,
        },
        'optional': [],
      };

      final offer = await _peerConnection!.createOffer(sdpConstraints);
      await _peerConnection!.setLocalDescription(offer);

      developer.log('📤 [CallScreen] Caller generated SDP offer (try ${_offerRetryCount + 1})', name: 'CallScreen');
      _broadcastSignalingMessage(
        signalType: 'offer',
        payload: {
          'from_cit': _myCit,
          'sender_name': _myDisplayName,
          'sdp': offer.sdp,
          'type': offer.type,
          'ice_candidates': _localIceCandidatesBuffer,
        },
      );
    } catch (e) {
      developer.log('⚠️ [CallScreen] Error generating SDP offer: $e', name: 'CallScreen');
    }
  }

  void _startOfferRetryLoop() {
    _offerRetryTimer?.cancel();
    _offerRetryTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      if (_isRemoteDescriptionSet || _isConnected || _peerConnection == null) {
        timer.cancel();
        return;
      }
      _offerRetryCount++;
      if (_offerRetryCount > 15) {
        timer.cancel();
        return;
      }
      developer.log('🔄 [CallScreen] Re-transmitting SDP offer (attempt #$_offerRetryCount)...', name: 'CallScreen');
      if (_peerConnection?.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        final localDesc = await _peerConnection?.getLocalDescription();
        if (localDesc != null) {
          _broadcastSignalingMessage(
            signalType: 'offer',
            payload: {
              'from_cit': _myCit,
              'sender_name': _myDisplayName,
              'sdp': localDesc.sdp,
              'type': localDesc.type,
              'ice_candidates': _localIceCandidatesBuffer,
            },
          );
        }
      } else {
        await _generateAndSendOffer();
      }
    });
  }

  /// Broadcasts signaling message over MQTT (shared room & direct topics)
  void _broadcastSignalingMessage({required String signalType, required Map<String, dynamic> payload}) {
    final payloadJson = jsonEncode(payload);

    // 1. Publish to Shared Room Topic
    if (_callCode != null && _callCode!.isNotEmpty) {
      MQTTService.instance.publishMessage(
        'simplysay/call_session/$_callCode/signaling',
        jsonEncode({
          'signal_type': signalType,
          'sender_id': _myCit,
          ...payload,
        }),
      );
    }

    // 2. Publish to Direct Target Peer Topic
    if (_peerCit != null && _peerCit!.isNotEmpty) {
      MQTTService.instance.publishMessage('simplysay/webrtc/live/$signalType/$_peerCit', payloadJson);
    }
  }

  void _handleMqttSignalingMessage(MqttReceivedMessage<MqttMessage> message) {
    try {
      final recMsg = message.payload as MqttPublishMessage;
      final payloadStr = MqttPublishPayload.bytesToStringAsString(recMsg.payload.message);
      final topic = message.topic;
      final data = jsonDecode(payloadStr) as Map<String, dynamic>;

      final fromCit = data['from_cit'] as String? ?? data['sender_id'] as String?;
      if (fromCit == _myCit) return; // Ignore our own broadcast

      if (topic == 'simplysay/call_session/$_callCode/signaling') {
        final signalType = data['signal_type'] as String?;
        if (signalType != null) {
          _processIncomingSignal(signalType, data);
        }
      } else if (topic.startsWith('simplysay/webrtc/live/offer/')) {
        _processIncomingSignal('offer', data);
      } else if (topic.startsWith('simplysay/webrtc/live/answer/')) {
        _processIncomingSignal('answer', data);
      } else if (topic.startsWith('simplysay/webrtc/live/ice/')) {
        _processIncomingSignal('ice', data);
      } else if (topic.startsWith('simplysay/webrtc/live/ready/')) {
        _processIncomingSignal('ready', data);
      } else if (topic.startsWith('simplysay/webrtc/live/hangup/') || topic.startsWith('simplysay/webrtc/live/bye/')) {
        _processIncomingSignal('hangup', data);
      }
    } catch (e) {
      developer.log('⚠️ [CallScreen] Error handling MQTT signaling message: $e', name: 'CallScreen');
    }
  }

  Future<void> _processIncomingSignal(String signalType, Map<String, dynamic> data) async {
    if (_peerConnection == null) return;
    final fromCit = data['from_cit'] as String? ?? data['sender_id'] as String?;

    if (_peerCit == null || _peerCit!.isEmpty) {
      _peerCit = fromCit;
    }

    // Extract remote sender name if provided
    final remoteSenderName = (data['sender_name'] as String?)?.trim();
    if (remoteSenderName != null &&
        remoteSenderName.isNotEmpty &&
        remoteSenderName != 'Host User' &&
        remoteSenderName != 'Peer User' &&
        remoteSenderName != 'Joiner User') {
      if (mounted && _peerName != remoteSenderName) {
        setState(() {
          _peerName = remoteSenderName;
        });
      }
      if (_peerCit != null && _peerCit!.isNotEmpty) {
        DatabaseHelper.instance.savePeer(peerId: _peerCit!, name: remoteSenderName);
      }
    }

    try {
      switch (signalType) {
        case 'hangup':
        case 'bye':
          developer.log('🛑 [CallScreen] Received hangup/bye signal from $fromCit', name: 'CallScreen');
          await _handleHangup(isRemoteInitiated: true);
          break;

        case 'ready':
          developer.log('⚡ [CallScreen] Received READY handshake from peer $fromCit', name: 'CallScreen');
          if (_isCaller && !_isRemoteDescriptionSet) {
            await _generateAndSendOffer();
          }
          break;

        case 'offer':
          final sdp = data['sdp'] as String?;
          final type = data['type'] as String? ?? 'offer';
          if (sdp != null && !_isRemoteDescriptionSet && !_isCaller) {
            developer.log('📥 [CallScreen] Applying received SDP offer from $fromCit', name: 'CallScreen');
            await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, type));
            _isRemoteDescriptionSet = true;
            await _flushPendingIceCandidates();

            // Also ingest bundled ICE candidates in offer
            final initialCandidates = data['ice_candidates'] as List<dynamic>?;
            if (initialCandidates != null) {
              for (final c in initialCandidates) {
                if (c is Map<String, dynamic>) {
                  _addParsedCandidate(c);
                }
              }
            }

            // Generate Answer
            final sdpConstraints = <String, dynamic>{
              'mandatory': {
                'OfferToReceiveAudio': true,
                'OfferToReceiveVideo': true,
              },
              'optional': [],
            };
            final answer = await _peerConnection!.createAnswer(sdpConstraints);
            await _peerConnection!.setLocalDescription(answer);

            developer.log('📤 [CallScreen] Callee sent SDP answer back to $fromCit', name: 'CallScreen');
            _broadcastSignalingMessage(
              signalType: 'answer',
              payload: {
                'from_cit': _myCit,
                'sender_name': _myDisplayName,
                'sdp': answer.sdp,
                'type': answer.type,
                'ice_candidates': _localIceCandidatesBuffer,
              },
            );
          }
          break;

        case 'answer':
          final sdp = data['sdp'] as String?;
          final type = data['type'] as String? ?? 'answer';
          if (sdp != null && !_isRemoteDescriptionSet && _isCaller) {
            developer.log('✅ [CallScreen] Applied received SDP answer from $fromCit', name: 'CallScreen');
            _offerRetryTimer?.cancel();
            await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, type));
            _isRemoteDescriptionSet = true;
            await _flushPendingIceCandidates();

            final initialCandidates = data['ice_candidates'] as List<dynamic>?;
            if (initialCandidates != null) {
              for (final c in initialCandidates) {
                if (c is Map<String, dynamic>) {
                  _addParsedCandidate(c);
                }
              }
            }
          }
          break;

        case 'ice':
          final candMap = data['candidate'] as Map<String, dynamic>?;
          if (candMap != null) {
            _addParsedCandidate(candMap);
          }
          break;
      }
    } catch (e) {
      developer.log('⚠️ [CallScreen] Error processing signal $signalType: $e', name: 'CallScreen');
    }
  }

  /// Handles clean call termination and synchronization
  Future<void> _handleHangup({bool isRemoteInitiated = false}) async {
    if (_isEndingCall) return;
    _isEndingCall = true;

    developer.log('🛑 [CallScreen] Ending call (isRemoteInitiated=$isRemoteInitiated)...', name: 'CallScreen');

    if (!isRemoteInitiated) {
      _broadcastSignalingMessage(
        signalType: 'hangup',
        payload: {
          'from_cit': _myCit,
          'sender_name': _myDisplayName,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
    }

    _offerRetryTimer?.cancel();
    _mqttSubscription?.cancel();

    // Save recent call to database
    if (_peerCit != null && _peerCit!.isNotEmpty) {
      try {
        await DatabaseHelper.instance.savePeer(peerId: _peerCit!, name: _peerName);
      } catch (_) {}
    }

    try {
      _peerConnection?.close();
    } catch (_) {}

    try {
      _localStream?.getTracks().forEach((track) => track.stop());
      _remoteStream?.getTracks().forEach((track) => track.stop());
    } catch (_) {}

    if (mounted) {
      if (isRemoteInitiated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Call ended by peer'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  void _addParsedCandidate(Map<String, dynamic> candMap) async {
    try {
      final candidateStr = candMap['candidate'] as String?;
      final sdpMid = candMap['sdpMid'] as String?;
      final sdpMLineIndex = candMap['sdpMLineIndex'] as int?;

      if (candidateStr != null && _peerConnection != null) {
        final candidate = RTCIceCandidate(candidateStr, sdpMid, sdpMLineIndex);
        if (_isRemoteDescriptionSet) {
          await _peerConnection!.addCandidate(candidate);
          developer.log('❄️ [CallScreen] Added remote ICE candidate', name: 'CallScreen');
        } else {
          _pendingIceCandidates.add(candidate);
          developer.log('⏳ [CallScreen] Queued ICE candidate (waiting for remote SDP)', name: 'CallScreen');
        }
      }
    } catch (e) {
      developer.log('⚠️ [CallScreen] Error adding ICE candidate: $e', name: 'CallScreen');
    }
  }

  Future<void> _flushPendingIceCandidates() async {
    if (_peerConnection == null || _pendingIceCandidates.isEmpty) return;
    developer.log('🔄 [CallScreen] Flushing ${_pendingIceCandidates.length} queued ICE candidates...', name: 'CallScreen');
    for (final candidate in _pendingIceCandidates) {
      try {
        await _peerConnection!.addCandidate(candidate);
      } catch (e) {
        developer.log('⚠️ [CallScreen] Error adding queued candidate: $e', name: 'CallScreen');
      }
    }
    _pendingIceCandidates.clear();
  }

  @override
  void dispose() {
    _offerRetryTimer?.cancel();
    _mqttSubscription?.cancel();
    _peerConnection?.close();
    _localStream?.getTracks().forEach((track) => track.stop());
    _remoteStream?.getTracks().forEach((track) => track.stop());
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callScreenProvider);
    final notifier = ref.read(callScreenProvider.notifier);
    final screenSize = MediaQuery.of(context).size;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && !_isEndingCall) {
          _handleHangup(isRemoteInitiated: false);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // -------------------------------------------------------------------
            // 1. Main Video Background (Remote Peer WebRTC Stream or Avatar Fallback)
            // -------------------------------------------------------------------
            Positioned.fill(
              child: (_isRendererInitialized && _remoteRenderer.srcObject != null)
                  ? RTCVideoView(
                      _remoteRenderer,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : Container(
                      color: const Color(0xFF111318),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 56,
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              child: Text(
                                _peerName.isNotEmpty ? _peerName[0].toUpperCase() : 'P',
                                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _peerName,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!_isConnected) ...[
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Text(
                                  _connectionStatusText,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
            ),

          // Top/Bottom Scrim Gradient Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.75),
                  ],
                  stops: const [0.0, 0.35, 1.0],
                ),
              ),
            ),
          ),

          // -------------------------------------------------------------------
          // 2. Top Overlay: Call Info & Status
          // -------------------------------------------------------------------
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [
                    Text(
                      _peerName,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            blurRadius: 8,
                            color: Colors.black54,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _isConnected ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _isConnected ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isConnected ? callState.formattedDuration : _connectionStatusText,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withValues(alpha: 0.9),
                            shadows: const [
                              Shadow(
                                blurRadius: 4,
                                color: Colors.black45,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // -------------------------------------------------------------------
          // 3. Picture-in-Picture (Local Camera WebRTC Stream)
          // -------------------------------------------------------------------
          Positioned(
            top: callState.pipOffset.dy,
            right: callState.pipOffset.dx,
            child: GestureDetector(
              onPanUpdate: (details) {
                notifier.updatePipPosition(details.delta, screenSize);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 50),
                width: screenSize.width < 600 ? 116 : 148,
                height: screenSize.width < 600 ? 172 : 210,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: (callState.isVideoOff || !_isRendererInitialized || _localRenderer.srcObject == null)
                      ? Container(
                          color: const Color(0xFF23252A),
                          child: const Center(
                            child: Icon(
                              Icons.videocam_off,
                              color: Colors.white54,
                              size: 32,
                            ),
                          ),
                        )
                      : RTCVideoView(
                          _localRenderer,
                          mirror: true,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                ),
              ),
            ),
          ),

          // -------------------------------------------------------------------
          // 4. Bottom Controls Floating Bar
          // -------------------------------------------------------------------
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Mute / Unmute Mic Button
                          _CallControlButton(
                            icon: callState.isMuted ? Icons.mic_off : Icons.mic,
                            isToggled: callState.isMuted,
                            tooltip: callState.isMuted ? 'Unmute' : 'Mute',
                            onPressed: () {
                              final nextMutedState = !callState.isMuted;
                              notifier.toggleMute();
                              _localStream?.getAudioTracks().forEach((track) {
                                track.enabled = !nextMutedState;
                              });
                            },
                          ),
                          const SizedBox(width: 14),

                          // End Call Button
                          _CallControlButton(
                            icon: Icons.call_end,
                            backgroundColor: const Color(0xFFE11D48),
                            iconColor: Colors.white,
                            size: 60,
                            iconSize: 28,
                            tooltip: 'End Call',
                            onPressed: () {
                              _handleHangup(isRemoteInitiated: false);
                            },
                          ),
                          const SizedBox(width: 14),

                          // Video Toggle Button
                          _CallControlButton(
                            icon: callState.isVideoOff ? Icons.videocam_off : Icons.videocam,
                            isToggled: callState.isVideoOff,
                            tooltip: callState.isVideoOff ? 'Turn on video' : 'Turn off video',
                            onPressed: () {
                              final nextVideoOffState = !callState.isVideoOff;
                              notifier.toggleVideo();
                              _localStream?.getVideoTracks().forEach((track) {
                                track.enabled = !nextVideoOffState;
                              });
                              if (!nextVideoOffState && mounted) {
                                setState(() {
                                  _localRenderer.srcObject = _localStream;
                                });
                              }
                            },
                          ),
                          const SizedBox(width: 14),

                          // Switch Camera Button
                          _CallControlButton(
                            icon: Icons.flip_camera_ios,
                            tooltip: 'Switch Camera',
                            onPressed: () {
                              notifier.toggleCamera();
                              if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
                                _localStream?.getVideoTracks().forEach((track) {
                                  Helper.switchCamera(track);
                                });
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Camera switching is supported on mobile devices.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
}

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool isToggled;
  final Color? backgroundColor;
  final Color? iconColor;
  final double size;
  final double iconSize;

  const _CallControlButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.isToggled = false,
    this.backgroundColor,
    this.iconColor,
    this.size = 48,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBgColor = backgroundColor ??
        (isToggled ? Colors.white : Colors.white.withValues(alpha: 0.85));
    final effectiveIconColor = iconColor ?? (isToggled ? Colors.black : const Color(0xFF1A1B1E));

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: effectiveBgColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                icon,
                color: effectiveIconColor,
                size: iconSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
