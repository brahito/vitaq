import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../core/device_config.dart';
import 'android/endoscope_camera_android.dart';
import 'endoscope_camera.dart';
import 'unsupported/endoscope_camera_unsupported.dart';

EndoscopeCamera createEndoscopeCamera(DeviceConfig config) {
  if (kIsWeb) return EndoscopeCameraUnsupported('Web');
  if (Platform.isAndroid) return EndoscopeCameraAndroid(config);
  if (Platform.isIOS) return EndoscopeCameraUnsupported('iOS');      // TODO: AVFoundation
  if (Platform.isWindows) return EndoscopeCameraUnsupported('Windows'); // TODO: Media Foundation / DirectShow
  if (Platform.isMacOS) return EndoscopeCameraUnsupported('macOS');   // TODO: AVFoundation
  return EndoscopeCameraUnsupported(Platform.operatingSystem);
}