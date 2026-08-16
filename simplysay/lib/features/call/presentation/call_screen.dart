import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mqtt_client/mqtt_client.dart';
import '../../../database/db_helper.dart';
import '../../../services/mqtt_service.dart';
import '../../../services/webrtc_service.dart';
import 'providers/call_screen_provider.dart';


class CallScreen extends ConsumerStatefulWidget {
  final String? peerName;
  final String? peerPhone;

  const CallScreen({
    super.key,
    this.peerName,
    this.peerPhone,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  RTCPeerConnection? _peerConnection;
  StreamSubscription? _mqttSubscription;
  bool _isRendererInitialized = false;
  String? _myCit;
  String? _peerCit;

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
      await _startLocalCamera();
      await _initWebRTC();
    } catch (e) {
      debugPrint('⚠️ Error initializing WebRTC call session: $e');
    }
  }

  Future<void> _startLocalCamera() async {
    try {
      final mediaConstraints = <String, dynamic>{
        'audio': true,
        'video': {
          'facingMode': 'user',
        },
      };
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      if (mounted) {
        setState(() {
          _localRenderer.srcObject = _localStream;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Error capturing local camera stream: $e');
    }
  }

  Future<void> _initWebRTC() async {
    try {
      final identity = await DatabaseHelper.instance.getClientIdentity();
      _myCit = identity?['cit'] as String?;

      final peers = await DatabaseHelper.instance.getPeers();
      if (peers.isNotEmpty) {
        _peerCit = peers.first['peer_id'] as String?;
      }

      if (_myCit == null) return;

      _peerConnection = await createPeerConnection(WebRTCService.rtcConfiguration);

      // 1. Add local audio & video tracks to PeerConnection
      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          await _peerConnection?.addTrack(track, _localStream!);
        }
      }

      // 2. Bind remote stream to _remoteRenderer
      _peerConnection?.onTrack = (RTCTrackEvent event) {
        developer.log('📹 [CallScreen] Remote track received: ${event.track.kind}', name: 'CallScreen');
        if (event.streams.isNotEmpty && mounted) {
          setState(() {
            _remoteRenderer.srcObject = event.streams[0];
          });
        }
      };

      _peerConnection?.onAddStream = (MediaStream stream) {
        developer.log('📹 [CallScreen] Remote stream added', name: 'CallScreen');
        if (mounted) {
          setState(() {
            _remoteRenderer.srcObject = stream;
          });
        }
      };

      // 3. Emit ICE candidates over MQTT
      _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null && _peerCit != null) {
          final payload = jsonEncode({
            'from_cit': _myCit,
            'candidate': candidate.toMap(),
          });
          MQTTService.instance.publishMessage('simplysay/webrtc/ice/$_peerCit', payload);
        }
      };

      // 4. Subscribe to MQTT topics for WebRTC signaling
      MQTTService.instance.subscribe('simplysay/webrtc/offer/$_myCit');
      MQTTService.instance.subscribe('simplysay/webrtc/answer/$_myCit');
      MQTTService.instance.subscribe('simplysay/webrtc/ice/$_myCit');

      _mqttSubscription = MQTTService.instance.messageStream.listen(_handleSignalingMessage);

      // 5. If I have a peer CIT, generate and send SDP Offer
      if (_peerCit != null) {
        final offer = await _peerConnection!.createOffer();
        await _peerConnection!.setLocalDescription(offer);
        final offerPayload = jsonEncode({
          'from_cit': _myCit,
          'sdp': offer.sdp,
          'type': offer.type,
        });
        MQTTService.instance.publishMessage('simplysay/webrtc/offer/$_peerCit', offerPayload);
        developer.log('📤 [CallScreen] Sent SDP offer to $_peerCit', name: 'CallScreen');
      }
    } catch (e) {
      developer.log('⚠️ [CallScreen] WebRTC setup error: $e', name: 'CallScreen');
    }
  }

  Future<void> _handleSignalingMessage(MqttReceivedMessage<MqttMessage> message) async {
    final recMsg = message.payload as MqttPublishMessage;
    final payloadStr = MqttPublishPayload.bytesToStringAsString(recMsg.payload.message);
    final topic = message.topic;

    try {
      final data = jsonDecode(payloadStr) as Map<String, dynamic>;
      final fromCit = data['from_cit'] as String?;

      if (topic == 'simplysay/webrtc/offer/$_myCit' && _peerConnection != null) {
        final sdp = data['sdp'] as String?;
        final type = data['type'] as String?;
        if (sdp != null && type != null) {
          await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, type));
          final answer = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(answer);
          if (fromCit != null) {
            MQTTService.instance.publishMessage(
              'simplysay/webrtc/answer/$fromCit',
              jsonEncode({'from_cit': _myCit, 'sdp': answer.sdp, 'type': answer.type}),
            );
            developer.log('📤 [CallScreen] Sent SDP answer to $fromCit', name: 'CallScreen');
          }
        }
      } else if (topic == 'simplysay/webrtc/answer/$_myCit' && _peerConnection != null) {
        final sdp = data['sdp'] as String?;
        final type = data['type'] as String?;
        if (sdp != null && type != null) {
          await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, type));
          developer.log('✅ [CallScreen] Applied remote SDP answer', name: 'CallScreen');
        }
      } else if (topic == 'simplysay/webrtc/ice/$_myCit' && _peerConnection != null) {
        final candMap = data['candidate'] as Map<String, dynamic>?;
        if (candMap != null) {
          final candidate = RTCIceCandidate(
            candMap['candidate'],
            candMap['sdpMid'],
            candMap['sdpMLineIndex'],
          );
          await _peerConnection!.addCandidate(candidate);
          developer.log('✅ [CallScreen] Added remote ICE candidate', name: 'CallScreen');
        }
      }
    } catch (e) {
      developer.log('⚠️ [CallScreen] Error handling WebRTC message: $e', name: 'CallScreen');
    }
  }

  @override
  void dispose() {
    _mqttSubscription?.cancel();
    _peerConnection?.close();
    _localStream?.getTracks().forEach((track) => track.stop());
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final String resolvedPeerName = widget.peerName ?? args?['peerName'] as String? ?? 'Peer User';
    final callState = ref.watch(callScreenProvider);
    final notifier = ref.read(callScreenProvider.notifier);
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
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
                    color: const Color(0xFF1A1B1E),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 60,
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            child: Text(
                              resolvedPeerName.isNotEmpty ? resolvedPeerName[0].toUpperCase() : 'P',
                              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            resolvedPeerName,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'WebRTC Live Media Stream Active',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

          // Top/Bottom Scrim Gradient Overlay for Text Readability
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.5),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ),

          // -------------------------------------------------------------------
          // 2. Top Overlay: Call Info (Recipient Name & Pulsing Timer)
          // -------------------------------------------------------------------
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  children: [
                    Text(
                      resolvedPeerName,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
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
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF6DDD81),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF6DDD81),
                                blurRadius: 6,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          callState.formattedDuration,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
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
                width: screenSize.width < 600 ? 128 : 160,
                height: screenSize.width < 600 ? 192 : 230,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: (callState.isVideoOff || !_isRendererInitialized || _localRenderer.srcObject == null)
                      ? Container(
                          color: const Color(0xFF2F3033),
                          child: const Center(
                            child: Icon(
                              Icons.videocam_off,
                              color: Colors.white54,
                              size: 36,
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
          // 4. Bottom Controls Floating Glassmorphism Bar
          // -------------------------------------------------------------------
          Positioned(
            bottom: 36,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                              notifier.toggleMute();
                              _localStream?.getAudioTracks().forEach((track) {
                                track.enabled = !callState.isMuted;
                              });
                            },
                          ),
                          const SizedBox(width: 16),

                          // End Call Button (Distinct Red)
                          _CallControlButton(
                            icon: Icons.call_end,
                            backgroundColor: const Color(0xFFD93025),
                            iconColor: Colors.white,
                            size: 64,
                            iconSize: 32,
                            tooltip: 'End Call',
                            onPressed: () {
                              if (Navigator.of(context).canPop()) {
                                Navigator.of(context).pop();
                              }
                            },
                          ),
                          const SizedBox(width: 16),

                          // Video Toggle Button
                          _CallControlButton(
                            icon: callState.isVideoOff ? Icons.videocam_off : Icons.videocam,
                            isToggled: callState.isVideoOff,
                            tooltip: callState.isVideoOff ? 'Turn on video' : 'Turn off video',
                            onPressed: () {
                              notifier.toggleVideo();
                              _localStream?.getVideoTracks().forEach((track) {
                                track.enabled = !callState.isVideoOff;
                              });
                            },
                          ),
                          const SizedBox(width: 16),

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
    this.size = 52,
    this.iconSize = 26,
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
