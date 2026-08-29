import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// LabDesk console design language.
///
/// This is an Operate surface: the operator is in a task, so the interface
/// should disappear into it. Familiarity is a feature here, and the character
/// lives in precise details rather than in expression.
///
/// The rules it holds itself to:
///   - One sans family carries headings, labels, buttons and body. Monospace is
///     reserved for things that are actually data: identifiers, timestamps,
///     measured values. Mono as a costume for "technical" is the tell.
///   - Restrained colour. One accent, used for primary action and current
///     selection only. Status colour is semantic and never decorative.
///   - One radius scale, applied everywhere.
///   - Real states on everything interactive: hover, focus, selected, disabled,
///     loading, empty.
class C {
  C._();

  // Surfaces. A cool near-black, never pure black, with a separate slightly
  // cooler layer for the chrome so the content plane reads as the subject.
  static const bg = Color(0xFF0E0E12);
  static const chrome = Color(0xFF121217);
  static const surface = Color(0xFF16161C);
  static const surfaceHi = Color(0xFF1D1D25);
  static const hairline = Color(0xFF262630);

  static const text = Color(0xFFEDEDF2);
  static const textMuted = Color(0xFF9C9CAB);
  static const textFaint = Color(0xFF6B6B7A);

  /// LabDesk's purple, pulled back from the branding to something that can sit
  /// behind data all day. Primary actions and current selection only.
  static const accent = Color(0xFF8B7DF7);
  static const accentDim = Color(0xFF5B4FBE);

  /// Semantic status. Never used as decoration.
  static const ok = Color(0xFF3FCF8E);
  static const bad = Color(0xFFF06A6A);
  static const idle = Color(0xFF6B6B7A);

  static const radius = 8.0;
  static const radiusSm = 6.0;
  static final rounded = BorderRadius.circular(radius);
  static final roundedSm = BorderRadius.circular(radiusSm);

  static const fast = Duration(milliseconds: 140);
  static const medium = Duration(milliseconds: 220);

  // A fixed scale with a tight ratio. Product UI is viewed at a consistent
  // size, so fluid type would only add noise.
  static TextStyle h1() => GoogleFonts.manrope(
      fontSize: 20, fontWeight: FontWeight.w700, color: text, letterSpacing: -0.4, height: 1.2);
  static TextStyle h2() => GoogleFonts.manrope(
      fontSize: 15, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.2, height: 1.3);
  static TextStyle body({Color color = text}) => GoogleFonts.manrope(
      fontSize: 13.5, fontWeight: FontWeight.w500, color: color, height: 1.45);
  static TextStyle small({Color color = textMuted, FontWeight w = FontWeight.w500}) =>
      GoogleFonts.manrope(fontSize: 12, fontWeight: w, color: color, height: 1.4);
  static TextStyle micro({Color color = textFaint}) => GoogleFonts.manrope(
      fontSize: 11, fontWeight: FontWeight.w600, color: color, height: 1.3);

  /// Identifiers, timestamps, measured values. Tabular so a column of figures
  /// does not jitter as it updates.
  static TextStyle data({double size = 12.5, Color color = text, FontWeight w = FontWeight.w500}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: w,
        color: color,
        height: 1.35,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// A large measured number.
  static TextStyle metric({Color color = text}) => GoogleFonts.manrope(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.8,
        height: 1.0,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static ThemeData theme() {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: hairline,
      colorScheme: base.colorScheme.copyWith(
        surface: surface,
        primary: accent,
        error: bad,
        outline: hairline,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: surfaceHi,
          borderRadius: roundedSm,
          border: Border.all(color: hairline),
          // Depth carries an offset and a soft blur; a zero-offset halo is
          // decoration, not elevation.
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 6)),
          ],
        ),
        textStyle: small(color: text),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(hairline),
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(4),
      ),
    );
  }
}

/// A titled panel. The structural unit of the console.
///
/// No eyebrow above the title: the title carries its own weight.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 18),
    this.fill = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;
  final EdgeInsets padding;

  /// Consume the height offered. Required when the body scrolls, otherwise the
  /// column sizes to its children and hands the body an unbounded height.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: C.rounded,
        border: Border.all(color: C.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 12, 14),
            child: Row(
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: C.h2()),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(subtitle!, style: C.small(color: C.textFaint)),
                      ],
                    ],
                  ),
                ),
                const Spacer(),
                if (actions != null) ...actions!,
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: C.hairline),
          if (fill)
            Expanded(child: Padding(padding: padding, child: child))
          else
            Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// A quiet secondary button with the full state set.
class GhostButton extends StatefulWidget {
  const GhostButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  State<GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<GhostButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final fg = !enabled ? C.textFaint : (_hover ? C.text : C.textMuted);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: C.fast,
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _down ? 1 : 0, 0),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: _hover && enabled ? C.surfaceHi : Colors.transparent,
            borderRadius: C.roundedSm,
            border: Border.all(color: _hover && enabled ? C.hairline : C.hairline.withOpacity(0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.busy)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.6, color: C.accent),
                )
              else if (widget.icon != null)
                Icon(widget.icon, size: 14, color: fg),
              if (widget.busy || widget.icon != null) const SizedBox(width: 7),
              Text(widget.label, style: C.small(color: fg, w: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
