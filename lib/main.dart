import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'camera/endoscope_camera_factory.dart';
import 'core/app_updater.dart';
import 'core/device_config.dart';
import 'ui/camera_screen.dart';
import 'ui/update_banner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Activar pantalla completa después del primer frame: pedirlo antes de
  // runApp() deja el FlutterView en tamaño 0x0 en algunos MIUI (edge-to-edge
  // de Android 15+) y la app nunca llega a pintar el primer frame.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  });
  runApp(const EndoscopeApp());
}

class EndoscopeApp extends StatefulWidget {
  const EndoscopeApp({super.key});

  @override
  State<EndoscopeApp> createState() => _EndoscopeAppState();
}

class _EndoscopeAppState extends State<EndoscopeApp> with WidgetsBindingObserver {
  late final camera = createEndoscopeCamera(kEndoscope);
  final updater = AppUpdater();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    updater.check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    updater.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) updater.onResumed();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VitaQ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: CameraScreen(camera: camera, config: kEndoscope),
      builder: (context, child) => Stack(
        children: [child!, UpdateBanner(updater: updater)],
      ),
    );
  }
}