import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Message "Cela peut prendre plusieurs minutes" avec animation fade
class PatienceMessage extends StatefulWidget {
  final String text;
  final Color color;

  const PatienceMessage({super.key, required this.text, required this.color});

  @override
  State<PatienceMessage> createState() => _PatienceMessageState();
}

class _PatienceMessageState extends State<PatienceMessage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _opacityAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeTransition(
        opacity: _opacityAnimation,
        child: Text(
          widget.text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}
