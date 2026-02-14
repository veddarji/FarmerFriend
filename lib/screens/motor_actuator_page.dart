// lib/screens/motor_actuator_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

class MotorActuatorPage extends StatefulWidget {
  final String signalingUrl; // http://<tailscale-ip>:8080/offer

  const MotorActuatorPage({
    super.key,
    required this.signalingUrl,
  });

  @override
  State<MotorActuatorPage> createState() => _MotorActuatorPageState();
}

class _MotorActuatorPageState extends State<MotorActuatorPage> {
  late RTCVideoRenderer _renderer;
  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;

  bool _controlsOnRight = true;
  bool _sprayOn = false;
  String _status = 'CONNECTING';
  double _servoAngle = 0;

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

    // 🔥 VERY IMPORTANT
    await _pc!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _renderer.srcObject = event.streams[0];
      }
    };

    RTCDataChannelInit dcInit = RTCDataChannelInit()
      ..ordered = false
      ..maxRetransmits = 0;

    _dataChannel = await _pc!.createDataChannel("control", dcInit);

    _dataChannel!.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        setState(() => _status = "ONLINE");
      }
    };

    await _createOffer();
  }

  Future<void> _createOffer() async {
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    await Future.delayed(const Duration(milliseconds: 500));

    final response = await http.post(
      Uri.parse(widget.signalingUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sdp': offer.sdp,
        'type': offer.type,
      }),
    );

    final data = jsonDecode(response.body);

    await _pc!.setRemoteDescription(
      RTCSessionDescription(data['sdp'], data['type']),
    );
  }

  // ================= COMMAND SEND =================
  void _sendCommand(String cmd, {int? angle}) {
    if (_dataChannel == null ||
        _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }

    final payload = {
      'cmd': cmd,
      if (angle != null) 'angle': angle,
    };

    _dataChannel!.send(
      RTCDataChannelMessage(jsonEncode(payload)),
    );
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Row(
                children: _controlsOnRight
                    ? [_buildVideoPanel(), _buildJoystickPanel()]
                    : [_buildJoystickPanel(), _buildVideoPanel()],
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.security, color: Colors.amber),
          const SizedBox(width: 12),
          Text(
            'STATUS: $_status',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Switch(
            value: _controlsOnRight,
            activeColor: Colors.amber,
            onChanged: (v) => setState(() => _controlsOnRight = v),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPanel() {
    return Expanded(
      flex: 3,
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: RTCVideoView(_renderer),
        ),
      ),
    );
  }

  Widget _buildJoystickPanel() {
    return Expanded(
      flex: 2,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _joyBtn(Icons.keyboard_arrow_up, "CW"),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _joyBtn(Icons.keyboard_arrow_left, "M2_LEFT_START"),
                const SizedBox(width: 40),
                _joyBtn(Icons.keyboard_arrow_right, "M2_RIGHT_START"),
              ],
            ),
            const SizedBox(height: 20),
            _joyBtn(Icons.keyboard_arrow_down, "CCW"),
          ],
        ),
      ),
    );
  }

  Widget _joyBtn(IconData icon, String cmd) {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.mediumImpact();
        _sendCommand(cmd);
      },
      onTapUp: (_) => _sendCommand("STOP"),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.amber, width: 2),
        ),
        child: Icon(icon, color: Colors.amber, size: 36),
      ),
    );
  }

  Widget _buildFooter() {
    return Slider(
      value: _servoAngle,
      min: 0,
      max: 180,
      activeColor: Colors.amber,
      onChanged: (value) {
        setState(() => _servoAngle = value);
        _sendCommand("SERVO", angle: value.toInt());
      },
    );
  }

  @override
  void dispose() {
    _dataChannel?.close();
    _pc?.close();
    _renderer.dispose();
    super.dispose();
  }
}
