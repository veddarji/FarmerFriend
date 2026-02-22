// lib/screens/spraying_module_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/rendering.dart';

enum ControlMode {
  spraying,
  actuator,
}

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

  String _status = "CONNECTING";
  bool _isRecording = false;
  MediaRecorder? _recorder;
  String? _recordingPath;
  bool _controlsVisible = true;
  ControlMode _currentMode = ControlMode.spraying;

  // Spray State
  bool _isPumpOn = false;
  bool _isAutoMode = false;
  double _servoH = 90;
  double _servoV = 90;

  final GlobalKey _videoKey = GlobalKey();
  final Color _primaryColor = const Color(0xFF7A6A3A);

  // Actuator State
  double _servoAngle = 90;

  // ================= INIT =================
  @override
  void initState() {
    super.initState();
    // Force landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
        _renderer.srcObject = event.streams[0];
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
        if (mounted) setState(() => _status = "ONLINE");
      }
    };

    _dc!.onMessage = (RTCDataChannelMessage message) {
      print("Message from rpi: ${message.text}");
    };

    // ================= OFFER =================
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    await Future.delayed(const Duration(milliseconds: 500));

    try {
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
    } catch (e) {
      if (mounted) setState(() => _status = "ERROR: $e");
    }
  }

  // ================= COMMAND =================
  void _sendCmd(String cmd, {int? angle}) {
    if (_dc == null || _dc!.state != RTCDataChannelState.RTCDataChannelOpen)
      return;

    final Map<String, dynamic> payload = {'cmd': cmd};
    if (angle != null) {
      payload['angle'] = angle;
    }

    _dc!.send(RTCDataChannelMessage(jsonEncode(payload)));
  }


  void _sendStopCommand() {
    // Send STOP multiple times to ensure delivery
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 50), () {
        if (mounted) _sendCmd("STOP");
      });
    }
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

    // Save to Gallery
    try {
      await Gal.putImage(file.path);
    } catch (e) {
      debugPrint("Error saving to gallery: $e");
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Photo saved to Gallery"),
          backgroundColor: _primaryColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ================= RECORD =================
  Future<void> _startRecording() async {
    if (_isRecording) return;

    final stream = _renderer.srcObject;
    if (stream == null) return;

    final dir = await getTemporaryDirectory();
    final path =
        "${dir.path}/record_${DateTime.now().millisecondsSinceEpoch}.mp4";

    _recordingPath = path;
    _recorder = MediaRecorder();
    await _recorder!.start(path, videoTrack: stream.getVideoTracks().first);

    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    await _recorder?.stop();
    setState(() => _isRecording = false);

    if (_recordingPath != null) {
      try {
        await Gal.putVideo(_recordingPath!);
        debugPrint("Video saved to gallery: $_recordingPath");
      } catch (e) {
        debugPrint("Error saving video to gallery: $e");
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Recording saved to Gallery"),
        backgroundColor: _primaryColor,
      ),
    );
  }

  // ================= UI BUILDERS =================

  Widget _buildGlassButton(
      {required IconData icon,
      required VoidCallback? onPressed,
      Color? color,
      String? tooltip,
      bool isPressed = false,
      bool isToggle = false}) {
    if (isToggle) {
      return GestureDetector(
        onTap: onPressed,
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isPressed
                ? (color ?? _primaryColor).withValues(alpha: 0.6)
                : Colors.black.withValues(alpha: 0.3),
            border: Border.all(
                color: isPressed
                    ? (color ?? _primaryColor)
                    : Colors.white.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                spreadRadius: 2,
              )
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: color ?? Colors.white, size: 28),
          ),
        ),
      );
    } else {
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (onPressed != null) onPressed();
        },
        onPointerUp: (_) {
          if (onPressed != null) _sendStopCommand();
        },
        onPointerCancel: (_) {
          if (onPressed != null) _sendStopCommand();
        },
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isPressed
                ? (color ?? _primaryColor).withValues(alpha: 0.6)
                : Colors.black.withValues(alpha: 0.3),
            border: Border.all(
                color: isPressed
                    ? (color ?? _primaryColor)
                    : Colors.white.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                spreadRadius: 2,
              )
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: color ?? Colors.white, size: 28),
          ),
        ),
      );
    }
  }

  Widget _buildTapButton(
      {required IconData icon,
      required VoidCallback onPressed,
      Color? color,
      String? tooltip}) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.3),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            spreadRadius: 2,
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(50),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: color ?? Colors.white, size: 28),
          ),
        ),
      ),
    );
  }

  Widget _buildSprayControls() {
    return Stack(
      children: [
        // Left Control Panel (Pump & Auto)
        Positioned(
          left: 48,
          bottom: 32,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildGlassButton(
                  icon: Icons.water_drop,
                  color: Colors.cyanAccent,
                  isPressed: _isPumpOn,
                  isToggle: true,
                  onPressed: () {
                    setState(() => _isPumpOn = !_isPumpOn);
                    _sendCmd(_isPumpOn ? "PUMP_ON" : "PUMP_OFF");
                  },
                  tooltip: "Pump",
                ),
                const SizedBox(height: 16),
                _buildGlassButton(
                  icon: Icons.smart_toy, // Auto icon
                  color: Colors.greenAccent,
                  isToggle: true,
                  isPressed: _isAutoMode,
                  onPressed: () {
                    setState(() => _isAutoMode = !_isAutoMode);
                    _sendCmd(_isAutoMode ? "AUTO_ON" : "AUTO_OFF");
                  },
                  tooltip: "Auto Mode",
                ),
              ],
            ),
          ),
        ),

        // Right Sliders (Vertical & Horizontal)
        Positioned(
          bottom: 32,
          right: 32,
          child: SizedBox(
            width: 200,
            height: 200,
            child: Stack(
              children: [
                // Vertical Slider (Right Edge)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 50, // Leave space for horizontal slider
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 12,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 14),
                          overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 24),
                        ),
                        child: Slider(
                          value: _servoV,
                          min: 0,
                          max: 180,
                          activeColor: _primaryColor,
                          inactiveColor: Colors.white10,
                          onChanged: (value) {
                            setState(() => _servoV = value);
                            _sendCmd("servo2", angle: value.toInt());
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                // Horizontal Slider (Bottom Edge)
                Positioned(
                  left: 0,
                  right: 40, // Leave space for vertical slider
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 12,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 14),
                        overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 24),
                      ),
                      child: Slider(
                        value: _servoH,
                        min: 0,
                        max: 180,
                        activeColor: _primaryColor,
                        inactiveColor: Colors.white10,
                        onChanged: (value) {
                          setState(() => _servoH = value);
                          _sendCmd("servo3", angle: value.toInt());
                        },
                      ),
                    ),
                  ),
                ),

                // Center/Corner Label or Icon
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _primaryColor.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: const Icon(Icons.open_with,
                        color: Colors.white70, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActuatorControls() {
    return Stack(
      children: [
        // Servo Slider (Left)
        Positioned(
          left: 24,
          bottom: 24,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_overscan, color: Colors.white70),
                const SizedBox(height: 16),
                SizedBox(
                  height: 160,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 12,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 14),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 24),
                      ),
                      child: Slider(
                        value: _servoAngle,
                        min: 0,
                        max: 180,
                        activeColor: _primaryColor,
                        inactiveColor: Colors.white10,
                        onChanged: (value) {
                          setState(() => _servoAngle = value);
                          _sendCmd("SERVO", angle: value.toInt());
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "${_servoAngle.toInt()}°",
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),

        // Motor D-Pad (Right)
        Positioned(
          bottom: 32,
          right: 48,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                Colors.white.withValues(alpha: 0.05),
                Colors.transparent,
              ]),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // CW (Up)
                Positioned(
                  top: 0,
                  child: _buildGlassButton(
                    icon: Icons.keyboard_arrow_up,
                    onPressed: () => _sendCmd("CW"),
                    color: _primaryColor,
                  ),
                ),
                // CCW (Down)
                Positioned(
                  bottom: 0,
                  child: _buildGlassButton(
                    icon: Icons.keyboard_arrow_down,
                    onPressed: () => _sendCmd("CCW"),
                    color: _primaryColor,
                  ),
                ),
                // LEFT
                Positioned(
                  left: 0,
                  child: _buildGlassButton(
                    icon: Icons.rotate_left,
                    onPressed: () => _sendCmd("M2_LEFT_START"),
                    color: _primaryColor,
                  ),
                ),
                // RIGHT
                Positioned(
                  right: 0,
                  child: _buildGlassButton(
                    icon: Icons.rotate_right,
                    onPressed: () => _sendCmd("M2_RIGHT_START"),
                    color: _primaryColor,
                  ),
                ),
                // Center Decoration
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _primaryColor.withValues(alpha: 0.5), width: 2),
                    color: Colors.black.withValues(alpha: 0.3),
                  ),
                  child: Icon(Icons.cached, color: _primaryColor),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            _buildTapButton(
              icon: Icons.arrow_back,
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "CONTROL CENTER",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _status == "ONLINE" ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _status,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(),

            // MODE TOGGLE
            Container(
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.2))),
              child: Row(
                children: [
                  _modeButton(ControlMode.spraying, Icons.water_drop, "SPRAY"),
                  _modeButton(ControlMode.actuator, Icons.settings, "MOTOR"),
                ],
              ),
            ),
            const SizedBox(width: 16),

            _buildTapButton(
              icon: Icons.camera_alt,
              onPressed: _capturePhoto,
              tooltip: "Snapshot",
            ),
            _buildTapButton(
              icon: _isRecording ? Icons.stop : Icons.fiber_manual_record,
              color: _isRecording ? Colors.redAccent : Colors.white,
              onPressed: _isRecording ? _stopRecording : _startRecording,
              tooltip: "Record",
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeButton(ControlMode mode, IconData icon, String label) {
    final isSelected = _currentMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _currentMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ]
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _controlsVisible = !_controlsVisible),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. VIDEO LAYER
            RepaintBoundary(
              key: _videoKey,
              child: RTCVideoView(
                _renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),

            // 2. OVERLAY CONTROLS
            AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Stack(
                children: [
                  // Top Bar
                  Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),

                  // Conditional Controls
                  if (_currentMode == ControlMode.spraying)
                    _buildSprayControls()
                  else
                    _buildActuatorControls(),

                  // Bottom Gradient
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 100,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.6),
                              Colors.transparent
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Reset orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    _renderer.dispose();
    _pc?.close();
    super.dispose();
  }
}
