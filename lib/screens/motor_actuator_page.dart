// lib/screens/motor_actuator_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../widgets/mjpeg_viewer.dart';

class MotorActuatorPage extends StatefulWidget {
  final String streamUrl;
  final String controlEndpoint;
  final String? mjpegUsername;
  final String? mjpegPassword;

  const MotorActuatorPage({
    super.key,
    required this.streamUrl,
    required this.controlEndpoint,
    this.mjpegUsername,
    this.mjpegPassword,
  });

  @override
  State<MotorActuatorPage> createState() => _MotorActuatorPageState();
}

class _MotorActuatorPageState extends State<MotorActuatorPage> {
  bool _controlsOnRight = true;
  bool _sprayOn = false;
  String _status = 'OFFLINE';
  double _servoAngle = 0;

  void _setStatus(String s) {
    if (!mounted) return;
    setState(() => _status = s.toUpperCase());
  }

  Future<void> _sendCommand(Map<String, dynamic> payload) async {
    try {
      final uri = Uri.parse('${widget.controlEndpoint}/command');
      final headers = {'Content-Type': 'application/json'};

      if (widget.mjpegUsername != null && widget.mjpegPassword != null) {
        final auth = base64Encode(
          utf8.encode('${widget.mjpegUsername}:${widget.mjpegPassword}'),
        );
        headers['Authorization'] = 'Basic $auth';
      }

      await http.post(uri, headers: headers, body: jsonEncode(payload));
    } catch (_) {
      _setStatus('OFFLINE');
    }
  }

  Future<void> _sendDirection(String cmd) async {
    HapticFeedback.mediumImpact();
    _sendCommand({'cmd': cmd});
  }

  void _toggleSpray() {
    setState(() => _sprayOn = !_sprayOn);
    _sendCommand({'cmd': _sprayOn ? 'SPRAY_ON' : 'SPRAY_OFF'});
    HapticFeedback.heavyImpact();
  }

  void _setServo(double value) {
    setState(() => _servoAngle = value);
    _sendCommand({'cmd': 'SERVO', 'angle': value.toInt()});
  }

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

  // ================= HEADER =================
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          const Icon(Icons.security, color: Colors.amber),
          const SizedBox(width: 12),
          const Text(
            'ACTUATOR PRO V2',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),

          GestureDetector(
            onTap: _toggleSpray,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.amber, width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.water_drop,
                      size: 16, color: Colors.amber),
                  const SizedBox(width: 6),
                  Text(
                    _sprayOn ? 'SPRAY ON' : 'SPRAY OFF',
                    style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),
          Switch(
            value: _controlsOnRight,
            activeColor: Colors.amber,
            onChanged: (v) => setState(() => _controlsOnRight = v),
          ),
        ],
      ),
    );
  }

  // ================= VIDEO =================
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
          child: MJPEGViewer(
            url: widget.streamUrl,
            username: widget.mjpegUsername,
            password: widget.mjpegPassword,
          ),
        ),
      ),
    );
  }

  // ================= JOYSTICK (FIXED) =================
  Widget _buildJoystickPanel() {
    return Expanded(
      flex: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40), // ✅ FIX
        child: LayoutBuilder(builder: (context, c) {
          final cx = c.maxWidth / 2;
          final cy = c.maxHeight / 2;
          const size = 80.0;
          const spread = 80.0; // ✅ REDUCED

          return Stack(
            clipBehavior: Clip.none,
            children: [
              _joyBtn(cx, cy - spread, Icons.keyboard_arrow_up, 'UP', 'CW', size),
              _joyBtn(
                  cx, cy + spread, Icons.keyboard_arrow_down, 'DOWN', 'CCW', size),
              _joyBtn(
                  cx - spread,
                  cy,
                  Icons.keyboard_arrow_left,
                  'LEFT',
                  'M2_LEFT',
                  size),
              _joyBtn(
                  cx + spread,
                  cy,
                  Icons.keyboard_arrow_right,
                  'RIGHT',
                  'M2_RIGHT',
                  size),
            ],
          );
        }),
      ),
    );
  }

  Widget _joyBtn(double x, double y, IconData icon, String label,
      String cmd, double size) {
    return Positioned(
      left: x - size / 2,
      top: y - size / 2,
      child: Column(
        children: [
          GestureDetector(
            onTapDown: (_) => _sendDirection(cmd),
            onTapUp: (_) => _sendDirection('STOP'),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.amber, width: 2),
                color: const Color(0xFF1A1A1A),
              ),
              child: Icon(icon, color: Colors.amber, size: 36),
            ),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ================= FOOTER =================
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          _statusPill(),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SERVO ${_servoAngle.toInt()}°',
                    style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                Slider(
                  value: _servoAngle,
                  min: 0,
                  max: 180,
                  activeColor: Colors.amber,
                  inactiveColor: Colors.white12,
                  onChanged: _setServo,
                ),
              ],
            ),
          ),
          const Icon(Icons.lock, color: Colors.greenAccent, size: 14),
          const SizedBox(width: 6),
          const Text('ENCRYPTED',
              style: TextStyle(color: Colors.white12, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _statusPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red),
      ),
      child: const Text('OFFLINE',
          style: TextStyle(
              color: Colors.red,
              fontSize: 11,
              fontWeight: FontWeight.bold)),
    );
  }
}
