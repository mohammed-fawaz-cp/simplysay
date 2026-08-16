import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<bool> requestCameraAndMicrophonePermissions() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.notification,
    ].request();

    return statuses[Permission.camera]?.isGranted == true &&
        statuses[Permission.microphone]?.isGranted == true;
  }

  Future<bool> isCameraGranted() async {
    return await Permission.camera.isGranted;
  }
}
