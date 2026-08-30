import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/native/native_call_bridge.dart';
import 'core/routes/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'database/db_helper.dart';
import 'features/call/presentation/call_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NativeCallBridge.instance.initialize();
  runApp(
    const ProviderScope(
      child: SimplySayApp(),
    ),
  );
}

class SimplySayApp extends ConsumerStatefulWidget {
  final Widget? homeScreen;
  const SimplySayApp({super.key, this.homeScreen});

  @override
  ConsumerState<SimplySayApp> createState() => _SimplySayAppState();
}

class _SimplySayAppState extends ConsumerState<SimplySayApp> {
  StreamSubscription? _callActionSubscription;

  @override
  void initState() {
    super.initState();
    _setupNativeCallListener();
  }

  void _setupNativeCallListener() {
    _callActionSubscription = NativeCallBridge.instance.onCallActionStream.listen((event) async {
      developer.log('⚡ [App Root] Native Call Action received: $event', name: 'SimplySayApp');
      final eventType = event['event'] as String?;
      if (eventType == 'call_accepted') {
        final callCode = event['call_code'] as String? ?? '';
        final callerCit = event['caller_cit'] as String? ?? '';
        final callerName = event['caller_name'] as String? ?? 'Caller';

        final identity = await DatabaseHelper.instance.getClientIdentity();
        final myCit = identity?['cit'] as String? ?? 'user_local';

        appNavigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => CallScreen(
              callCode: callCode,
              peerCit: callerCit,
              peerName: callerName,
              myCit: myCit,
              isCaller: false,
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _callActionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'SimplySay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: widget.homeScreen,
      initialRoute: widget.homeScreen == null ? AppRoutes.login : null,
      routes: widget.homeScreen == null ? AppRoutes.routes : {},
    );
  }
}
