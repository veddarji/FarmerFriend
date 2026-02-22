// lib/services/pi_discovery.dart
import 'dart:async';
import 'dart:io';

class PiDiscovery {
  static const int _discoveryPort = 5005;
  static const String _probeMessage = 'FARM_ROVER_DISCOVER';
  static const String _expectedReply = 'FARM_ROVER_PI';

  /// Tries to discover Raspberry Pi on LAN using UDP broadcast.
  /// Returns something like: "http://192.168.1.50:8001" or null if not found.
  static Future<String?> discoverControlEndpoint({
    int apiPort = 8001,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      // Send discovery probe as broadcast
      socket.send(
        _probeMessage.codeUnits,
        InternetAddress('255.255.255.255'),
        _discoveryPort,
      );

      final completer = Completer<InternetAddress?>();

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          Datagram? datagram = socket?.receive();
          if (datagram == null) return;

          final msg = String.fromCharCodes(datagram.data).trim();
          if (msg == _expectedReply && !completer.isCompleted) {
            completer.complete(datagram.address);
          }
        }
      });

      final addr =
          await completer.future.timeout(timeout, onTimeout: () => null);

      socket.close();

      if (addr == null) return null;
      return 'http://${addr.address}:$apiPort';
    } catch (e) {
      socket?.close();
      return null;
    }
  }
}
