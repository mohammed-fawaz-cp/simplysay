import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../database/db_helper.dart';
import '../../../services/fcm_service.dart';
import '../../../services/token_service.dart';
import '../../../services/mqtt_service.dart';
import '../../../services/user_registration_service.dart';
import '../../../services/contact_sync_service.dart';
import '../../../services/peer_profile_exchange_service.dart';
import '../../../services/webrtc_prewarm_service.dart';
import 'widgets/wave_loading_widget.dart';

final initializationProvider = AsyncNotifierProvider<InitializationNotifier, void>(
  InitializationNotifier.new,
);

class InitializationNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    // Initial state is idle until startInitialization is called
  }

  Future<void> startInitialization({
    required BuildContext context,
    required String selectedPhoneNumber,
  }) async {
    final startTime = DateTime.now();
    developer.log('🚀 [InitializationFlow] Starting full 3-Stage Initialization Flow for phone=$selectedPhoneNumber...', name: 'InitializationFlow');
    state = const AsyncValue.loading();
    try {
      // STAGE 1: Initialize Database & Generate Local Identity
      developer.log('⚡ [InitializationFlow] STAGE 1: Initializing SQLite DB and generating device identity...', name: 'InitializationFlow');
      await DatabaseHelper.instance.database;
      final deviceId = await TokenService.instance.getDeviceId();
      final cit = TokenService.instance.generateCIT(deviceId, selectedPhoneNumber);
      final csit = TokenService.instance.generateCSIT(deviceId, cit);

      await DatabaseHelper.instance.saveClientIdentity(
        cit: cit,
        csit: csit,
        deviceId: deviceId,
        phoneNumber: selectedPhoneNumber,
      );

      developer.log('✅ [InitializationFlow] STAGE 1 COMPLETE: Local identity saved (CIT: $cit, CSIT: $csit, DeviceId: $deviceId)', name: 'InitializationFlow');

      // STAGE 2: Register User Identity with FastAPI Server (MUST occur before contact sync)
      developer.log('⚡ [InitializationFlow] STAGE 2: Registering user identity with FastAPI server...', name: 'InitializationFlow');
      final fcmToken = await FCMService.instance.getDeviceToken();
      final registered = await UserRegistrationService.registerUserOnServer(
        rawPhoneNumber: selectedPhoneNumber,
        cit: cit,
        csit: csit,
        deviceId: deviceId,
        fcmToken: fcmToken,
      );
      unawaited(FCMService.instance.syncDeviceToken());

      developer.log('✅ [InitializationFlow] STAGE 2 COMPLETE: Server Registration result=$registered', name: 'InitializationFlow');

      // STAGE 3: Run Background Services in Parallel (MQTT + Isolate Contact Sync + Profile Exchange + WebRTC Pre-warm)
      developer.log('⚡ [InitializationFlow] STAGE 3: Spawning parallel MQTT connection & Background Isolate Contact Sync...', name: 'InitializationFlow');
      await Future.wait([
        MQTTService.instance.initialize(cit: cit),
        ContactSyncService.syncContactsInBackground(),
        PeerProfileExchangeService.instance.initialize(),
        WebRTCPrewarmService.instance.initialize(),
      ]);

      final totalDuration = DateTime.now().difference(startTime).inMilliseconds;
      developer.log('🎉 [InitializationFlow] STAGE 3 COMPLETE: Services initialized successfully in ${totalDuration}ms!', name: 'InitializationFlow');

      state = const AsyncValue.data(null);
    } catch (e, stack) {
      developer.log('❌ [InitializationFlow] ERROR during initialization: $e', name: 'InitializationFlow', error: e, stackTrace: stack);
      state = AsyncValue.error(e, stack);
    }
  }
}

class InitializationScreen extends ConsumerStatefulWidget {
  const InitializationScreen({super.key});

  @override
  ConsumerState<InitializationScreen> createState() => _InitializationScreenState();
}

class _InitializationScreenState extends ConsumerState<InitializationScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runInitializationFlow();
    });
  }

  Future<void> _runInitializationFlow() async {
    developer.log('⚡ [InitializationScreen] Entering _runInitializationFlow...', name: 'InitializationScreen');
    // Check if identity already exists
    final existingIdentity = await DatabaseHelper.instance.getClientIdentity();
    if (existingIdentity != null && mounted) {
      developer.log('✅ [InitializationScreen] Existing client identity found (CIT: ${existingIdentity['cit']}). Initializing P2P listeners...', name: 'InitializationScreen');
      unawaited(FCMService.instance.syncDeviceToken());
      await PeerProfileExchangeService.instance.initialize();
      await WebRTCPrewarmService.instance.initialize();

      final displayName = existingIdentity['display_name'] as String?;
      if (displayName == null || displayName.trim().isEmpty) {
        developer.log('👤 [InitializationScreen] Profile name missing. Navigating to Profile Setup Screen...', name: 'InitializationScreen');
        _navigateToProfileSetup();
      } else {
        developer.log('✅ [InitializationScreen] Profile complete. Navigating to Home Screen...', name: 'InitializationScreen');
        _navigateToHome();
      }
      return;
    }

    // Default auto-detected phone number with country code
    String detectedPhone = '+1234567890';
    developer.log('📱 [InitializationScreen] Prompting user to confirm or enter phone number (Default/SIM: $detectedPhone)...', name: 'InitializationScreen');

    if (!mounted) return;

    // Show Bottom Sheet to confirm / edit phone number
    final confirmedPhone = await showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => _PhoneNumberBottomSheet(
        initialPhone: detectedPhone,
      ),
    );

    final finalPhone = confirmedPhone ?? detectedPhone;
    developer.log('✅ [InitializationScreen] Phone number selected: $finalPhone', name: 'InitializationScreen');

    if (mounted) {
      await ref.read(initializationProvider.notifier).startInitialization(
            context: context,
            selectedPhoneNumber: finalPhone,
          );

      if (mounted) {
        developer.log('🚀 [InitializationScreen] Initialization completed. Navigating to Profile Setup Screen...', name: 'InitializationScreen');
        _navigateToProfileSetup();
      }
    }
  }

  void _navigateToProfileSetup() {
    Navigator.of(context).pushReplacementNamed(AppRoutes.profileSetup);
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacementNamed(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      body: const SafeArea(
        child: WaveLoadingWidget(
          text: 'Initializing...',
        ),
      ),
    );
  }
}

class _PhoneNumberBottomSheet extends StatefulWidget {
  final String initialPhone;

  const _PhoneNumberBottomSheet({required this.initialPhone});

  @override
  State<_PhoneNumberBottomSheet> createState() => _PhoneNumberBottomSheetState();
}

class _PhoneNumberBottomSheetState extends State<_PhoneNumberBottomSheet> {
  late TextEditingController _phoneController;
  late bool _isEditing;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.initialPhone);
    // On Desktop or when SIM number is not auto-detected, default to editable state
    _isEditing = widget.initialPhone.isEmpty || widget.initialPhone == '+1234567890';
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _onConfirm() {
    final input = _phoneController.text.trim();
    if (input.isEmpty || input.length < 5) {
      setState(() {
        _errorText = 'Please enter a valid phone number (e.g. +1234567890)';
      });
      return;
    }
    Navigator.of(context).pop(input);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDefaultOrEmpty = widget.initialPhone.isEmpty || widget.initialPhone == '+1234567890';

    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[700] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isDefaultOrEmpty ? 'Enter Your Phone Number' : 'Confirm Phone Number',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            isDefaultOrEmpty
                ? 'No SIM card detected. Please enter your mobile phone number (including country code, e.g. +1234567890) to generate your Client Identity Token (CIT).'
                : 'Your device phone number (including country code) will be used to generate your secure Client Identity Token (CIT).',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _phoneController,
            enabled: _isEditing,
            keyboardType: TextInputType.phone,
            onChanged: (_) {
              if (_errorText != null) {
                setState(() {
                  _errorText = null;
                });
              }
            },
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
            decoration: InputDecoration(
              labelText: 'Phone Number (with Country Code)',
              hintText: '+1234567890',
              errorText: _errorText,
              prefixIcon: const Icon(Icons.phone),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              if (!isDefaultOrEmpty) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _isEditing = !_isEditing;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(_isEditing ? 'Lock' : 'Modify'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: ElevatedButton(
                  onPressed: _onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Confirm'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
