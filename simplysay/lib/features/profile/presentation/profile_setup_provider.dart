import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../database/db_helper.dart';

/// Immutable State for Profile Setup
class ProfileSetupState {
  final Uint8List? imageBytes;
  final String? imageBase64;
  final bool isSaving;
  final bool isHoveringAvatar;
  final String? errorMessage;

  const ProfileSetupState({
    this.imageBytes,
    this.imageBase64,
    this.isSaving = false,
    this.isHoveringAvatar = false,
    this.errorMessage,
  });

  ProfileSetupState copyWith({
    Uint8List? imageBytes,
    String? imageBase64,
    bool? isSaving,
    bool? isHoveringAvatar,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ProfileSetupState(
      imageBytes: imageBytes ?? this.imageBytes,
      imageBase64: imageBase64 ?? this.imageBase64,
      isSaving: isSaving ?? this.isSaving,
      isHoveringAvatar: isHoveringAvatar ?? this.isHoveringAvatar,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class ProfileSetupNotifier extends StateNotifier<ProfileSetupState> {
  ProfileSetupNotifier() : super(const ProfileSetupState()) {
    loadExistingProfile();
  }

  final ImagePicker _picker = ImagePicker();

  Future<void> loadExistingProfile() async {
    try {
      final identity = await DatabaseHelper.instance.getClientIdentity();
      if (identity != null) {
        final b64 = identity['profile_image_base64'] as String?;
        if (b64 != null && b64.isNotEmpty) {
          state = state.copyWith(
            imageBase64: b64,
            imageBytes: base64Decode(b64),
          );
        }
      }
    } catch (e) {
      developer.log('⚠️ [ProfileSetupNotifier] Error loading profile: $e', name: 'ProfileSetupNotifier');
    }
  }

  Future<void> pickImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        final b64 = base64Encode(bytes);
        state = state.copyWith(
          imageBytes: bytes,
          imageBase64: b64,
          clearError: true,
        );
        developer.log('📸 [ProfileSetupNotifier] Picked image (${bytes.length} bytes)', name: 'ProfileSetupNotifier');
      }
    } catch (e) {
      developer.log('⚠️ [ProfileSetupNotifier] Error picking image: $e', name: 'ProfileSetupNotifier');
      state = state.copyWith(errorMessage: 'Could not access image source: $e');
    }
  }

  void setHovering(bool isHovering) {
    if (state.isHoveringAvatar == isHovering) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        state = state.copyWith(isHoveringAvatar: isHovering);
      }
    });
  }

  Future<bool> saveProfile({required String name, required BuildContext context}) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      state = state.copyWith(errorMessage: 'Please enter your name');
      return false;
    }

    state = state.copyWith(isSaving: true, clearError: true);

    try {
      developer.log('⚡ [ProfileSetupNotifier] Saving profile (name=$trimmedName)...', name: 'ProfileSetupNotifier');
      await DatabaseHelper.instance.updateUserProfile(
        displayName: trimmedName,
        profileImageBase64: state.imageBase64,
      );

      developer.log('✅ [ProfileSetupNotifier] Profile saved successfully.', name: 'ProfileSetupNotifier');
      return true;
    } catch (e) {
      developer.log('❌ [ProfileSetupNotifier] Error saving profile: $e', name: 'ProfileSetupNotifier');
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Failed to save profile: $e',
      );
      return false;
    }
  }
}

final profileSetupProvider = StateNotifierProvider.autoDispose<ProfileSetupNotifier, ProfileSetupState>(
  (ref) => ProfileSetupNotifier(),
);
