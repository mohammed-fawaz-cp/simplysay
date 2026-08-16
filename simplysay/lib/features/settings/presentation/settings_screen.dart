import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../database/db_helper.dart';
import '../../home/presentation/providers/recent_calls_provider.dart';

/// Riverpod provider for user settings profile data from SQLite
final settingsProfileProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  return await DatabaseHelper.instance.getClientIdentity();
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final profileAsync = ref.watch(settingsProfileProvider);

    // Color definitions based on HTML specification
    final surfaceColor = theme.colorScheme.surface;
    final primaryColor = theme.colorScheme.primary;
    final onSurfaceColor = theme.colorScheme.onSurface;
    final subtitleColor = theme.colorScheme.outline;
    final cardBgColor = theme.colorScheme.surfaceContainerLowest;
    final errorColor = theme.colorScheme.error;

    return Scaffold(
      backgroundColor: surfaceColor,
      appBar: AppBar(
        backgroundColor: surfaceColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: primaryColor),
          onPressed: () {
            // Switch to Call tab if inside IndexedStack, or pop if navigated as route
            ref.read(activeTabProvider.notifier).state = 0;
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text(
          'Settings',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: primaryColor,
          ),
        ),
        centerTitle: true,
        // actions: [
        //   PopupMenuButton<String>(
        //     icon: Icon(Icons.more_vert, color: theme.colorScheme.onSurfaceVariant),
        //     onSelected: (value) {
        //       if (value == 'refresh') {
        //         ref.invalidate(settingsProfileProvider);
        //       } else if (value == 'about') {
        //         showAboutDialog(
        //           context: context,
        //           applicationName: 'SimplySay',
        //           applicationVersion: '1.0.0',
        //           applicationIcon: Icon(Icons.forum, size: 48, color: primaryColor),
        //           children: [
        //             const Text('SimplySay is a secure, end-to-end encrypted direct peer-to-peer communication platform.'),
        //           ],
        //         );
        //       }
        //     },
        //     itemBuilder: (context) => [
        //       const PopupMenuItem(value: 'refresh', child: Text('Refresh Profile')),
        //       const PopupMenuItem(value: 'about', child: Text('About SimplySay')),
        //     ],
        //   ),
        // ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // -------------------------------------------------------------
                // Profile Section
                // -------------------------------------------------------------
                profileAsync.when(
                  data: (identity) {
                    final displayName = (identity?['display_name'] as String?) ?? 'Alex Johnson';
                    final imageB64 = identity?['profile_image_base64'] as String?;
                    Uint8List? imageBytes;
                    if (imageB64 != null && imageB64.isNotEmpty) {
                      try {
                        imageBytes = base64Decode(imageB64);
                      } catch (_) {}
                    }

                    return Column(
                      children: [
                        // Avatar with Edit FAB
                        Stack(
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.colorScheme.surfaceContainerHigh,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: imageBytes != null
                                    ? Image.memory(
                                        imageBytes,
                                        width: 96,
                                        height: 96,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                          color: theme.colorScheme.primaryContainer,
                                          child: Icon(
                                            Icons.person,
                                            size: 48,
                                            color: theme.colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(context).pushNamed(AppRoutes.profileSetup);
                                },
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.15),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.edit,
                                    size: 18,
                                    color: theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Editable Name
                        InkWell(
                          onTap: () {
                            Navigator.of(context).pushNamed(AppRoutes.profileSetup);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  displayName,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                    color: onSurfaceColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.edit,
                                  size: 20,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => Column(
                    children: [
                      const CircleAvatar(
                        radius: 48,
                        child: Icon(Icons.person, size: 48),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No name',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: onSurfaceColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // -------------------------------------------------------------
                // Phone Verification Card
                // -------------------------------------------------------------
                // Container(
                //   decoration: BoxDecoration(
                //     color: cardBgColor,
                //     borderRadius: BorderRadius.circular(16),
                //    // border: Border.all(color: borderColor),
                //     boxShadow: [
                //       BoxShadow(
                //         color: Colors.black.withValues(alpha: 0.02),
                //         blurRadius: 4,
                //         offset: const Offset(0, 2),
                //       ),
                //     ],
                //   ),
                //   padding: const EdgeInsets.all(16),
                //   child: LayoutBuilder(
                //     builder: (context, constraints) {
                //       final isMobile = constraints.maxWidth < 600;
                //       final cardContent = Row(
                //         children: [
                //           Container(
                //             width: 40,
                //             height: 40,
                //             decoration: BoxDecoration(
                //               color: errorContainerColor,
                //               shape: BoxShape.circle,
                //             ),
                //             child: Icon(
                //               Icons.warning,
                //               color: onErrorContainerColor,
                //               size: 22,
                //             ),
                //           ),
                //           const SizedBox(width: 12),
                //           Expanded(
                //             child: Column(
                //               crossAxisAlignment: CrossAxisAlignment.start,
                //               children: [
                //                 Text(
                //                   'Verify your phone number',
                //                   style: TextStyle(
                //                     fontFamily: 'Inter',
                //                     fontSize: 18,
                //                     fontWeight: FontWeight.w500,
                //                     color: onSurfaceColor,
                //                   ),
                //                 ),
                //                 const SizedBox(height: 2),
                //                 Text(
                //                   'Required to connect with contacts.',
                //                   style: TextStyle(
                //                     fontFamily: 'Inter',
                //                     fontSize: 14,
                //                     color: subtitleColor,
                //                   ),
                //                 ),
                //               ],
                //             ),
                //           ),
                //         ],
                //       );

                //       final verifyButton = ElevatedButton(
                //         onPressed: () {
                //           ScaffoldMessenger.of(context).showSnackBar(
                //             const SnackBar(
                //               content: Text('Phone verification code sent via SMS.'),
                //             ),
                //           );
                //         },
                //         style: ElevatedButton.styleFrom(
                //           backgroundColor: primaryColor,
                //           foregroundColor: Colors.white,
                //           elevation: 0,
                //           padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                //           shape: RoundedRectangleBorder(
                //             borderRadius: BorderRadius.circular(999),
                //           ),
                //         ),
                //         child: const Text(
                //           'Verify',
                //           style: TextStyle(
                //             fontFamily: 'Inter',
                //             fontSize: 16,
                //             fontWeight: FontWeight.w500,
                //           ),
                //         ),
                //       );

                //       if (isMobile) {
                //         return Column(
                //           crossAxisAlignment: CrossAxisAlignment.stretch,
                //           children: [
                //             cardContent,
                //             const SizedBox(height: 16),
                //             verifyButton,
                //           ],
                //         );
                //       } else {
                //         return Row(
                //           children: [
                //             Expanded(child: cardContent),
                //             const SizedBox(width: 16),
                //             verifyButton,
                //           ],
                //         );
                //       }
                //     },
                //   ),
                // ),
                // const SizedBox(height: 32),

                // -------------------------------------------------------------
                // Settings Options List Card
                // -------------------------------------------------------------
                Container(
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(16),
                   // border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      // Notifications
                      _buildSettingsTile(
                        context: context,
                        icon: Icons.notifications_outlined,
                        title: 'Notifications',
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Notifications settings updated.')),
                          );
                        },
                      ),
                     // Divider(height: 1, color: borderColor.withValues(alpha: 0.5)),

                      // Privacy
                      _buildSettingsTile(
                        context: context,
                        icon: Icons.lock_outlined,
                        title: 'Privacy',
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Privacy & Security settings.')),
                          );
                        },
                      ),
                     // Divider(height: 1, color: borderColor.withValues(alpha: 0.5)),

                      // Linked Devices
                      _buildSettingsTile(
                        context: context,
                        icon: Icons.devices_outlined,
                        title: 'Linked Devices',
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Linked Devices view.')),
                          );
                        },
                      ),
                    //  Divider(height: 1, color: borderColor.withValues(alpha: 0.5)),

                      // Dark Mode Theme Toggle
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Icon(
                          isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                          color: subtitleColor,
                        ),
                        title: Text(
                          'Dark Mode',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            color: onSurfaceColor,
                          ),
                        ),
                        trailing: Switch(
                          value: isDark,
                          activeTrackColor: primaryColor,
                          onChanged: (val) {
                            ref.read(themeModeProvider.notifier).state =
                                val ? ThemeMode.dark : ThemeMode.light;
                          },
                        ),
                      ),
                      //Divider(height: 1, color: borderColor.withValues(alpha: 0.5)),

                      // Help
                      _buildSettingsTile(
                        context: context,
                        icon: Icons.help_outline,
                        title: 'Help',
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Help & Support center.')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // -------------------------------------------------------------
                // Logout Action
                // -------------------------------------------------------------
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Log Out'),
                          content: const Text('Are you sure you want to log out of SimplySay?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                Navigator.of(context).pushReplacementNamed(AppRoutes.login);
                              },
                              style: TextButton.styleFrom(foregroundColor: errorColor),
                              child: const Text('Log Out'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: Icon(Icons.logout, color: errorColor),
                    label: Text(
                      'Log Out',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: errorColor,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: theme.colorScheme.outline),
      title: Text(
        title,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          color: theme.colorScheme.onSurface,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
