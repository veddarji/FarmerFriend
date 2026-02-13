// lib/widgets/mjpeg_viewer.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// MJPEGViewer with small frame buffer for smoother playback
class MJPEGViewer extends StatefulWidget {
  final String url;
  final String? username;
  final String? password;
  final BoxFit fit;

  const MJPEGViewer({
    super.key,
    required this.url,
    this.username,
    this.password,
    this.fit = BoxFit.cover,
  });

  @override
  State<MJPEGViewer> createState() => _MJPEGViewerState();
}

class _MJPEGViewerState extends State<MJPEGViewer> {
  http.Client? _client;
  bool _running = false;

  // Currently displayed frame
  Uint8List? _currentFrame;

  // Small buffer queue
  final List<Uint8List> _buffer = [];
  static const int _maxBufferSize = 10;

  Timer? _playbackTimer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant MJPEGViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.username != widget.username ||
        oldWidget.password != widget.password) {
      _restart();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _start() {
    _running = true;
    _startPlaybackTimer();
    _connectLoop();
  }

  void _restart() {
    _stop();
    _start();
  }

  void _stop() {
    _running = false;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
  }

  void _startPlaybackTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_running) return;
      if (_buffer.isEmpty) return;

      final frame = _buffer.removeAt(0);
      if (mounted) {
        setState(() {
          _currentFrame = frame;
        });
      }
    });
  }

  Future<void> _connectLoop() async {
    while (_running) {
      try {
        await _connectOnce();
        if (!_running) break;
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (_) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _connectOnce() async {
    _client?.close();
    _client = http.Client();

    final req = http.Request('GET', Uri.parse(widget.url));
    req.headers['User-Agent'] = 'FarmRover-MJPEG-Client/1.0';

    if (widget.username != null && widget.password != null) {
      final auth =
          base64Encode(utf8.encode('${widget.username}:${widget.password}'));
      req.headers['Authorization'] = 'Basic $auth';
    }

    final streamed =
        await _client!.send(req).timeout(const Duration(seconds: 20));
    final buffer = <int>[];

    await for (final chunk in streamed.stream) {
      if (!_running) break;
      for (final b in chunk) {
        buffer.add(b);
        final n = buffer.length;

        // End of JPEG: FF D9
        if (n >= 2 && buffer[n - 2] == 0xFF && buffer[n - 1] == 0xD9) {
          int start = 0;
          // Find SOI: FF D8
          for (int i = 0; i < n - 1; i++) {
            if (buffer[i] == 0xFF && buffer[i + 1] == 0xD8) {
              start = i;
              break;
            }
          }
          final frameBytes = Uint8List.fromList(buffer.sublist(start, n));
          buffer.clear();

          if (_buffer.length >= _maxBufferSize) {
            _buffer.removeAt(0); // drop oldest
          }
          _buffer.add(frameBytes);
        }
      }
    }

    _client?.close();
    _client = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_currentFrame == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Image.memory(
      _currentFrame!,
      gaplessPlayback: true,
      fit: widget.fit,
    );
  }
}
