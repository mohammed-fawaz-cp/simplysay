import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CallScreenState {
  final bool isMuted;
  final bool isVideoOff;
  final bool isFrontCamera;
  final int durationSeconds;
  final String peerName;
  final String peerPhoneNumber;
  final Offset pipOffset;

  const CallScreenState({
    this.isMuted = false,
    this.isVideoOff = false,
    this.isFrontCamera = true,
    this.durationSeconds = 0,
    this.peerName = 'Alex Johnson',
    this.peerPhoneNumber = '+1 555-0199',
    this.pipOffset = const Offset(16, 24),
  });

  CallScreenState copyWith({
    bool? isMuted,
    bool? isVideoOff,
    bool? isFrontCamera,
    int? durationSeconds,
    String? peerName,
    String? peerPhoneNumber,
    Offset? pipOffset,
  }) {
    return CallScreenState(
      isMuted: isMuted ?? this.isMuted,
      isVideoOff: isVideoOff ?? this.isVideoOff,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      peerName: peerName ?? this.peerName,
      peerPhoneNumber: peerPhoneNumber ?? this.peerPhoneNumber,
      pipOffset: pipOffset ?? this.pipOffset,
    );
  }

  String get formattedDuration {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class CallScreenNotifier extends StateNotifier<CallScreenState> {
  Timer? _timer;

  CallScreenNotifier({String? name, String? phone})
      : super(CallScreenState(
          peerName: name ?? 'Peer User',
          peerPhoneNumber: phone ?? '',
          durationSeconds: 0,
        )) {
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        state = state.copyWith(durationSeconds: state.durationSeconds + 1);
      }
    });
  }

  void toggleMute() {
    state = state.copyWith(isMuted: !state.isMuted);
  }

  void toggleVideo() {
    state = state.copyWith(isVideoOff: !state.isVideoOff);
  }

  void toggleCamera() {
    state = state.copyWith(isFrontCamera: !state.isFrontCamera);
  }

  void updatePipPosition(Offset delta, Size screenSize) {
    final double newX = (state.pipOffset.dx - delta.dx).clamp(12.0, screenSize.width - 140.0);
    final double newY = (state.pipOffset.dy + delta.dy).clamp(16.0, screenSize.height - 240.0);
    state = state.copyWith(pipOffset: Offset(newX, newY));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final callScreenProvider =
    StateNotifierProvider.autoDispose<CallScreenNotifier, CallScreenState>((ref) {
  return CallScreenNotifier();
});
