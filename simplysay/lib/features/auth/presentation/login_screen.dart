import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/routes/app_routes.dart';
import 'widgets/brand_header.dart';
import 'widgets/oauth_button.dart';
import 'widgets/social_icons.dart';
import 'widgets/auth_footer.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    void handleLoginSuccess(String providerName) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login successful via $providerName!')),
      );
      Navigator.of(context).pushReplacementNamed(AppRoutes.initialization);
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const BrandHeader(),
            Expanded(
              child: Stack(
                children: [
                  // Main Centered Authentication Section
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OAuthButton(
                            icon: const GoogleLogoWidget(size: 24),
                            label: 'Continue with Google',
                            onPressed: () {
                              handleLoginSuccess('Google');
                            },
                          ),
                          const SizedBox(height: 16),
                          OAuthButton(
                            icon: const MicrosoftLogoWidget(size: 23),
                            label: 'Continue with Microsoft',
                            onPressed: () {
                              handleLoginSuccess('Microsoft');
                            },
                          ),
                          const SizedBox(height: 16),
                          OAuthButton(
                            icon: const MetaLogoWidget(size: 24),
                            label: 'Continue with Meta',
                            onPressed: () {
                              handleLoginSuccess('Meta');
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const AuthFooter(),
          ],
        ),
      ),
    );
  }
}
