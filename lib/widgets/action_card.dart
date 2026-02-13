// lib/widgets/action_card.dart
import 'package:flutter/material.dart';

class ActionCard extends StatefulWidget {
  final String title;
  final String iconPath;
  final Color accentColor;
  final VoidCallback onTap;

  const ActionCard(
      {super.key,
      required this.title,
      required this.iconPath,
      required this.accentColor,
      required this.onTap});

  @override
  State<ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<ActionCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 120),
        lowerBound: 0.0,
        upperBound: 0.04);
    _scale = Tween<double>(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (_busy) return;
    _busy = true;
    widget.onTap();
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: _handleTap,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(0.06),
                      Colors.white.withOpacity(0.02)
                    ]),
                border: Border.all(color: Colors.white10),
                boxShadow: [
                  BoxShadow(
                      color: widget.accentColor.withOpacity(0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 8))
                ],
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black26,
                            border: Border.all(
                                color: widget.accentColor.withOpacity(0.4))),
                        child: Image.asset(widget.iconPath,
                            width: 28, height: 28)),
                    const Spacer(),
                    Text(widget.title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Container(
                        height: 3,
                        width: 34,
                        decoration: BoxDecoration(
                            color: widget.accentColor,
                            borderRadius: BorderRadius.circular(2))),
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}
