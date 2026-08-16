import 'package:flutter/material.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/initialization/presentation/initialization_screen.dart';
import '../../features/profile/presentation/profile_setup_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/call/presentation/call_screen.dart';

import '../../features/call/presentation/instant_call_host_screen.dart';
import '../../features/call/presentation/instant_call_join_screen.dart';

/// Centralized Named Routes configuration for SimplySay app.
class AppRoutes {
  AppRoutes._();

  static const String login = '/';
  static const String initialization = '/initialization';
  static const String profileSetup = '/profile-setup';
  static const String home = '/home';
  static const String settings = '/settings';
  static const String call = '/call';
  static const String instantCallHost = '/instant-call-host';
  static const String instantCallJoin = '/instant-call-join';

  static Map<String, WidgetBuilder> get routes => {
        login: (context) => const LoginScreen(),
        initialization: (context) => const InitializationScreen(),
        profileSetup: (context) => const ProfileSetupScreen(),
        home: (context) => const HomeScreen(),
        settings: (context) => const SettingsScreen(),
        call: (context) => const CallScreen(),
        instantCallHost: (context) => const InstantCallHostScreen(),
        instantCallJoin: (context) => const InstantCallJoinScreen(),
      };
}
