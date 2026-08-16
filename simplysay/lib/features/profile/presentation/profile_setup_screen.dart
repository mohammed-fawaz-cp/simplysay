import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import 'profile_setup_provider.dart';

/// ProfileSetupScreen: Clean ConsumerWidget built strictly with Riverpod.
/// Matches the exact HTML design specification with pill inputs, custom avatar hover overlay, and (+) FAB button.
class ProfileSetupScreen extends ConsumerWidget {
  const ProfileSetupScreen({super.key});

  void _showImageSourcePicker(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final notifier = ref.read(profileSetupProvider.notifier);

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF201F1F) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Select Profile Photo',
                style: TextStyle(
                  color: isDark ? Colors.white : AppColors.lightOnSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.lightPrimaryContainer,
                  child: const Icon(Icons.camera_alt, color: Colors.white),
                ),
                title: Text(
                  'Take Photo',
                  style: TextStyle(color: isDark ? Colors.white : AppColors.lightOnSurface),
                ),
                subtitle: Text(
                  'Capture using camera',
                  style: TextStyle(color: isDark ? Colors.white60 : AppColors.lightOnSurfaceVariant),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  notifier.pickImage(ImageSource.camera);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF86F898),
                  child: Icon(Icons.photo_library, color: Color(0xFF005320)),
                ),
                title: Text(
                  'Choose from Gallery',
                  style: TextStyle(color: isDark ? Colors.white : AppColors.lightOnSurface),
                ),
                subtitle: Text(
                  'Pick from device photos',
                  style: TextStyle(color: isDark ? Colors.white60 : AppColors.lightOnSurfaceVariant),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  notifier.pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(profileSetupProvider);
    final notifier = ref.read(profileSetupProvider.notifier);
    final nameController = TextEditingController();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final cardColor = isDark ? AppColors.darkSurfaceContainer : Colors.white;
    final textColor = isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface;
    final subtitleColor = isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant;
    final inputBgColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF1F3F4);
    final primaryColor = isDark ? const Color(0xFF1A73E8) : AppColors.lightPrimaryContainer;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Header Text
                Text(
                  'Set up your profile',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: Text(
                    'Add a photo and name so friends can recognize you.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      color: subtitleColor,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
            
                // Avatar Upload Container (matching HTML specs)
                InkWell(
                  onTap: () => _showImageSourcePicker(context, ref),
                  onHover: (hovering) => notifier.setHovering(hovering),
                  customBorder: const CircleBorder(),
                  child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 128,
                          height: 128,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark ? const Color(0xFF2A2A2A) : AppColors.lightSurfaceContainerHigh,
                            border: Border.all(
                              color: cardColor,
                              width: 4,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (state.imageBytes != null)
                                  Image.memory(
                                    state.imageBytes!,
                                    fit: BoxFit.cover,
                                  )
                                else
                                  Center(
                                    child: Icon(
                                      Icons.person,
                                      size: 56,
                                      color: isDark ? Colors.white38 : AppColors.lightOutline.withValues(alpha: 0.5),
                                    ),
                                  ),
                                // Hover / Tap Camera Overlay
                                if (state.isHoveringAvatar)
                                  Container(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    child: const Icon(
                                      Icons.photo_camera,
                                      size: 32,
                                      color: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        // FAB (+) icon at bottom right of avatar
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: primaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: cardColor,
                                width: 2,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x1F000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.add,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 40),
            
                // Full Name Pill Input Field
                Container(
                  decoration: BoxDecoration(
                    color: inputBgColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: TextField(
                    controller: nameController,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      color: textColor,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Your Full Name',
                      hintStyle: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        color: isDark ? Colors.white38 : AppColors.lightOutline,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                  ),
                ),
            
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    state.errorMessage!,
                    style: const TextStyle(
                      color: AppColors.lightError,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
            
                const SizedBox(height: 40),
            
                // Continue Button (Pill shape with arrow_forward)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: state.isSaving
                        ? null
                        : () async {
                            final success = await notifier.saveProfile(
                              name: nameController.text,
                              context: context,
                            );
                            if (success && context.mounted) {
                              Navigator.of(context).pushReplacementNamed(AppRoutes.home);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: Colors.black.withValues(alpha: 0.15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: state.isSaving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Continue',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward,
                                size: 20,
                                color: Colors.white,
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
