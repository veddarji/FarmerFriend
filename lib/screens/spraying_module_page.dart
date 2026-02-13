// lib/screens/spraying_module_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:farmer_friend/screens/motor_actuator_page.dart';
import 'package:farmer_friend/widgets/mjpeg_viewer.dart';

const MethodChannel _mediaChannel =
    MethodChannel('farmer_friend/media_scanner');

/// Helper: ask Android to save file to gallery (returns content:// uri string if success)
Future<String?> _saveFileToGalleryPlatform(String path, {String? mime}) async {
  try {
    final res = await _mediaChannel.invokeMethod('saveToGallery', {
      'path': path,
      'mime': mime ?? _guessMime(path),
    });
    if (res is String) return res;
    return null;
  } catch (e) {
    // fallback: try scanning only
    try {
      await _mediaChannel.invokeMethod('scanFile', {'path': path});
    } catch (_) {}
    return null;
  }
}

String _guessMime(String path) {
  final ext = path.split('.').last.toLowerCase();
  if (['png', 'jpg', 'jpeg', 'gif', 'webp'].contains(ext)) {
    if (ext == 'jpg') return 'image/jpeg';
    return 'image/$ext';
  }
  if (['mp4', 'mkv', 'mov', 'avi'].contains(ext)) return 'video/$ext';
  if (ext == 'mjpg' || ext == 'mjpeg') return 'video/x-mjpeg';
  return 'application/octet-stream';
}

/// Spraying Module page with capture + recording + gallery save
class SprayingModulePage extends StatefulWidget {
  final String streamUrl; // e.g. http://<PI_IP>:8000/stream.mjpg
  final String controlEndpoint; // e.g. http://<PI_IP>:8000
  final String? mjpegUsername;
  final String? mjpegPassword;

  const SprayingModulePage({
    super.key,
    required this.streamUrl,
    required this.controlEndpoint,
    this.mjpegUsername,
    this.mjpegPassword,
  });

  @override
  State<SprayingModulePage> createState() => _SprayingModulePageState();
}

class _SprayingModulePageState extends State<SprayingModulePage> {
  final GlobalKey _videoKey = GlobalKey();
  String _status = 'Ready';

  // controls side: true = right, false = left
  bool _controlsOnRight = true;

  // Recording state
  bool _isRecording = false;
  File? _recordFile;
  IOSink? _recordSink;
  http.Client? _recordClient;
  StreamSubscription<List<int>>? _recordSub;

  @override
  void initState() {
    super.initState();
    // force landscape while in this page
    SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestNecessaryPermissions();
    });
  }

  @override
  void dispose() {
    _stopRecording();
    SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
    );
    super.dispose();
  }

  Future<void> _requestNecessaryPermissions() async {
    if (Platform.isAndroid) {
      if (await Permission.storage.isDenied) {
        await Permission.storage.request();
      }
      if (await Permission.photos.isDenied) {
        await Permission.photos.request();
      }
      if (await Permission.videos.isDenied) {
        await Permission.videos.request();
      }
    } else if (Platform.isIOS) {
      if (await Permission.photosAddOnly.isDenied) {
        await Permission.photosAddOnly.request();
      }
    }
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<bool> _ensureStoragePermission() async {
    if (Platform.isAndroid) {
      if (await Permission.storage.request().isGranted) return true;
      if (await Permission.photos.request().isGranted) return true;
      if (await Permission.videos.request().isGranted) return true;
      return false;
    } else if (Platform.isIOS) {
      return await Permission.photosAddOnly.request().isGranted;
    }
    return true;
  }

  Future<String> _getRecordingFilePath() async {
    final base = await getExternalStorageDirectory();
    final dir = base ?? await getTemporaryDirectory();
    final d = Directory('${dir.path}/FarmRoverRecords');
    await d.create(recursive: true);
    final file =
        File('${d.path}/record_${DateTime.now().millisecondsSinceEpoch}.mjpg');
    return file.path;
  }

  // -------- PHOTO CAPTURE --------
  Future<void> _capturePhoto() async {
    _setStatus('Capturing photo...');
    final ok = await _ensureStoragePermission();
    if (!ok) {
      _setStatus('Permission denied');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage permission required')),
        );
      }
      return;
    }

    try {
      final boundary = _videoKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        _setStatus('No frame');
        return;
      }
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _setStatus('Capture failed');
        return;
      }
      final pngBytes = byteData.buffer.asUint8List();

      final savedPath = await _saveBytes(pngBytes, suffix: '.png');

      final contentUri =
          await _saveFileToGalleryPlatform(savedPath, mime: 'image/png');
      if (contentUri != null) {
        _setStatus('Saved to gallery');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photo saved to gallery')),
          );
        }
      } else {
        _setStatus('Saved (not in gallery)');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photo saved (not in gallery)')),
          );
        }
      }
    } catch (e, st) {
      debugPrint('capture error: $e\n$st');
      _setStatus('Capture error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Capture failed')),
        );
      }
    } finally {
      Future.delayed(const Duration(seconds: 2), () => _setStatus('Ready'));
    }
  }

  Future<String> _saveBytes(Uint8List bytes, {String suffix = '.png'}) async {
    try {
      final base = await getExternalStorageDirectory();
      final dir = base ?? await getTemporaryDirectory();
      final d = Directory('${dir.path}/FarmRoverMedia');
      await d.create(recursive: true);
      final path =
          '${d.path}/media_${DateTime.now().millisecondsSinceEpoch}$suffix';
      final f = File(path);
      await f.writeAsBytes(bytes);
      return f.path;
    } catch (e) {
      final tmp = await getTemporaryDirectory();
      final fallback =
          '${tmp.path}/media_${DateTime.now().millisecondsSinceEpoch}$suffix';
      await File(fallback).writeAsBytes(bytes);
      return fallback;
    }
  }

  // -------- RECORDING --------
  Future<void> _startRecording() async {
    if (_isRecording) return;

    final ok = await _ensureStoragePermission();
    if (!ok) {
      _setStatus('Permission denied');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Storage permission required for recording'),
          ),
        );
      }
      return;
    }

    final path = await _getRecordingFilePath();
    final file = File(path);
    final sink = file.openWrite(mode: FileMode.writeOnlyAppend);

    setState(() {
      _isRecording = true;
      _recordFile = file;
      _recordSink = sink;
    });

    _setStatus('Recording...');
    _recordClient = http.Client();
    final req = http.Request('GET', Uri.parse(widget.streamUrl));
    req.headers['User-Agent'] = 'FarmRover-Recorder/1.0';
    if (widget.mjpegUsername != null && widget.mjpegPassword != null) {
      final auth = base64Encode(
        utf8.encode('${widget.mjpegUsername}:${widget.mjpegPassword}'),
      );
      req.headers['Authorization'] = 'Basic $auth';
    }

    try {
      final streamed =
          await _recordClient!.send(req).timeout(const Duration(seconds: 20));
      _recordSub = streamed.stream.listen(
        (data) {
          try {
            _recordSink?.add(data);
          } catch (_) {}
        },
        onDone: () async {
          await _stopRecording(finalize: true);
        },
        onError: (e) async {
          debugPrint('record stream error: $e');
          await _stopRecording(finalize: true);
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('record start error: $e');
      await _stopRecording(finalize: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording failed to start')),
        );
      }
    }
  }

  Future<void> _stopRecording({bool finalize = true}) async {
    if (!_isRecording && finalize == true) return;

    try {
      await _recordSub?.cancel();
      _recordSub = null;
    } catch (_) {}
    try {
      await _recordSink?.flush();
      await _recordSink?.close();
    } catch (_) {}
    try {
      _recordClient?.close();
    } catch (_) {}

    final savedPath = _recordFile?.path;
    setState(() {
      _isRecording = false;
      _recordFile = null;
      _recordSink = null;
      _recordClient = null;
    });

    if (savedPath != null) {
      final contentUri = await _saveFileToGalleryPlatform(
        savedPath,
        mime: _guessMime(savedPath),
      );
      if (contentUri != null) {
        _setStatus('Saved video to gallery');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recording saved to gallery')),
          );
        }
      } else {
        _setStatus('Saved video (not in gallery)');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording saved (not in gallery)'),
            ),
          );
        }
      }
    } else {
      _setStatus('Recording stopped');
    }

    Future.delayed(const Duration(seconds: 2), () => _setStatus('Ready'));
  }

  // -------- SEND COMMAND TO PI (spray head, not motor) --------
  Future<void> _sendControlCommand(String cmd) async {
    _setStatus('Sending $cmd...');
    try {
      final uri = Uri.parse('${widget.controlEndpoint}/command');
      Map<String, String> headers = {'Content-Type': 'application/json'};
      if (widget.mjpegUsername != null && widget.mjpegPassword != null) {
        final auth = base64Encode(
          utf8.encode('${widget.mjpegUsername}:${widget.mjpegPassword}'),
        );
        headers['Authorization'] = 'Basic $auth';
      }
      final resp = await http
          .post(uri, headers: headers, body: '{"cmd":"$cmd"}')
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        _setStatus('Sent $cmd');
      } else {
        _setStatus('Fail ${resp.statusCode}');
      }
    } catch (e) {
      _setStatus('Err');
    } finally {
      Future.delayed(
        const Duration(milliseconds: 700),
        () => _setStatus('Ready'),
      );
    }
  }

  // -------- UI HELPERS --------
  Widget _directionButton({required IconData icon, required String cmd}) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      elevation: 6,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _sendControlCommand(cmd),
        child: Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black54.withOpacity(0.6),
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  /// Live view card
  Widget _buildVideoArea() {
    return Center(
      child: RepaintBoundary(
        key: _videoKey,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 16),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: MJPEGViewer(
                url: widget.streamUrl,
                username: widget.mjpegUsername,
                password: widget.mjpegPassword,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Controls column: Top / Left / Right / Bottom
  Widget _buildControlsArea() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 16),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    children: [
                      _directionButton(
                        icon: Icons.keyboard_arrow_up,
                        cmd: 'U',
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Top',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        children: [
                          _directionButton(
                            icon: Icons.keyboard_arrow_left,
                            cmd: 'L',
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Left',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(width: 32),
                      Column(
                        children: [
                          _directionButton(
                            icon: Icons.keyboard_arrow_right,
                            cmd: 'R',
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Right',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Column(
                    children: [
                      _directionButton(
                        icon: Icons.keyboard_arrow_down,
                        cmd: 'D',
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Bottom',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;
    debugPrint('Spray page size: $screenW x $screenH');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 8),
            // MOTOR ACTUATOR BUTTON – uses SAME endpoint & streamUrl
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MotorActuatorPage(
                      streamUrl: widget.streamUrl,
                      controlEndpoint: widget.controlEndpoint,
                      mjpegUsername: widget.mjpegUsername,
                      mjpegPassword: widget.mjpegPassword,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text(
                "Motor Actuator",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),

            const Spacer(),

            // PHOTO BUTTON
            ElevatedButton.icon(
              onPressed: _capturePhoto,
              icon: const Icon(Icons.camera_alt, color: Colors.black),
              label: const Text(
                "Photo",
                style:
                    TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),

            const SizedBox(width: 12),

            // RECORD BUTTON
            ElevatedButton.icon(
              onPressed: _isRecording ? _stopRecording : _startRecording,
              icon: Icon(
                _isRecording ? Icons.stop : Icons.fiber_manual_record,
                color: Colors.white,
              ),
              label: Text(
                _isRecording ? "Stop" : "Record",
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.grey : Colors.green,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),

            const SizedBox(width: 12),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 6),

            // Controls toggle row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    'Controls side',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(width: 6),
                  Switch(
                    value: _controlsOnRight,
                    activeColor: Colors.amber,
                    onChanged: (v) {
                      setState(() => _controlsOnRight = v);
                    },
                  ),
                ],
              ),
            ),

            // MAIN ROW: live view + controls
            Expanded(
              child: Row(
                children: _controlsOnRight
                    ? [
                        Expanded(flex: 6, child: _buildVideoArea()),
                        const SizedBox(width: 8),
                        Expanded(flex: 4, child: _buildControlsArea()),
                      ]
                    : [
                        Expanded(flex: 4, child: _buildControlsArea()),
                        const SizedBox(width: 8),
                        Expanded(flex: 6, child: _buildVideoArea()),
                      ],
              ),
            ),

            const SizedBox(height: 8),

            // Footer: url + status
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0),
              child: Row(
                children: [
                  const Icon(Icons.rss_feed, color: Colors.greenAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.streamUrl,
                      style: const TextStyle(color: Colors.white60),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _status,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
