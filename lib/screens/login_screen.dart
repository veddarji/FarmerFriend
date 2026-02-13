// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import '../services/auth.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtl = TextEditingController();
  final _passCtl = TextEditingController();
  bool _remember = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _userCtl.text = Auth().username ?? '';
    _passCtl.text = Auth().password ?? '';
    _remember = Auth().isLoggedIn;
  }

  @override
  void dispose() {
    _userCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final user = _userCtl.text.trim();
    final pass = _passCtl.text;
    setState(() => _error = null);

    if (user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please enter username and password');
      return;
    }

    setState(() => _loading = true);

    // Optionally verify credentials here by pinging the control endpoint.
    await Auth().setCredentials(user: user, pass: pass, remember: _remember);

    setState(() => _loading = false);
    if (!mounted) return;

    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      body: SafeArea(
        child: Center(
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Sign in',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: _userCtl,
                decoration: const InputDecoration(
                    hintText: 'Username',
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(borderSide: BorderSide.none)),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passCtl,
                obscureText: true,
                decoration: const InputDecoration(
                    hintText: 'Password',
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(borderSide: BorderSide.none)),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Checkbox(
                    value: _remember,
                    onChanged: (v) => setState(() => _remember = v ?? false),
                    fillColor: MaterialStateProperty.all(Colors.white24)),
                const SizedBox(width: 4),
                const Text('Remember (store securely)',
                    style: TextStyle(color: Colors.white70)),
              ]),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Sign in'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
