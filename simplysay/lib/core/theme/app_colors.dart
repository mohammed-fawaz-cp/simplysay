import 'package:flutter/material.dart';

/// Design tokens extracted directly from design theory files:
/// - simplysay-theme-light.txt
/// - simplysay-theme-dark.txt
abstract class AppColors {
  // ================= LIGHT THEME =================
  static const lightPrimary = Color(0xFF004492);
  static const lightPrimaryContainer = Color(0xFF005BBF);
  static const lightOnPrimary = Color(0xFFFFFFFF);
  static const lightSecondary = Color(0xFF006E2C);
  static const lightSecondaryContainer = Color(0xFF97F4A2);
  static const lightBackground = Color(0xFFFAF9FD);
  static const lightSurface = Color(0xFFFAF9FD);
  static const lightSurfaceContainer = Color(0xFFEFEDF1);
  static const lightSurfaceContainerHigh = Color(0xFFE9E7EB);
  static const lightOnSurface = Color(0xFF1A1B1E);
  static const lightOnSurfaceVariant = Color(0xFF414754);
  static const lightOutline = Color(0xFF727784);
  static const lightError = Color(0xFFBA1A1A);

  // ================= DARK THEME =================
  static const darkPrimary = Color(0xFFFFB3B1);
  static const darkPrimaryContainer = Color(0xFFFF535A);
  static const darkOnPrimary = Color(0xFF680011);
  static const darkSecondary = Color(0xFFC8C6C6);
  static const darkSecondaryContainer = Color(0xFF474747);
  static const darkBackground = Color(0xFF131313);
  static const darkSurface = Color(0xFF131313);
  static const darkSurfaceContainer = Color(0xFF201F1F);
  static const darkSurfaceContainerHigh = Color(0xFF2A2A2A);
  static const darkOnSurface = Color(0xFFE5E2E1);
  static const darkOnSurfaceVariant = Color(0xFFE4BDBC);
  static const darkOutline = Color(0xFFAB8887);
  static const darkError = Color(0xFFFFB4AB);
}
