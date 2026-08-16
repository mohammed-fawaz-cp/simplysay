import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// TokenService generates and manages:
/// 1. Device ID
/// 2. CIT (Client Identification Token) -> UUID derived from Device ID + Phone Number
/// 3. CSIT (Client Storage Identification Token) -> UUID derived from Device ID + CIT + Storage Key
class TokenService {
  static final TokenService instance = TokenService._internal();
  TokenService._internal();

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final Uuid _uuid = const Uuid();

  /// Fetches unique device ID based on platform
  Future<String> getDeviceId() async {
    developer.log('⚡ [TokenService.getDeviceId] Querying platform info...', name: 'TokenService');
    String id;
    try {
      if (kIsWeb) {
        final webInfo = await _deviceInfo.webBrowserInfo;
        id = 'web_${webInfo.vendor ?? 'browser'}_${webInfo.userAgent?.hashCode ?? DateTime.now().millisecondsSinceEpoch}';
      } else if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        id = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        id = iosInfo.identifierForVendor ?? 'ios_device_id';
      } else if (Platform.isWindows) {
        final windowsInfo = await _deviceInfo.windowsInfo;
        id = windowsInfo.deviceId;
      } else {
        id = 'device_${DateTime.now().millisecondsSinceEpoch}';
      }
    } catch (e) {
      developer.log('⚠️ [TokenService.getDeviceId] Query failed, using fallback timestamp ID: $e', name: 'TokenService');
      id = 'device_${DateTime.now().millisecondsSinceEpoch}';
    }
    developer.log('✅ [TokenService.getDeviceId] Device ID resolved: $id', name: 'TokenService');
    return id;
  }

  /// Generates Client Identification Token (CIT) UUID
  String generateCIT(String deviceId, String phoneNumber) {
    developer.log('⚡ [TokenService.generateCIT] Generating CIT for phone=$phoneNumber, deviceId=$deviceId...', name: 'TokenService');
    final raw = 'cit:$deviceId:$phoneNumber';
    final bytes = utf8.encode(raw);
    final hash = sha256.convert(bytes).toString();
    final cit = _uuid.v5(Namespace.url.value, hash);
    developer.log('✅ [TokenService.generateCIT] Generated CIT: $cit', name: 'TokenService');
    return cit;
  }

  /// Generates Client Storage Identification Token (CSIT) UUID
  String generateCSIT(String deviceId, String cit) {
    developer.log('⚡ [TokenService.generateCSIT] Generating CSIT for CIT=$cit, deviceId=$deviceId...', name: 'TokenService');
    final raw = 'csit:$deviceId:$cit:storage_key';
    final bytes = utf8.encode(raw);
    final hash = sha256.convert(bytes).toString();
    final csit = _uuid.v5(Namespace.url.value, hash);
    developer.log('✅ [TokenService.generateCSIT] Generated CSIT: $csit', name: 'TokenService');
    return csit;
  }
}
