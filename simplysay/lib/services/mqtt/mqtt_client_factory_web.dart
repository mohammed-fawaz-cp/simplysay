import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

MqttClient createMqttClient(String broker, String clientId, int port) {
  // Web browser requires WebSockets for MQTT
  final wsUrl = 'ws://$broker:$port/mqtt';
  final client = MqttBrowserClient(wsUrl, clientId);
  client.port = port;
  return client;
}
