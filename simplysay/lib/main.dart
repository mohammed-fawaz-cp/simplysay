import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'core/native/native_call_bridge.dart';
import 'core/routes/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'database/db_helper.dart';
import 'features/call/presentation/call_screen.dart';
import 'services/call_signaling_service.dart';
import 'services/fcm_service.dart';
import 'services/mqtt_service.dart';
import 'services/notification_service.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  NativeCallBridge.instance.initialize();
  await NotificationService().initialize();
  await FCMService.instance.initialize();
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
    CallSignalingService.instance.initGlobalIncomingCallListener();
  }

  void _setupNativeCallListener() {
    _callActionSubscription = NativeCallBridge.instance.onCallActionStream.listen((event) async {
      developer.log('⚡ [App Root] Native Call Action received: $event', name: 'SimplySayApp');
      final eventType = event['event'] as String?;
      if (eventType == 'call_accepted') {
        final callType = event['call_type'] as String? ?? 'video';
        final callCode = event['call_code'] as String? ?? '';
        final callerCit = event['caller_cit'] as String? ?? '';
        final callerName = event['caller_name'] as String? ?? 'Caller';

        final identity = await DatabaseHelper.instance.getClientIdentity();
        final myCit = identity?['cit'] as String? ?? 'user_local';

        if (callType == 'instant_call') {
          MQTTService.instance.publishMessage(
            'simplysay/instant_call/$callCode',
            jsonEncode({
              'type': 'CALL_ACCEPTED',
              'host_id': myCit,
              'host_name': identity?['display_name'] ?? 'Host',
              'call_code': callCode,
            }),
            qos: MqttQos.atLeastOnce,
          );
        }

        if (CallSignalingService.instance.isCallActive) {
          developer.log('⚡ [App Root] Call already active, ignoring duplicate route push', name: 'SimplySayApp');
          return;
        }

        appNavigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => CallScreen(
              callCode: callCode,
              peerCit: callerCit,
              peerName: callerName,
              myCit: myCit,
              isCaller: callType == 'instant_call',
            ),
          ),
        );
      } else if (eventType == 'call_declined') {
        final callCode = event['call_code'] as String? ?? '';
        final callerCit = event['caller_cit'] as String? ?? '';
        developer.log('⚡ [App Root] Call declined via native notification (code=$callCode, caller=$callerCit)', name: 'SimplySayApp');
        await NativeCallBridge.instance.dismissIncomingCall();
        if (callCode.isNotEmpty || callerCit.isNotEmpty) {
          await CallSignalingService.instance.declineDirectCall(
            callCode: callCode,
            callerCit: callerCit,
          );
        }
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
