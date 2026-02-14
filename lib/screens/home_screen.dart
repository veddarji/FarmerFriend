// lib/screens/home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import '../widgets/action_card.dart';
import '../services/auth.dart';
import 'login_screen.dart';
import 'spraying_module_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  Color primary = const Color(0xFF7A6A3A);
  Color secondary = const Color(0xFF4A4A2A);
  final Color background = const Color(0xFF0B0B0B);

  late final AnimationController _entranceController;
  bool _colorsLoaded = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    _entranceController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _entranceController.forward();
    _extractPalette();
  }

  Future<void> _extractPalette() async {
    try {
      final generator = await PaletteGenerator.fromImageProvider(
          const AssetImage('assets/images/logo.png'),
          maximumColorCount: 20);
      if (!mounted) return;
      setState(() {
        primary = generator.lightVibrantColor?.color ??
            generator.vibrantColor?.color ??
            generator.dominantColor?.color ??
            primary;
        secondary = generator.darkVibrantColor?.color ??
            generator.mutedColor?.color ??
            secondary;
        _colorsLoaded = true;
      });
    } catch (e) {
      if (mounted) setState(() => _colorsLoaded = true);
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 700)));
  }

  void _openSprayingModule() {
    debugPrint('SPRAY SYSTEM tapped - navigating');

    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SprayingModulePage(
              signalingUrl: "http://100.93.20.61:8080/offer",
            )));
  }

  Future<void> _openLogin() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LoginScreen()));
    if (mounted) setState(() {});
  }

  Widget _buildHeader(double width) {
    final dot = Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: primary, shape: BoxShape.circle));
    return FadeTransition(
      opacity:
          CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
                height: 64,
                width: 64,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white10,
                    border: Border.all(color: Colors.white12),
                    image: const DecorationImage(
                        image: AssetImage('assets/images/logo.png'),
                        fit: BoxFit.cover))),
            const SizedBox(width: 16),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('FARMER FRIEND',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0)),
                  const SizedBox(height: 6),
                  Row(children: [
                    dot,
                    const SizedBox(width: 8),
                    Text('SYSTEM ONLINE',
                        style: TextStyle(
                            color: primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700))
                  ])
                ])),
            if (Auth().isLoggedIn)
              const Icon(Icons.lock, color: Colors.white70),
            IconButton(
                onPressed: () => _showSnack('Profile tapped'),
                icon: const Icon(Icons.person_outline, color: Colors.white),
                tooltip: 'Profile'),
            const SizedBox(width: 6),
            IconButton(
                onPressed: _openLogin,
                icon:
                    const Icon(Icons.settings_outlined, color: Colors.white70),
                tooltip: 'Settings (open login)'),
          ],
        ),
      ),
    );
  }

  Widget _buildActionGrid(double availableWidth, double availableHeight) {
    final crossAxisCount = (availableWidth < 600) ? 1 : 2;
    final cardAspect = (availableWidth < 600) ? 2.8 : 1.05;

    return GridView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        physics: const BouncingScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: cardAspect,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16),
        children: [
          _buildAnimatedCard(
              0, 'SPRAY\nSYSTEM', 'assets/images/icons/spray_icon.png', primary,
              onTap: _openSprayingModule),
          _buildAnimatedCard(1, 'OPTICAL\nFEED',
              'assets/images/icons/camera_icon.png', secondary),
          _buildAnimatedCard(2, 'MANUAL\nDRIVE',
              'assets/images/icons/drive_icon.png', Colors.amberAccent),
          _buildAnimatedCard(3, 'DATA\nLOGS',
              'assets/images/icons/logs_icon.png', Colors.purpleAccent),
        ]);
  }

  Widget _buildAnimatedCard(
      int index, String title, String iconPath, Color color,
      {VoidCallback? onTap}) {
    final anim = CurvedAnimation(
        parent: _entranceController,
        curve: Interval(0.15 + index * 0.08, 1.0, curve: Curves.easeOutBack));
    return SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
            .animate(anim),
        child: ActionCard(
            title: title,
            iconPath: iconPath,
            accentColor: color,
            onTap: onTap ?? () => _showSnack('$title selected')));
  }

  Widget _buildStatusChips() {
    return SizedBox(
        height: 52,
        child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              _GlassChip(
                  icon: Icons.battery_full, label: '87% POWER', color: primary),
              const SizedBox(width: 12),
              _GlassChip(
                  icon: Icons.wifi, label: 'CONNECTED', color: secondary),
              const SizedBox(width: 12),
              _GlassChip(
                  icon: Icons.speed, label: 'TURBO', color: Colors.orange),
              const SizedBox(width: 12),
              _GlassChip(
                  icon: Icons.cloud,
                  label: 'CLOUD OK',
                  color: Colors.tealAccent),
            ]));
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final availW = mq.size.width;
    return Scaffold(
        backgroundColor: background,
        body: Stack(children: [
          const _AnimatedBackground(),
          SafeArea(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _buildHeader(availW),
                const SizedBox(height: 10),
                _buildStatusChips(),
                const SizedBox(height: 12),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Row(children: [
                      Text('COMMAND CENTER',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              letterSpacing: 2,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Container(height: 1, color: Colors.white10)),
                    ])),
                const SizedBox(height: 12),
                Expanded(
                    child: LayoutBuilder(
                        builder: (context, constraints) => _buildActionGrid(
                            constraints.maxWidth, constraints.maxHeight))),
              ]))
        ]));
  }
}

class _GlassChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _GlassChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: color.withOpacity(0.28))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12)),
        ]));
  }
}

class _AnimatedBackground extends StatelessWidget {
  const _AnimatedBackground();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF071216),
            Color(0xFF0D2630),
            Color(0xFF12363E),
          ],
        ),
      ),
    );
  }
}
