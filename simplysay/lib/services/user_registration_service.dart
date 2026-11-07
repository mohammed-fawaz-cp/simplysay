import 'dart:convert';
import 'dart:developer' as developer;
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

/// UserRegistrationService handles STAGE 2 of initialization:
/// Registering the local user's (phone_hash, cit, csit, device_id) with the FastAPI server.
class UserRegistrationService {
  /// Computes SHA-256 hash of a phone number (E.164 format)
  static String computePhoneHash(String rawPhone) {
    developer.log('⚡ [UserRegistrationService.computePhoneHash] Hashing rawPhone=$rawPhone...', name: 'UserRegistrationService');
    // Normalize phone number (strip whitespace, dashes, parens)
    final cleaned = rawPhone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    final bytes = utf8.encode(cleaned);
    final hash = sha256.convert(bytes).toString();
    developer.log('✅ [UserRegistrationService.computePhoneHash] Cleaned=$cleaned, Hash=$hash', name: 'UserRegistrationService');
    return hash;
  }

  /// Sends user registration request to FastAPI server
  static Future<bool> registerUserOnServer({
    required String rawPhoneNumber,
    required String cit,
    required String csit,
    required String deviceId,
    String? fcmToken,
  }) async {
    try {
      final phoneHash = computePhoneHash(rawPhoneNumber);
      final url = Uri.parse('${AppConfig.apiBaseUrl}/users/register');

      developer.log(
        '⚡ [UserRegistrationService.registerUserOnServer] STAGE 2: Registering user with FastAPI at $url (phoneHash=$phoneHash, CIT=$cit, CSIT=$csit)',
        name: 'UserRegistrationService',
      );

      final payload = <String, dynamic>{
        'phone_hash': phoneHash,
        'cit': cit,
        'csit': csit,
        'device_id': deviceId,
      };
      if (fcmToken != null && fcmToken.isNotEmpty) {
        payload['fcm_token'] = fcmToken;
      }

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        developer.log(
          '✅ [UserRegistrationService.registerUserOnServer] User registered on FastAPI server (Status ${response.statusCode}).',
          name: 'UserRegistrationService',
        );
        return true;
      } else {
        developer.log(
          '❌ [UserRegistrationService.registerUserOnServer] Server returned status ${response.statusCode}: ${response.body}',
          name: 'UserRegistrationService',
          error: response.body,
        );
        return false;
      }
    } catch (e) {
      // In case server is offline or unreachable, log error gracefully so initialization continues locally
      developer.log(
        '⚠️ [UserRegistrationService.registerUserOnServer] Server registration failed (backend offline/unreachable): $e',
        name: 'UserRegistrationService',
      );
      return false;
    }
  }
}
