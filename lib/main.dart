// lib/main.dart
import 'package:flutter/material.dart';
import 'services/auth.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // load persisted credentials (if any)
  await Auth().init();

  runApp(const FarmerFriendApp());
}

class FarmerFriendApp extends StatelessWidget {
  const FarmerFriendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Farmer Friend',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF071216),
        colorScheme:
            ColorScheme.fromSwatch().copyWith(primary: const Color(0xFF7A6A3A)),
      ),
      home: const SplashScreen(),
    );
  }
}
