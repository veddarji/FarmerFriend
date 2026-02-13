// lib/services/auth.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Auth {
  Auth._private();
  static final Auth _instance = Auth._private();
  factory Auth() => _instance;

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  String? username;
  String? password;

  static const String _kUserKey = 'farmrover_user';
  static const String _kPassKey = 'farmrover_pass';

  Future<void> init() async {
    try {
      final u = await _secure.read(key: _kUserKey);
      final p = await _secure.read(key: _kPassKey);
      if (u != null && p != null) {
        username = u;
        password = p;
        if (kDebugMode) debugPrint('Auth: loaded credentials for $u');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Auth.init error: $e');
    }
  }

  bool get isLoggedIn => username != null && password != null;

  Future<void> setCredentials(
      {required String user,
      required String pass,
      bool remember = false}) async {
    username = user;
    password = pass;
    if (remember) {
      try {
        await _secure.write(key: _kUserKey, value: user);
        await _secure.write(key: _kPassKey, value: pass);
      } catch (e) {
        if (kDebugMode) debugPrint('Auth.setCredentials write error: $e');
      }
    } else {
      await clearPersisted();
    }
  }

  Future<void> clear({bool clearPersistedToo = true}) async {
    username = null;
    password = null;
    if (clearPersistedToo) {
      await clearPersisted();
    }
  }

  Future<void> clearPersisted() async {
    try {
      await _secure.delete(key: _kUserKey);
      await _secure.delete(key: _kPassKey);
    } catch (e) {
      if (kDebugMode) debugPrint('Auth.clearPersisted error: $e');
    }
  }
}
