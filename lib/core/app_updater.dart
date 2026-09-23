import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// URL del latest.json publicado en GitHub Releases. La inyecta el workflow
/// de GitHub Actions con --dart-define; en builds locales queda vacía y el
/// actualizador no hace nada.
const kUpdateManifestUrl = String.fromEnvironment('UPDATE_URL');

enum UpdateStatus { idle, downloading, ready, error }

/// Busca una versión nueva en GitHub Releases, la descarga en segundo plano y
/// deja la APK lista para que el usuario toque "Instalar".
class AppUpdater extends ChangeNotifier {
  static const _channel = MethodChannel('vtq/updater');
  static const _minCheckInterval = Duration(hours: 1);

  UpdateStatus status = UpdateStatus.idle;
  String? newVersionName;
  double progress = 0;
  String? error;

  String? _apkPath;
  DateTime? _lastCheck;
  bool _busy = false;
  bool _waitingPermission = false;

  bool get enabled => kUpdateManifestUrl.isNotEmpty && Platform.isAndroid;

  /// Se llama al arrancar y al volver a la app; como mucho una consulta por hora.
  Future<void> check() async {
    if (!enabled || _busy || status == UpdateStatus.ready) return;
    final now = DateTime.now();
    if (_lastCheck != null && now.difference(_lastCheck!) < _minCheckInterval) return;
    _lastCheck = now;
    _busy = true;

    try {
      final manifest = await _getJson(kUpdateManifestUrl);
      final remoteCode = manifest['versionCode'] as int;
      final localCode = await _channel.invokeMethod<int>('getVersionCode') ?? 0;
      if (remoteCode <= localCode) return;

      newVersionName = manifest['versionName'] as String?;
      final dir = await _channel.invokeMethod<String>('getUpdateDir');
      final apk = File('$dir/vtq-$remoteCode.apk');

      status = UpdateStatus.downloading;
      progress = 0;
      notifyListeners();
      await _download(manifest['apkUrl'] as String, apk);

      _apkPath = apk.path;
      status = UpdateStatus.ready;
    } catch (e) {
      debugPrint('AppUpdater: $e');
      error = '$e';
      status = UpdateStatus.error;
      _lastCheck = null; // reintentar en la próxima ocasión
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Abre el instalador de Android. La primera vez Android pide permitir
  /// "instalar apps desconocidas" para VTQ; al volver se reintenta solo.
  Future<void> install() async {
    final path = _apkPath;
    if (path == null) return;
    final res = await _channel.invokeMethod<String>('installApk', {'path': path});
    _waitingPermission = res == 'needs_permission';
  }

  /// Llamar al volver a primer plano (AppLifecycleState.resumed).
  void onResumed() {
    if (_waitingPermission) {
      _waitingPermission = false;
      install();
    } else {
      check();
    }
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(Uri.parse(url))).close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode} en $url');
      return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  Future<void> _download(String url, File dest) async {
    final tmp = File('${dest.path}.part');
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(Uri.parse(url))).close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode} en $url');
      final total = res.contentLength;
      var received = 0;
      final sink = tmp.openWrite();
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            progress = received / total;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && received != total) throw const HttpException('Descarga incompleta');
      await tmp.rename(dest.path);
    } finally {
      client.close();
    }
  }
}
