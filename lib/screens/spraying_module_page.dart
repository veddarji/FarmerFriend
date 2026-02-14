// lib/screens/spraying_module_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/rendering.dart';

import 'motor_actuator_page.dart';

class SprayingModulePage extends StatefulWidget {
  final String signalingUrl;

  const SprayingModulePage({
    super.key,
    required this.signalingUrl,
  });

  @override
  State<SprayingModulePage> createState() => _SprayingModulePageState();
}

class _SprayingModulePageState extends State<SprayingModulePage> {
  late RTCVideoRenderer _renderer;
  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;

  bool _controlsOnRight = true;
  String _status = "CONNECTING";
  bool _isRecording = false;
  MediaRecorder? _recorder;

  final GlobalKey _videoKey = GlobalKey();

  // ================= INIT =================
  @override
  void initState() {
    super.initState();
    _initWebRTC();
  }

  Future<void> _initWebRTC() async {
    _renderer = RTCVideoRenderer();
    await _renderer.initialize();

    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ],
    };

    _pc = await createPeerConnection(configuration);

    // 🔥 REQUIRED — Tell Flutter we want to receive video
    await _pc!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(
        direction: TransceiverDirection.RecvOnly,
      ),
    );

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        setState(() {
          _renderer.srcObject = event.streams[0];
        });
      }
    };

    // ================= DATA CHANNEL =================
    RTCDataChannelInit init = RTCDataChannelInit()
      ..ordered = false
      ..maxRetransmits = 0;

    // 🔥 CREATE IT (do NOT comment this)
    _dc = await _pc!.createDataChannel("control", init);

    _dc!.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        setState(() => _status = "ONLINE");
      }
    };

    _dc!.onMessage = (RTCDataChannelMessage message) {
      print("Message from rpi: ${message.text}");
    };

    // ================= OFFER =================
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    await Future.delayed(const Duration(milliseconds: 500));

    final resp = await http.post(
      Uri.parse(widget.signalingUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sdp': offer.sdp,
        'type': offer.type,
      }),
    );

    final data = jsonDecode(resp.body);

    await _pc!.setRemoteDescription(
      RTCSessionDescription(data['sdp'], data['type']),
    );
  }

  // ================= COMMAND =================
  void _sendCmd(String cmd) {
    if (_dc == null || _dc!.state != RTCDataChannelState.RTCDataChannelOpen)
      return;

    _dc!.send(RTCDataChannelMessage(jsonEncode({'cmd': cmd})));
  }

  // ================= PHOTO =================
  Future<void> _capturePhoto() async {
    final boundary =
        _videoKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

    if (boundary == null) return;

    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();

    final dir = await getTemporaryDirectory();
    final file =
        File("${dir.path}/photo_${DateTime.now().millisecondsSinceEpoch}.png");

    await file.writeAsBytes(bytes);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Photo saved")),
    );
  }

  // ================= RECORD =================
  Future<void> _startRecording() async {
    if (_isRecording) return;

    final stream = _renderer.srcObject;
    if (stream == null) return;

    final dir = await getTemporaryDirectory();
    final path =
        "${dir.path}/record_${DateTime.now().millisecondsSinceEpoch}.mp4";

    _recorder = MediaRecorder();
    await _recorder!.start(path, videoTrack: stream.getVideoTracks().first);

    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    await _recorder?.stop();
    setState(() => _isRecording = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Recording saved")),
    );
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text("Spraying Module ($_status)"),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt),
            onPressed: _capturePhoto,
          ),
          IconButton(
            icon: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record),
            onPressed: _isRecording ? _stopRecording : _startRecording,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MotorActuatorPage(
                    signalingUrl: widget.signalingUrl,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Row(
        children: [
          if (!_controlsOnRight) _buildControls(),
          Expanded(
            child: RepaintBoundary(
              key: _videoKey,
              child: RTCVideoView(_renderer),
            ),
          ),
          if (_controlsOnRight) _buildControls(),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
            onPressed: () => _sendCmd("U"),
            icon: const Icon(Icons.arrow_upward, color: Colors.white)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
                onPressed: () => _sendCmd("L"),
                icon: const Icon(Icons.arrow_back, color: Colors.white)),
            const SizedBox(width: 20),
            IconButton(
                onPressed: () => _sendCmd("R"),
                icon: const Icon(Icons.arrow_forward, color: Colors.white)),
          ],
        ),
        IconButton(
            onPressed: () => _sendCmd("D"),
            icon: const Icon(Icons.arrow_downward, color: Colors.white)),
      ],
    );
  }

  @override
  void dispose() {
    _renderer.dispose();
    _pc?.close();
    super.dispose();
  }
}
