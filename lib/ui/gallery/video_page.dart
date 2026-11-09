import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../gallery/photo.dart';
import '../../gallery/photo_repository.dart';
import '../format.dart';
import 'photo_thumbnail.dart';

/// Un video del álbum dentro del visor. Toca para reproducir o pausar; la
/// barra de abajo se puede arrastrar para adelantar o retroceder.
class VideoPage extends StatefulWidget {
  final Photo video;
  final PhotoRepository photos;

  const VideoPage({super.key, required this.video, required this.photos});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  late final VideoPlayerController _player = _createPlayer();
  bool _ready = false;
  bool _failed = false;

  VideoPlayerController _createPlayer() {
    final uri = Uri.parse(widget.video.uri);
    return uri.scheme == 'file'
        ? VideoPlayerController.file(File.fromUri(uri))
        : VideoPlayerController.contentUri(uri);
  }

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayer);
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.initialize();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint('[Gallery] no se pudo abrir el video: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onPlayer() {
    if (!mounted) return;
    if (_player.value.hasError && !_failed) {
      debugPrint('[Gallery] error reproduciendo: ${_player.value.errorDescription}');
      setState(() => _failed = true);
      return;
    }
    setState(() {}); // tiempo y botón de reproducir
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayer);
    _player.dispose();
    super.dispose();
  }

  bool get _atEnd {
    final v = _player.value;
    return v.duration > Duration.zero && v.position >= v.duration;
  }

  Future<void> _toggle() async {
    if (!_ready || _failed) return;
    try {
      if (_player.value.isPlaying) {
        await _player.pause();
      } else {
        if (_atEnd) await _player.seekTo(Duration.zero);
        await _player.play();
      }
    } catch (e) {
      debugPrint('[Gallery] falló reproducir/pausar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const _Broken();
    final value = _player.value;
    return Hero(
      tag: widget.video.uri,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: _ready
                  ? AspectRatio(
                      aspectRatio: value.aspectRatio,
                      child: VideoPlayer(_player),
                    )
                  // Mientras abre el video se ve su miniatura.
                  : AspectRatio(
                      aspectRatio: 1,
                      child: PhotoThumbnail(photo: widget.video, photos: widget.photos),
                    ),
            ),
            if (!_ready)
              const Center(child: CircularProgressIndicator())
            else if (!value.isPlaying)
              const Center(
                child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 84),
              ),
            if (_ready)
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        Text(
                          formatDuration(value.position),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: VideoProgressIndicator(
                            _player,
                            allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            colors: const VideoProgressColors(
                              playedColor: Colors.white,
                              bufferedColor: Colors.white38,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          formatDuration(value.duration),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Broken extends StatelessWidget {
  const _Broken();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, size: 72, color: Colors.white38),
            SizedBox(height: 12),
            Text('No se pudo abrir el video', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
}
