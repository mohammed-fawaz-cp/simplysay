import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:otp/otp.dart';

class AuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
  final FlutterAppAuth _appAuth = const FlutterAppAuth();

  FlutterAppAuth get appAuth => _appAuth;

  // Configuration Constants (To be updated with user credentials)
  static String googleWebClientId = '';
  
  static String microsoftClientId = '';
  static String microsoftTenantId = 'common';
  static String microsoftRedirectUri = 'com.comlabs.simplysay://oauthredirect';

  static String metaAppId = '';
  static String metaRedirectUri = 'com.comlabs.simplysay://oauthredirect';

  /// Real Google OAuth login
  Future<GoogleSignInAccount?> signInWithGoogle() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        final auth = await account.authentication;
        debugPrint('====================================');
        debugPrint('LOGIN SUCCESSFUL: Google');
        debugPrint('User ID: ${account.id}');
        debugPrint('Email: ${account.email}');
        debugPrint('Display Name: ${account.displayName}');
        debugPrint('Photo URL: ${account.photoUrl}');
        debugPrint('ID Token: ${auth.idToken}');
        debugPrint('Access Token: ${auth.accessToken}');
        debugPrint('====================================');
      }
      return account;
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      return null;
    }
  }

  /// Real Microsoft OAuth 2.0 login via PKCE / AppAuth
  Future<AuthorizationTokenResponse?> signInWithMicrosoft() async {
    try {
      if (microsoftClientId.isEmpty) {
        debugPrint('Microsoft Client ID not set yet.');
      }
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          microsoftClientId,
          microsoftRedirectUri,
          issuer: 'https://login.microsoftonline.com/$microsoftTenantId/v2.0',
          scopes: ['openid', 'profile', 'email', 'User.Read'],
        ),
      );
      debugPrint('====================================');
      debugPrint('LOGIN SUCCESSFUL: Microsoft');
      debugPrint('Access Token: ${result.accessToken}');
      debugPrint('ID Token: ${result.idToken}');
      debugPrint('Refresh Token: ${result.refreshToken}');
      debugPrint('Token Expiration: ${result.accessTokenExpirationDateTime}');
      debugPrint('====================================');
      return result;
    } catch (e) {
      debugPrint('Microsoft Sign-In Error: $e');
      return null;
    }
  }

  /// Real Meta (Facebook) OAuth 2.0 login via AppAuth
  Future<AuthorizationTokenResponse?> signInWithMeta() async {
    try {
      if (metaAppId.isEmpty) {
        debugPrint('Meta App ID not set yet.');
      }
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          metaAppId,
          metaRedirectUri,
          serviceConfiguration: const AuthorizationServiceConfiguration(
            authorizationEndpoint: 'https://www.facebook.com/v18.0/dialog/oauth',
            tokenEndpoint: 'https://graph.facebook.com/v18.0/oauth/access_token',
          ),
          scopes: ['email', 'public_profile'],
        ),
      );
      debugPrint('====================================');
      debugPrint('LOGIN SUCCESSFUL: Meta');
      debugPrint('Access Token: ${result.accessToken}');
      debugPrint('Token Expiration: ${result.accessTokenExpirationDateTime}');
      debugPrint('====================================');
      return result;
    } catch (e) {
      debugPrint('Meta Sign-In Error: $e');
      return null;
    }
  }

  /// Generate 2FA Time-based One-Time Password (TOTP)
  String generate2FACode(String secret) {
    return OTP.generateTOTPCodeString(
      secret,
      DateTime.now().millisecondsSinceEpoch,
      algorithm: Algorithm.SHA1,
      isGoogle: true,
    );
  }

  /// Verify 2FA code entered by user
  bool verify2FACode(String userCode, String secret) {
    final generated = generate2FACode(secret);
    return userCode == generated;
  }
}
