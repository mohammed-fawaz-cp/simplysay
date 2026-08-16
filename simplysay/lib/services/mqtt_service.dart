import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import '../core/config/app_config.dart';
import 'mqtt/mqtt_client_factory.dart';

enum MQTTConnectionState { disconnected, connecting, connected, error }

class MQTTService {
  static final MQTTService instance = MQTTService._internal();
  MQTTService._internal();

  MqttClient? _client;
  MQTTConnectionState _connectionState = MQTTConnectionState.disconnected;
  Timer? _reconnectTimer;
  String? _clientId;
  final Set<String> _subscribedTopics = {};
  
  final StreamController<MQTTConnectionState> _stateController =
      StreamController<MQTTConnectionState>.broadcast();
  final StreamController<MqttReceivedMessage<MqttMessage>> _messageController =
      StreamController<MqttReceivedMessage<MqttMessage>>.broadcast();

  MQTTConnectionState get connectionState => _connectionState;
  bool get isConnected => _connectionState == MQTTConnectionState.connected;
  Stream<MQTTConnectionState> get stateStream => _stateController.stream;
  Stream<MqttReceivedMessage<MqttMessage>> get messageStream => _messageController.stream;

  /// Alias for publish with default QoS
  void publishMessage(String topic, String payload, {MqttQos qos = MqttQos.atLeastOnce}) {
    publish(topic, payload, qos: qos);
  }

  /// Initializes and connects MQTT client with auto-reconnect support
  Future<bool> initialize({required String cit}) async {
    _clientId = '${AppConfig.mqttClientIdPrefix}$cit';

    developer.log('⚡ [MQTTService.initialize] STAGE 3A: Initializing MQTT client for broker ${AppConfig.mqttBroker}:${AppConfig.mqttPort} with ClientID=$_clientId...', name: 'MQTTService');

    _client = createMqttClient(AppConfig.mqttBroker, _clientId!, AppConfig.mqttPort);
    _client!.keepAlivePeriod = AppConfig.mqttKeepAlive;
    _client!.logging(on: kDebugMode);
    _client!.autoReconnect = AppConfig.mqttAutoReconnect;
    _client!.resubscribeOnAutoReconnect = true;

    // Callbacks
    _client!.onDisconnected = _onDisconnected;
    _client!.onConnected = _onConnected;
    _client!.onAutoReconnected = _onAutoReconnected;
    _client!.onSubscribed = _onSubscribed;

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(_clientId!)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    if (AppConfig.mqttUsername != null && AppConfig.mqttPassword != null) {
      connMessage.authenticateAs(
        AppConfig.mqttUsername!,
        AppConfig.mqttPassword!,
      );
    }

    _client!.connectionMessage = connMessage;

    return await connect();
  }

  /// Establishes connection to MQTT broker
  Future<bool> connect() async {
    if (_client == null) return false;

    try {
      _updateState(MQTTConnectionState.connecting);
      developer.log('⚡ [MQTTService.connect] Connecting to MQTT broker at ${AppConfig.mqttBroker}:${AppConfig.mqttPort}...', name: 'MQTTService');
      await _client!.connect();

      if (_client!.connectionStatus?.state == MqttConnectionState.connected) {
        _updateState(MQTTConnectionState.connected);
        _listenToMessages();
        _reconnectTimer?.cancel();
        _resubscribeAll();
        developer.log('✅ [MQTTService.connect] Connected successfully to Mosquitto MQTT broker.', name: 'MQTTService');
        return true;
      } else {
        developer.log('⚠️ [MQTTService.connect] MQTT Connection failed: ${_client!.connectionStatus}', name: 'MQTTService');
        _updateState(MQTTConnectionState.error);
        _scheduleReconnect();
        return false;
      }
    } catch (e) {
      developer.log('⚠️ [MQTTService.connect] MQTT Exception (Broker unreachable): $e', name: 'MQTTService');
      _updateState(MQTTConnectionState.error);
      _scheduleReconnect();
      return false;
    }
  }

  void _listenToMessages() {
    _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final msg in messages) {
        developer.log('📩 [MQTTService] Message received on topic: ${msg.topic}', name: 'MQTTService');
        _messageController.add(msg);
      }
    });
  }

  void _onConnected() {
    developer.log('✅ [MQTTService] Callback: Connected to MQTT broker.', name: 'MQTTService');
    _updateState(MQTTConnectionState.connected);
    _resubscribeAll();
  }

  void _resubscribeAll() {
    for (final topic in _subscribedTopics) {
      developer.log('📡 [MQTTService] Subscribing/Resubscribing to topic: $topic', name: 'MQTTService');
      _client?.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  void _onDisconnected() {
    debugPrint('MQTT Disconnected');
    _updateState(MQTTConnectionState.disconnected);
    if (AppConfig.mqttAutoReconnect) {
      _scheduleReconnect();
    }
  }

  void _onAutoReconnected() {
    debugPrint('MQTT Auto Reconnected');
    _updateState(MQTTConnectionState.connected);
    _resubscribeAll();
  }

  void _onSubscribed(String topic) {
    debugPrint('MQTT Subscribed to topic: $topic');
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      Duration(seconds: AppConfig.mqttReconnectDelaySeconds),
      () async {
        if (_connectionState != MQTTConnectionState.connected) {
          debugPrint('MQTT Auto-reconnecting background retry...');
          await connect();
        }
      },
    );
  }

  /// Subscribe to a topic
  void subscribe(String topic, {MqttQos qos = MqttQos.atLeastOnce}) {
    _subscribedTopics.add(topic);
    if (_client != null && _connectionState == MQTTConnectionState.connected) {
      _client!.subscribe(topic, qos);
      developer.log('📡 [MQTTService] Subscribed immediately to topic: $topic', name: 'MQTTService');
    } else {
      developer.log('⏳ [MQTTService] Queued subscription for topic: $topic (Awaiting connection)', name: 'MQTTService');
    }
  }

  /// Publish a message to a topic
  void publish(String topic, String payload, {MqttQos qos = MqttQos.atLeastOnce}) async {
    if (_client == null || _connectionState != MQTTConnectionState.connected) {
      developer.log('⏳ [MQTTService.publish] Waiting for MQTT connection before publishing to $topic...', name: 'MQTTService');
      try {
        await stateStream.firstWhere((s) => s == MQTTConnectionState.connected).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    if (_client != null && _connectionState == MQTTConnectionState.connected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(payload);
      _client!.publishMessage(topic, qos, builder.payload!);
      developer.log('📤 [MQTTService.publish] Published message to topic $topic: $payload', name: 'MQTTService');
    } else {
      developer.log('❌ [MQTTService.publish] Failed to publish message to topic $topic (Not connected)', name: 'MQTTService');
    }
  }

  void _updateState(MQTTConnectionState state) {
    _connectionState = state;
    _stateController.add(state);
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _client?.disconnect();
    _updateState(MQTTConnectionState.disconnected);
  }
}

