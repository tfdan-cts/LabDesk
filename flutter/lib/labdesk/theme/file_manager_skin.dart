import 'package:flutter/material.dart';

import 'console_theme.dart';
import 'ld_icons.dart';

/// The look of the file-transfer window.
///
/// Two directory listings and a queue of jobs, which makes this the most
/// data-dense surface in the product and the one where the console's rules
/// earn the most: one hairline, one radius, one accent, monospace on the
/// things that are measured and nowhere else.
///
/// The pieces take plain values and know nothing about the FFI, for the same
/// reason the toolbar's do: `desktop/pages/file_manager_page.dart` needs a live
/// session and the app's shared `common.dart`, so the window could not be
/// looked at. `tool/shots/filemanager_test.dart` renders these, the page builds
/// from them, and what the shot shows is what ships.
class FmSkin {
  FmSkin._();

  /// A file row is read, not just clicked: name, modified and size have to sit
  /// on one line with air around them. RustDesk's 30 was a Material list
  /// density that left the three columns touching.
  static const rowHeight = 44.0;

  /// The column head band. Shorter than a row on purpose — it is a label
  /// strip, not the first line of data.
  static const headerHeight = 30.0;

  /// The strip that names which machine a pane is showing.
  static const paneHeaderHeight = 46.0;

  static const toolButtonSize = 30.0;
  static const toolGlyphSize = 17.0;

  /// The gap between the two panes and the job queue, and between the group
  /// and the window edge.
  static const gap = 7.0;

  /// A pane, and the job queue: the same plane, the same hairline, the same
  /// radius. Nothing in this window is a floating card.
  static BoxDecoration get panel => BoxDecoration(
        color: C.surface,
        borderRadius: C.rounded,
        border: Border.all(color: C.hairline),
      );

  /// The path field and the search field: recessed to the background plane so
  /// they read as something to type into rather than as another panel.
  static BoxDecoration get field => BoxDecoration(
        color: C.bg,
        borderRadius: C.roundedSm,
        border: Border.all(color: C.hairline),
      );

  /// A column head, and every other small label that names a thing rather than
  /// being the thing.
  static TextStyle head({Color color = C.textFaint}) =>
      C.micro(color: color).copyWith(letterSpacing: 0.8);
}

/// Glyphs this window needs that the console's set does not carry yet.
///
/// Drawn to the same system as [LdIcons] — 24x24 box, 20x20 optical area, one
/// stroke weight, square corners at radius 2 — so they can move into that file
/// unchanged once anything else needs them. The folder is [LdIcons.fileTransfer]'s
/// folder with the arrow taken out, so the two cannot drift.
class FmGlyphs {
  FmGlyphs._();

  /// A directory.
  static const folder = LdIcons.folder;

  /// A file: a sheet with the corner turned, which is the only mark that
  /// separates it from a folder at 16px without relying on colour.
  static const file = LdIcons.file;

  /// A volume. A bay with its lamp lit, not a floppy disk.
  static const drive = LdIcons.drive;

  /// The home directory of whichever machine the pane is showing.
  static const home = LdIcons.home;

  /// Start a paused job again.
  static const resume = LdIcons.resume;
}

/// One square control in a pane's toolbar.
///
/// A glyph on the pane surface and nothing else at rest; hover raises the same
/// quiet pad the session toolbar uses, so the two windows agree about what a
/// control under the cursor looks like. The filled chip behind every icon —
/// which is what RustDesk drew here — is what made a row of eight controls
/// read as eight buttons instead of one toolbar.
class FmToolButton extends StatefulWidget {
  const FmToolButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
    this.glyphSize,
  });

  /// A path from [LdIcons] or [FmGlyphs].
  final String glyph;

  /// Already translated.
  final String tooltip;
  final VoidCallback? onPressed;

  /// Destructive. Red only under the cursor: a red mark sitting on a control
  /// nobody has reached for is shouting about a file it has not been asked to
  /// delete.
  final bool danger;
  final double? glyphSize;

  @override
  State<FmToolButton> createState() => _FmToolButtonState();
}

class _FmToolButtonState extends State<FmToolButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final fg = !enabled
        ? C.textFaint.withOpacity(0.55)
        : _hover
            ? (widget.danger ? C.bad : C.text)
            : C.textMuted;
    // No tooltip rather than an empty one: a Material tooltip with an empty
    // message still opens an empty box under the cursor, which is what the
    // controls that carry no message used to do.
    final button = MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: C.fast,
            curve: Curves.easeOut,
            width: FmSkin.toolButtonSize,
            height: FmSkin.toolButtonSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover && enabled ? C.surfaceHi : Colors.transparent,
              borderRadius: C.roundedSm,
              border: Border.all(
                  color: _hover && enabled ? C.hairline : Colors.transparent),
            ),
            child: LdIcon(widget.glyph,
                size: widget.glyphSize ?? FmSkin.toolGlyphSize, color: fg),
          ),
        ));
    return widget.tooltip.isEmpty
        ? button
        : Tooltip(
            message: widget.tooltip,
            waitDuration: const Duration(milliseconds: 300),
            child: button,
          );
  }
}

/// The one consequential control in a pane: send this selection to the other
/// machine.
///
/// It is the only filled surface in the window, which is the whole reason it
/// can be found. Disabled it keeps its shape and stops claiming it can act —
/// the old button dimmed the accent instead, so an empty selection and a full
/// one differed by twenty per cent of one colour.
class FmSendButton extends StatefulWidget {
  const FmSendButton({
    super.key,
    required this.label,
    required this.glyph,
    required this.onPressed,
    this.reversed = false,
    this.quarterTurns = 0,
  });

  /// Already translated.
  final String label;
  final String glyph;
  final VoidCallback? onPressed;

  /// Glyph first. The two panes mirror each other, so the arrow always sits on
  /// the side the files are leaving by.
  final bool reversed;

  /// The direction the arrow points, in quarter turns of [LdIcons.arrowRight].
  final int quarterTurns;

  @override
  State<FmSendButton> createState() => _FmSendButtonState();
}

class _FmSendButtonState extends State<FmSendButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final fg = enabled ? C.bg : C.textFaint;
    final glyph = RotatedBox(
      quarterTurns: widget.quarterTurns,
      child: LdIcon(widget.glyph, size: 16, color: fg),
    );
    final text = Text(widget.label, style: C.small(color: fg, w: FontWeight.w700));

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: C.fast,
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _down ? 1 : 0, 0),
          height: FmSkin.toolButtonSize,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: !enabled
                ? Colors.transparent
                : (_hover ? const Color(0xFF9C90F8) : C.accent),
            borderRadius: C.roundedSm,
            border: Border.all(color: enabled ? Colors.transparent : C.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: widget.reversed
                ? [glyph, const SizedBox(width: 8), text]
                : [text, const SizedBox(width: 8), glyph],
          ),
        ),
      ),
    );
  }
}

/// The frame around a pane, and around the queue beside them.
///
/// One margin, one hairline, one radius, and a clip — so the column-head band
/// can run to the panel's own edges instead of floating inside it.
class FmPane extends StatelessWidget {
  const FmPane({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.all(FmSkin.gap),
        clipBehavior: Clip.antiAlias,
        decoration: FmSkin.panel,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

/// Which machine a pane is showing, and — over the queue, where there is no
/// machine to name — what the column beside them holds.
///
/// The platform mark is a tile on the surface ramp, not a filled accent square:
/// the accent in this window means "this is the action", and spending it twice
/// on a decorative badge is what made the old pane header the loudest thing on
/// screen.
class FmPaneHeader extends StatelessWidget {
  const FmPaneHeader({
    super.key,
    required this.title,
    this.badge,
    this.trailing,
  });

  /// Already translated.
  final String title;

  /// The platform image, or whatever stands in while it is being fetched.
  final Widget? badge;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: FmSkin.paneHeaderHeight,
      padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: C.hairline)),
      ),
      child: Row(
        children: [
          if (badge != null) ...[
            Container(
              width: 26,
              height: 26,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: C.surfaceHi,
                borderRadius: C.roundedSm,
                border: Border.all(color: C.hairline),
              ),
              child: badge,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(title,
                style: C.h2(), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// One column head, and the sort it carries.
///
/// Set as a label rather than as body text, because a head that looks like data
/// is a row the eye tries to read. The sorted column is the only one that takes
/// the accent, and it takes it on the word as well as on the chevron so the
/// sort survives a glance at the arrow alone.
class FmColumnHead extends StatelessWidget {
  const FmColumnHead({
    super.key,
    required this.label,
    required this.ascending,
    required this.onTap,
    this.width,
    this.alignEnd = false,
  });

  /// Already translated.
  final String label;

  /// Null when this column is not the one being sorted by.
  final bool? ascending;
  final VoidCallback onTap;
  final double? width;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final sorted = ascending != null;
    final child = SizedBox(
      width: width,
      height: FmSkin.headerHeight,
      child: Row(
        mainAxisAlignment:
            alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              label.toUpperCase(),
              style: FmSkin.head(color: sorted ? C.accent : C.textFaint),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 12,
            child: sorted
                ? LdIcon(ascending! ? LdIcons.chevronUp : LdIcons.chevronDown,
                    size: 12, color: C.accent)
                : null,
          ),
        ],
      ),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: child),
    );
  }
}

/// The band the column heads sit in.
class FmHeaderBand extends StatelessWidget {
  const FmHeaderBand({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        height: FmSkin.headerHeight,
        padding: const EdgeInsets.only(left: 12, right: 12),
        decoration: const BoxDecoration(
          color: C.chrome,
          border: Border(
            top: BorderSide(color: C.hairline),
            bottom: BorderSide(color: C.hairline),
          ),
        ),
        child: Row(children: children),
      );
}

/// What a row in a listing is.
enum FmEntryKind { file, folder, drive }

/// One entry in a directory listing.
///
/// Three things have to survive a glance down the column: what kind of thing it
/// is, what it is called, and how big it is. So the kind is a drawn shape
/// rather than a colour, the name is the only text at reading weight, and the
/// size and the timestamp are set in the console's data face — tabular, so a
/// column of figures lines up on the decimal instead of dancing.
///
/// Selection is a wash plus a rule down the leading edge. The rule is there
/// because a wash alone is a colour, and a listing is exactly the surface where
/// somebody will be reading a colour they cannot see.
class FmFileRow extends StatefulWidget {
  const FmFileRow({
    super.key,
    required this.name,
    required this.kind,
    required this.modified,
    required this.size,
    required this.selected,
    required this.contextTarget,
    required this.nameWidth,
    required this.modifiedWidth,
    this.onTap,
    this.onSecondaryTap,
    this.onSecondaryTapDown,
  });

  final String name;
  final FmEntryKind kind;

  /// Already formatted by the caller.
  final String modified;
  final String size;

  final bool selected;

  /// The row whose context menu is open.
  final bool contextTarget;

  final double nameWidth;
  final double modifiedWidth;

  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  State<FmFileRow> createState() => _FmFileRowState();
}

class _FmFileRowState extends State<FmFileRow> {
  bool _hover = false;

  static const _tooltipWait = Duration(milliseconds: 500);

  String get _glyph => switch (widget.kind) {
        FmEntryKind.folder => FmGlyphs.folder,
        FmEntryKind.drive => FmGlyphs.drive,
        FmEntryKind.file => FmGlyphs.file,
      };

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    // A directory is a place and a file is a payload, so the directory carries
    // the heavier name and the brighter glyph. Colour agrees with the shape; it
    // is never asked to carry the difference on its own.
    final isDir = widget.kind != FmEntryKind.file;
    final nameColor = selected || _hover ? C.text : (isDir ? C.text : C.textMuted);
    final glyphColor = selected
        ? C.accent
        : (isDir ? C.textMuted : C.textFaint);
    final dataColor = selected ? C.textMuted : C.textFaint;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTap: widget.onSecondaryTap,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: AnimatedContainer(
          duration: C.fast,
          curve: Curves.easeOut,
          height: FmSkin.rowHeight,
          decoration: BoxDecoration(
            color: selected
                ? C.accent.withOpacity(0.13)
                : (_hover || widget.contextTarget
                    ? C.surfaceHi
                    : Colors.transparent),
            border: Border(
              // The row whose context menu is open keeps the rule, one step
              // back from a selected row: an accent line under a row reads as
              // belonging to the row above it, which is why it is drawn down
              // the leading edge instead.
              left: BorderSide(
                  color: selected
                      ? C.accent
                      : (widget.contextTarget
                          ? C.accentDim
                          : Colors.transparent),
                  width: 2),
              bottom: const BorderSide(color: C.hairline),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: widget.nameWidth,
                child: Tooltip(
                  waitDuration: _tooltipWait,
                  message: widget.name,
                  child: Row(children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 10, right: 9),
                      child: LdIcon(_glyph, size: 17, color: glyphColor),
                    ),
                    Expanded(
                      child: Padding(
                        // The name never runs into the timestamp beside it: two
                        // columns of text that touch are one column of noise.
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          widget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: C.body(color: nameColor).copyWith(
                              fontWeight:
                                  isDir ? FontWeight.w600 : FontWeight.w500),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 2),
              SizedBox(
                width: widget.modifiedWidth,
                child: Tooltip(
                  waitDuration: _tooltipWait,
                  message: widget.modified,
                  child: Text(
                    widget.modified.trim(),
                    overflow: TextOverflow.ellipsis,
                    style: C.data(size: 11.5, color: dataColor),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Tooltip(
                  waitDuration: _tooltipWait,
                  message: widget.size,
                  child: Text(
                    widget.size.isEmpty ? '—' : widget.size,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: C.data(
                        size: 11.5,
                        color: widget.size.isEmpty ? C.textFaint : dataColor),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a job in the queue is actually doing.
///
/// The model carries five states and the old panel drew two of them: a bar
/// while it ran, and nothing at all afterwards, so a finished copy and a failed
/// one were the same grey card with different words buried in it. Named here so
/// each one can be drawn as itself.
enum FmJobState { queued, running, paused, failed, done }

extension _FmJobTone on FmJobState {
  Color get color => switch (this) {
        FmJobState.queued => C.idle,
        FmJobState.running => C.accent,
        FmJobState.paused => C.textMuted,
        FmJobState.failed => C.bad,
        FmJobState.done => C.ok,
      };
}

/// One job in the queue.
///
/// Reading order is the order somebody watching a transfer asks for it: what is
/// being copied, which way, how far along, how fast, and — if it went wrong —
/// what went wrong, in the one colour the console keeps for bad news. The
/// failure reason is on the tile rather than behind a tooltip: a transfer that
/// failed in the night is the whole reason this panel is looked at.
class FmJobTile extends StatelessWidget {
  const FmJobTile({
    super.key,
    required this.name,
    required this.state,
    required this.stateLabel,
    required this.detail,
    required this.directionGlyph,
    required this.directionTurns,
    required this.actions,
    this.percent,
    this.percentText,
    this.speed,
    this.error,
  });

  /// The job's name, already elided by the caller where it has to be.
  final Widget name;

  final FmJobState state;

  /// Already translated.
  final String stateLabel;

  /// The model's own status line, unchanged: file counts and sizes.
  final String detail;

  final String directionGlyph;
  final int directionTurns;

  /// Resume, cancel.
  final List<Widget> actions;

  /// Only while it is running.
  final double? percent;
  final String? percentText;
  final String? speed;

  /// Only when it failed.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tone = state.color;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: C.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: RotatedBox(
                  quarterTurns: directionTurns,
                  child: LdIcon(directionGlyph, size: 15, color: tone),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(child: name),
              const SizedBox(width: 6),
              ...actions,
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(stateLabel,
                  style: FmSkin.head(
                      color: state == FmJobState.failed ? C.bad : C.textMuted)),
              if (speed != null) ...[
                const Spacer(),
                Text(speed!, style: C.data(size: 11, color: C.textMuted)),
              ],
            ],
          ),
          if (percent != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: percent,
                      minHeight: 4,
                      backgroundColor: C.bg,
                      valueColor: const AlwaysStoppedAnimation<Color>(C.accent),
                    ),
                  ),
                ),
                if (percentText != null) ...[
                  const SizedBox(width: 9),
                  Text(percentText!,
                      style: C.data(size: 11, color: C.text, w: FontWeight.w600)),
                ],
              ],
            ),
          ],
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(detail,
                style: C.data(size: 11, color: C.textFaint),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
          if (error != null && error!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
              decoration: BoxDecoration(
                color: C.bad.withOpacity(0.10),
                borderRadius: C.roundedSm,
                border: Border.all(color: C.bad.withOpacity(0.45)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: LdIcon(LdIcons.alert, size: 13, color: C.bad),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(error!,
                        style: C.small(color: C.bad, w: FontWeight.w600),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Nothing here, said once and quietly.
///
/// An empty queue is the normal state of this panel, so it is drawn at the
/// weight of a caption rather than as an illustration with a headline.
class FmEmpty extends StatelessWidget {
  const FmEmpty({super.key, required this.glyph, required this.line, this.hint});

  final String glyph;

  /// Already translated.
  final String line;
  final String? hint;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LdIcon(glyph, size: 26, color: C.textFaint.withOpacity(0.7)),
              const SizedBox(height: 12),
              Text(line,
                  textAlign: TextAlign.center,
                  style: C.small(color: C.textMuted, w: FontWeight.w600)),
              if (hint != null) ...[
                const SizedBox(height: 5),
                Text(hint!,
                    textAlign: TextAlign.center,
                    style: C.small(color: C.textFaint)),
              ],
            ],
          ),
        ),
      );
}

/// One step of the path.
///
/// The current directory is the only crumb at full strength; the ones behind it
/// are a way back, which is a quieter job. A crumb is text with a hit area, not
/// a Material TextButton — the button brought its own padding, its own ripple
/// and its own minimum size into a 30-pixel-tall bar.
class FmCrumb extends StatefulWidget {
  const FmCrumb(
      {super.key,
      required this.label,
      required this.current,
      required this.onTap});

  final String label;
  final bool current;
  final VoidCallback onTap;

  @override
  State<FmCrumb> createState() => _FmCrumbState();
}

class _FmCrumbState extends State<FmCrumb> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.current
        ? C.text
        : (_hover ? C.text : C.textMuted);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Text(
            widget.label,
            style: C.small(
                color: color,
                w: widget.current ? FontWeight.w700 : FontWeight.w500),
          ),
        ),
      ),
    );
  }
}
