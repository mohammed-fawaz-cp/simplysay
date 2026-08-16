/// AppConfig holds configuration values for MQTT, Storage, FCM, and App parameters.
/// Decoupled from logic so values can easily be modified in the future.
class AppConfig {
  AppConfig._();

  // --- REST API Server Configuration ---
  /// Dynamic backend domain/URL. Can be modified in config for Vercel, Render, or custom domains.
  static String apiBaseUrl = 'http://159.89.166.217:8000/api/v1';

  // --- MQTT Configuration ---
  static String mqttBroker = '159.89.166.217';
  static int mqttPort = 1883; // 1883 for TCP
  static String mqttClientIdPrefix = 'simplysay_client_';
  static String? mqttUsername = 'root';
  static String? mqttPassword = '2026LifeAndTree';
  static int mqttKeepAlive = 60; // seconds
  static bool mqttAutoReconnect = true;
  static int mqttReconnectDelaySeconds = 5;

  // Default MQTT topics
  static String p2pTopicPrefix = 'simplysay/p2p/';
  static String broadcastTopic = 'simplysay/broadcast';

  // --- Storage Configuration ---
  static const String dbName = 'simplysay_local.db';
  static const int dbVersion = 1;

  // --- FCM (Firebase Cloud Messaging) Configuration ---
  static const String fcmChannelId = 'simplysay_notifications';
  static const String fcmChannelName = 'SimplySay Notifications';
  static const String fcmChannelDescription = 'P2P messaging and call alerts';

  // --- Identity & App Parameters ---
  static const String appName = 'SimplySay';
  static const String defaultCountryCode = '+1';
  static const String defaultPhoneNumber = '+1234567890';
}
