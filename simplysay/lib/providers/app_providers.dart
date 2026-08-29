import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/webrtc_service.dart';
import '../services/mqtt_service.dart';
import '../services/fcm_service.dart';
import '../services/notification_service.dart';
import '../services/permission_service.dart';
import '../services/p2p_service.dart';
import '../services/auth_service.dart';
import '../database/db_helper.dart';

final dbHelperProvider = Provider<DatabaseHelper>((ref) => DatabaseHelper.instance);

final webRTCServiceProvider = Provider<WebRTCService>((ref) => WebRTCService());

final mqttServiceProvider = Provider<MQTTService>((ref) => MQTTService.instance);

final fcmServiceProvider = Provider<FCMService>((ref) => FCMService.instance);

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());

final permissionServiceProvider = Provider<PermissionService>((ref) => PermissionService());

final p2pServiceProvider = Provider<P2PService>((ref) => P2PService());

final authServiceProvider = Provider<AuthService>((ref) => AuthService());
