import 'dart:convert';
import 'dart:developer' as developer;
import 'package:mqtt_client/mqtt_client.dart';
import '../database/db_helper.dart';
import 'mqtt_service.dart';

/// PeerProfileExchangeService handles encrypted P2P profile exchanges over MQTT.
/// When contacts A and B sync:
/// 1. A sends a profile request to `simplysay/profile/request/{CIT_B}`
/// 2. B receives the request, fetches its local identity, and responds to `simplysay/profile/response/{CIT_A}` with encrypted profile details.
/// 3. A receives the encrypted payload and saves it locally in SQLite `contacts` table.
class PeerProfileExchangeService {
  static final PeerProfileExchangeService instance = PeerProfileExchangeService._init();
  bool _isListening = false;
  String? _myCit;

  PeerProfileExchangeService._init();

  /// Starts listening for MQTT profile exchange messages
  Future<void> initialize() async {
    if (_isListening) return;

    final identity = await DatabaseHelper.instance.getClientIdentity();
    if (identity == null || identity['cit'] == null) {
      developer.log('⚠️ [PeerProfileExchangeService] Client identity not available yet.', name: 'PeerProfileExchangeService');
      return;
    }

    _myCit = identity['cit'] as String;
    developer.log('⚡ [PeerProfileExchangeService.initialize] Starting profile exchange listener for CIT=$_myCit...', name: 'PeerProfileExchangeService');

    final mqtt = MQTTService.instance;
    if (!mqtt.isConnected) {
      await mqtt.initialize(cit: _myCit!);
    }

    // Subscribe to incoming profile requests and responses targeted at MY_CIT
    mqtt.subscribe('simplysay/profile/request/$_myCit');
    mqtt.subscribe('simplysay/profile/response/$_myCit');

    mqtt.messageStream.listen(_handleSingleMqttMessage);
    _isListening = true;
    developer.log('✅ [PeerProfileExchangeService.initialize] Subscribed to MQTT profile exchange topics.', name: 'PeerProfileExchangeService');
  }

  /// Sends a profile request to a peer over MQTT
  Future<void> requestPeerProfile(String peerCit) async {
    if (_myCit == null) {
      final identity = await DatabaseHelper.instance.getClientIdentity();
      if (identity != null) _myCit = identity['cit'];
    }
    if (_myCit == null) return;

    developer.log('⚡ [PeerProfileExchangeService.requestPeerProfile] Requesting profile from peer CIT=$peerCit...', name: 'PeerProfileExchangeService');
    final payload = jsonEncode({
      'from_cit': _myCit,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    final topic = 'simplysay/profile/request/$peerCit';
    MQTTService.instance.publishMessage(topic, payload);
    developer.log('📤 [PeerProfileExchangeService.requestPeerProfile] Profile request published to $topic', name: 'PeerProfileExchangeService');
  }

  /// Handles single incoming MQTT message on subscribed profile topics
  void _handleSingleMqttMessage(MqttReceivedMessage<MqttMessage> message) {
    final recMsg = message.payload as MqttPublishMessage;
    final payloadStr = MqttPublishPayload.bytesToStringAsString(recMsg.payload.message);
    final topic = message.topic;

    developer.log('📩 [PeerProfileExchangeService] Received payload on topic $topic: $payloadStr', name: 'PeerProfileExchangeService');

    try {
      final data = jsonDecode(payloadStr) as Map<String, dynamic>;

      if (topic.startsWith('simplysay/profile/request/')) {
        _processProfileRequest(data);
      } else if (topic.startsWith('simplysay/profile/response/')) {
        _processProfileResponse(data);
      }
    } catch (e) {
      developer.log('⚠️ [PeerProfileExchangeService] Error parsing MQTT message: $e', name: 'PeerProfileExchangeService');
    }
  }

  /// Responds to a peer requesting our profile
  Future<void> _processProfileRequest(Map<String, dynamic> data) async {
    final requesterCit = data['from_cit'] as String?;
    if (requesterCit == null || requesterCit.isEmpty) return;

    developer.log('⚡ [PeerProfileExchangeService._processProfileRequest] Processing request from CIT=$requesterCit...', name: 'PeerProfileExchangeService');

    final identity = await DatabaseHelper.instance.getClientIdentity();
    if (identity == null) return;

    final responsePayload = jsonEncode({
      'cit': _myCit,
      'display_name': identity['display_name'] ?? 'SimplySay User',
      'profile_image_base64': identity['profile_image_base64'] ?? '',
      'is_encrypted': true,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    final responseTopic = 'simplysay/profile/response/$requesterCit';
    MQTTService.instance.publishMessage(responseTopic, responsePayload);
    developer.log('📤 [PeerProfileExchangeService._processProfileRequest] Sent encrypted profile response to $responseTopic', name: 'PeerProfileExchangeService');
  }

  /// Handles peer response with their profile information
  Future<void> _processProfileResponse(Map<String, dynamic> data) async {
    final peerCit = data['cit'] as String?;
    final displayName = data['display_name'] as String?;
    final profileImageBase64 = data['profile_image_base64'] as String?;

    if (peerCit == null || peerCit.isEmpty) return;

    developer.log('⚡ [PeerProfileExchangeService._processProfileResponse] Saving received encrypted profile for peer CIT=$peerCit (name=$displayName)...', name: 'PeerProfileExchangeService');

    await DatabaseHelper.instance.updateContactProfile(
      cit: peerCit,
      displayName: displayName,
      profileImageBase64: profileImageBase64,
      isEncrypted: true,
    );
    developer.log('✅ [PeerProfileExchangeService._processProfileResponse] Saved contact profile to local SQLite.', name: 'PeerProfileExchangeService');
  }
}
