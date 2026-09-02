import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/machine_row.dart';
import '../theme/console_theme.dart';
import '../theme/ld_icons.dart';

/// One line of terminal output.
class TerminalLine {
  const TerminalLine(this.text, {this.kind = TerminalLineKind.output});

  final String text;
  final TerminalLineKind kind;
}

enum TerminalLineKind { output, input, error, notice }

/// A terminal surface for one machine.
///
/// Presentational on purpose: it takes the buffer and hands back submitted
/// commands, so the real client can drive it from the PTY channel while the
/// same widget stays renderable and testable without the FFI layer.
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({
    super.key,
    required this.machine,
    required this.lines,
    this.connected = false,
    this.busy = false,
    this.onSubmit,
    this.onOpenSession,
  });

  final MachineRow? machine;
  final List<TerminalLine> lines;
  final bool connected;
  final bool busy;
  final ValueChanged<String>? onSubmit;
  final VoidCallback? onOpenSession;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  /// Command history, walked with the arrow keys the way a shell does.
  final List<String> _history = [];
  int _historyIndex = -1;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TerminalScreen old) {
    super.didUpdateWidget(old);
    if (widget.lines.length != old.lines.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  void _submit() {
    final text = _input.text.trim();
    if (text.isEmpty || widget.onSubmit == null) return;
    _history.add(text);
    _historyIndex = _history.length;
    widget.onSubmit!(text);
    _input.clear();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_history.isEmpty) return KeyEventResult.handled;
      _historyIndex = (_historyIndex - 1).clamp(0, _history.length - 1);
      _input.text = _history[_historyIndex];
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_history.isEmpty) return KeyEventResult.handled;
      _historyIndex = (_historyIndex + 1).clamp(0, _history.length);
      _input.text = _historyIndex >= _history.length ? '' : _history[_historyIndex];
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.machine == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The console's own terminal glyph, the bare prompt the sidebar
            // draws. Material's terminal_rounded puts that prompt inside a
            // window, so the empty state and the tab that leads to it were two
            // different marks for the same screen.
            const LdIcon(LdIcons.terminal, size: 26, color: C.textFaint),
            const SizedBox(height: 14),
            Text('No machine selected', style: C.h2()),
            const SizedBox(height: 6),
            // Fixed height, matching the health and actions screens: see the
            // note on HealthScreen's empty state.
            SizedBox(
              width: 320,
              height: 34,
              child: Text(
                'Choose a machine on the Fleet screen to open a shell on it.',
                textAlign: TextAlign.center,
                style: C.small(color: C.textFaint),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      child: Panel(
        title: 'Terminal',
        subtitle: 'On ${widget.machine!.displayName}',
        padding: EdgeInsets.zero,
        fill: true,
        actions: [
          if (!widget.connected)
            GhostButton(
              label: 'Open session',
              glyph: LdIcons.resume,
              busy: widget.busy,
              onPressed: widget.onOpenSession,
            ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: widget.lines.isEmpty
                  ? _Idle(connected: widget.connected)
                  : Scrollbar(
                      controller: _scroll,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                        itemCount: widget.lines.length,
                        itemBuilder: (context, i) => _Line(line: widget.lines[i]),
                      ),
                    ),
            ),
            Divider(height: 1, thickness: 1, color: C.hairline),
            _Prompt(
              controller: _input,
              focus: _focus,
              enabled: widget.connected && widget.onSubmit != null,
              onSubmit: _submit,
              onKey: _onKey,
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.line});

  final TerminalLine line;

  @override
  Widget build(BuildContext context) {
    final color = switch (line.kind) {
      TerminalLineKind.input => C.text,
      TerminalLineKind.error => C.bad,
      TerminalLineKind.notice => C.textFaint,
      TerminalLineKind.output => C.textMuted,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SelectableText(
        line.kind == TerminalLineKind.input ? '\$ ${line.text}' : line.text,
        style: C.data(size: 12.5, color: color),
      ),
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          connected
              ? 'Session open. Type a command below.'
              : 'No session. Open one to run commands on this machine.',
          style: C.small(color: C.textFaint),
        ),
      );
}

class _Prompt extends StatelessWidget {
  const _Prompt({
    required this.controller,
    required this.focus,
    required this.enabled,
    required this.onSubmit,
    required this.onKey,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool enabled;
  final VoidCallback onSubmit;
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Text('\$', style: C.data(size: 13, color: enabled ? C.accent : C.textFaint)),
          const SizedBox(width: 10),
          Expanded(
            child: Focus(
              onKeyEvent: onKey,
              child: TextField(
                controller: controller,
                focusNode: focus,
                enabled: enabled,
                onSubmitted: (_) => onSubmit(),
                style: C.data(size: 12.5, color: C.text),
                cursorColor: C.accent,
                cursorWidth: 1.6,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: enabled ? 'Run a command' : 'Open a session to type here',
                  hintStyle: C.data(size: 12.5, color: C.textFaint),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
