import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/routes/app_routes.dart';
import 'providers/instant_call_provider.dart';
import 'widgets/otp_code_boxes.dart';

class InstantCallJoinScreen extends ConsumerWidget {
  const InstantCallJoinScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final joinState = ref.watch(joinCallProvider);
    final joinNotifier = ref.read(joinCallProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Connect to Instant Call'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

              // Hero Header Icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.connect_without_contact_outlined,
                  size: 36,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'Enter Shared Code',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Type or paste the 9-character code provided by the host to start the call.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),

              const SizedBox(height: 36),

              // OTP 9-Box Input Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    OtpCodeBoxesInput(
                      onChanged: (code) {
                        joinNotifier.setCode(code);
                      },
                    ),

                    if (joinState.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        joinState.errorMessage!,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Join Call Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: joinState.isConnecting
                      ? null
                      : () async {
                          final success = await joinNotifier.joinCall();
                          if (success && context.mounted) {
                            final latestJoinState = ref.read(joinCallProvider);
                            final cleanCode = latestJoinState.callCode ?? latestJoinState.code.replaceAll('-', '').trim().toUpperCase();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Connection established! Directing to call...'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                            // Navigate to WebRTC active call screen with peer info
                            Navigator.of(context).pushReplacementNamed(
                              AppRoutes.call,
                              arguments: {
                                'peerName': latestJoinState.hostName,
                                'peerCit': latestJoinState.hostId,
                                'myCit': latestJoinState.myCit,
                                'callCode': cleanCode,
                                'isCaller': false,
                              },
                            );
                          }
                        },
                  icon: joinState.isConnecting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.call, size: 20),
                  label: Text(
                    joinState.isConnecting ? 'Connecting...' : 'Join Call',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
