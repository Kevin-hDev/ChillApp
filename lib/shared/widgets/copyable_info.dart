import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/design_tokens.dart';
import '../../i18n/locale_provider.dart';
import '../extensions/chill_theme.dart';

/// Ligne d'info avec bouton copier
class CopyableInfo extends StatefulWidget {
  final String value;
  final String? label;
  final bool compact;
  final String locale;

  const CopyableInfo({
    super.key,
    required this.value,
    this.label,
    this.compact = false,
    required this.locale,
  });

  @override
  State<CopyableInfo> createState() => _CopyableInfoState();
}

class _CopyableInfoState extends State<CopyableInfo> {
  bool _copied = false;

  void _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: context.chillBgSurface,
        borderRadius: BorderRadius.circular(ChillRadius.lg),
        border: Border.all(color: context.chillBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.value,
              style: GoogleFonts.jetBrainsMono(
                fontSize: widget.compact ? 13 : 15,
                fontWeight: FontWeight.w500,
                color: context.chillTextPrimary,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              _copied ? Icons.check : Icons.copy,
              color: _copied ? context.chillAccent : context.chillTextSecondary,
              size: 18,
            ),
            onPressed: _copy,
            tooltip: _copied
                ? t(widget.locale, 'info.copied')
                : t(widget.locale, 'info.copy'),
          ),
        ],
      ),
    );
  }
}
