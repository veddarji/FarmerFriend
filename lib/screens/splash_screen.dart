// lib/screens/splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import '../services/auth.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Color? _backgroundColor;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _prepareSplash();
  }

  Future<void> _prepareSplash() async {
    final imageProvider = const AssetImage('assets/images/logo.png');

    try {
      final generator = await PaletteGenerator.fromImageProvider(imageProvider,
          maximumColorCount: 20);
      Color? chosen =
          generator.dominantColor?.color ?? generator.mutedColor?.color;
      chosen ??= const Color(0xFF10242A);

      final brightness = ThemeData.estimateBrightnessForColor(chosen);
      final overlayStyle = (brightness == Brightness.dark)
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark;
      SystemChrome.setSystemUIOverlayStyle(overlayStyle);

      if (mounted) setState(() => _backgroundColor = chosen);
    } catch (e) {
      if (mounted) setState(() => _backgroundColor = const Color(0xFF10242A));
    }

    Timer(const Duration(seconds: 3), () {
      if (!_navigated && mounted) {
        _navigated = true;
        if (Auth().isLoggedIn) {
          Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const HomeScreen()));
        } else {
          Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const LoginScreen()));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = _backgroundColor ?? const Color(0xFF10242A);
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/images/logo.png',
                width: 160, fit: BoxFit.contain),
            const SizedBox(height: 20),
            Text('Farmer Friend',
                style: TextStyle(
                    fontSize: 20,
                    color: ThemeData.estimateBrightnessForColor(bg) ==
                            Brightness.dark
                        ? Colors.white
                        : Colors.black)),
          ]),
        ),
      ),
    );
  }
}
