import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/labdesk/theme/console_theme.dart';
import 'package:flutter_hbb/labdesk/theme/ld_icons.dart';
import 'package:flutter_hbb/labdesk/theme/session_toolbar_skin.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

const double _kColumn1Width = 34;
const double _kColumn4Width = 64;
const double _kRowHeight = 46;
const double _kTextLeftMargin = 14;

/// A port is a number and a host is an address, so both are set in the
/// console's data face rather than in the interface face at display size.
TextStyle _cellStyle() => C.data(size: 13.5, color: C.text);

InputDecoration _fieldDecoration(String? hint) => InputDecoration(
      hintText: hint,
      hintStyle: C.data(size: 13, color: C.textFaint),
      isDense: true,
      filled: true,
      fillColor: C.bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      enabledBorder: OutlineInputBorder(
          borderRadius: C.roundedSm,
          borderSide: const BorderSide(color: C.hairline)),
      focusedBorder: OutlineInputBorder(
          borderRadius: C.roundedSm,
          borderSide: const BorderSide(color: C.accent, width: 1.4)),
      border: OutlineInputBorder(
          borderRadius: C.roundedSm,
          borderSide: const BorderSide(color: C.hairline)),
    );

class _PortForward {
  int localPort;
  String remoteHost;
  int remotePort;

  _PortForward.fromJson(List<dynamic> json)
      : localPort = json[0] as int,
        remoteHost = json[1] as String,
        remotePort = json[2] as int;
}

class PortForwardPage extends StatefulWidget {
  PortForwardPage({
    Key? key,
    required this.id,
    required this.password,
    required this.tabController,
    required this.isRDP,
    required this.isSharedPassword,
    this.forceRelay,
    this.connToken,
  }) : super(key: key);
  final String id;
  final String? password;
  final DesktopTabController tabController;
  final bool isRDP;
  final bool? forceRelay;
  final bool? isSharedPassword;
  final String? connToken;
  final SimpleWrapper<State<PortForwardPage>?> _lastState = SimpleWrapper(null);

  FFI get ffi => (_lastState.value! as _PortForwardPageState)._ffi;

  @override
  State<PortForwardPage> createState() {
    final state = _PortForwardPageState();
    _lastState.value = state;
    return state;
  }
}

class _PortForwardPageState extends State<PortForwardPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController localPortController = TextEditingController();
  final TextEditingController remoteHostController = TextEditingController();
  final TextEditingController remotePortController = TextEditingController();
  RxList<_PortForward> pfs = RxList.empty(growable: true);
  late FFI _ffi;

  @override
  void initState() {
    super.initState();
    _ffi = FFI(null);
    _ffi.start(widget.id,
        isPortForward: true,
        password: widget.password,
        isSharedPassword: widget.isSharedPassword,
        forceRelay: widget.forceRelay,
        connToken: widget.connToken,
        isRdp: widget.isRDP);
    Get.put<FFI>(_ffi, tag: 'pf_${widget.id}');
    debugPrint("Port forward page init success with id ${widget.id}");
    // Call onSelected in post frame callback, since we cannot guarantee that the callback will not call setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.tabController.onSelected?.call(widget.id);
    });
  }

  @override
  void dispose() {
    _ffi.close();
    _ffi.dialogManager.dismissAll();
    Get.delete<FFI>(tag: 'pf_${widget.id}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Theme(
      data: cmThemeData(context),
      child: Scaffold(
        backgroundColor: C.bg,
        body: FutureBuilder(future: () async {
          if (!widget.isRDP) {
            refreshTunnelConfig();
          }
        }(), builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buildPrompt(context),
                  Flexible(
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: C.surface,
                        borderRadius: C.rounded,
                        border: Border.all(color: C.hairline),
                      ),
                      child: widget.isRDP
                          ? buildRdp(context)
                          : buildTunnel(context),
                    ),
                  ),
                ],
              ),
            );
          }
          return const Offstage();
        }),
      ),
    );
  }

  /// The tunnel is up and has to stay up. The old banner said so in a filled
  /// green bar, which is the loudest thing the product can draw and it was
  /// spent on a state that is simply *normal*. A running state is a status
  /// line: the semantic dot, the word, and the warning underneath it in the
  /// voice it deserves.
  buildPrompt(BuildContext context) {
    return Obx(() => Offstage(
          offstage: pfs.isEmpty && !widget.isRDP,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: C.rounded,
              border: Border.all(color: C.hairline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 5),
                  child: CmStatusDot(color: C.ok),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(translate('Listening ...'), style: C.h2()),
                      const SizedBox(height: 3),
                      Text(translate('not_close_tcp_tip'),
                          style: C.small(color: C.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ).marginOnly(bottom: 12),
        ));
  }

  /// One column head. Set as a label, not as body text: a column head that
  /// looks like data is a row the eye tries to read.
  Widget _head(String label) => Expanded(
      child: Text(translate(label).toUpperCase(),
              style: C.micro(color: C.textFaint).copyWith(letterSpacing: 0.8))
          .marginOnly(left: _kTextLeftMargin));

  buildTunnel(BuildContext context) {
    return Obx(() => ListView.builder(
        controller: ScrollController(),
        itemCount: pfs.length + 2,
        itemBuilder: ((context, index) {
          if (index == 0) {
            return Container(
              height: 30,
              alignment: Alignment.centerLeft,
              decoration: const BoxDecoration(
                color: C.chrome,
                border: Border(bottom: BorderSide(color: C.hairline)),
              ),
              child: Row(children: [
                _head('Local Port'),
                const SizedBox(width: _kColumn1Width),
                _head('Remote Host'),
                _head('Remote Port'),
                SizedBox(
                    width: _kColumn4Width,
                    child: Text(translate('Action').toUpperCase(),
                        style: C
                            .micro(color: C.textFaint)
                            .copyWith(letterSpacing: 0.8))),
              ]),
            );
          } else if (index == 1) {
            return buildTunnelAddRow(context);
          } else {
            return buildTunnelDataRow(context, pfs[index - 2], index - 2);
          }
        })));
  }

  buildTunnelAddRow(BuildContext context) {
    var portInputFormatter = [
      FilteringTextInputFormatter.allow(RegExp(
          r'^([0-9]|[1-9]\d|[1-9]\d{2}|[1-9]\d{3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$'))
    ];

    return Container(
      height: _kRowHeight,
      decoration: const BoxDecoration(
        color: C.surfaceHi,
        border: Border(bottom: BorderSide(color: C.hairline)),
      ),
      child: Row(children: [
        buildTunnelInputCell(context,
            controller: localPortController,
            inputFormatters: portInputFormatter),
        const SizedBox(
            width: _kColumn1Width,
            child: Center(
                child:
                    LdIcon(LdIcons.arrowRight, size: 16, color: C.textFaint))),
        buildTunnelInputCell(context,
            controller: remoteHostController, hint: 'localhost'),
        buildTunnelInputCell(context,
            controller: remotePortController,
            inputFormatters: portInputFormatter),
        GhostButton(
          glyph: LdIcons.add,
          label: translate('Add'),
          onPressed: () async {
            int? localPort = int.tryParse(localPortController.text);
            int? remotePort = int.tryParse(remotePortController.text);
            if (localPort != null &&
                remotePort != null &&
                (remoteHostController.text.isEmpty ||
                    remoteHostController.text.trim().isNotEmpty)) {
              await bind.sessionAddPortForward(
                  sessionId: _ffi.sessionId,
                  localPort: localPort,
                  remoteHost: remoteHostController.text.trim().isEmpty
                      ? 'localhost'
                      : remoteHostController.text.trim(),
                  remotePort: remotePort);
              localPortController.clear();
              remoteHostController.clear();
              remotePortController.clear();
              refreshTunnelConfig();
            }
          },
        ).marginSymmetric(horizontal: 10),
      ]),
    );
  }

  buildTunnelInputCell(BuildContext context,
      {required TextEditingController controller,
      List<TextInputFormatter>? inputFormatters,
      String? hint}) {
    return Expanded(
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: TextField(
              controller: controller,
              inputFormatters: inputFormatters,
              style: _cellStyle(),
              cursorColor: C.accent,
              cursorWidth: 1.6,
              decoration: _fieldDecoration(hint)).workaroundFreezeLinuxMint()),
    );
  }

  /// One live tunnel.
  ///
  /// The zebra stripe is gone: a hairline under each row separates them at a
  /// tenth of the cost, and the stripe was the only place in the product where
  /// a surface changed colour for a reason that was not a state.
  Widget buildTunnelDataRow(BuildContext context, _PortForward pf, int index) {
    text(String label) => Expanded(
        child: Text(label, style: _cellStyle())
            .marginOnly(left: _kTextLeftMargin));

    return Container(
      height: _kRowHeight,
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: C.hairline))),
      child: Row(children: [
        text(pf.localPort.toString()),
        const SizedBox(
            width: _kColumn1Width,
            child: Center(
                child:
                    LdIcon(LdIcons.arrowRight, size: 16, color: C.textFaint))),
        text(pf.remoteHost),
        text(pf.remotePort.toString()),
        SizedBox(
          width: _kColumn4Width,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _RemoveTunnelButton(
              onRemove: () async {
                await bind.sessionRemovePortForward(
                    sessionId: _ffi.sessionId, localPort: pf.localPort);
                refreshTunnelConfig();
              },
            ),
          ),
        ),
      ]),
    );
  }

  void refreshTunnelConfig() async {
    String peer = bind.mainGetPeerSync(id: widget.id);
    Map<String, dynamic> config = jsonDecode(peer);
    List<dynamic> infos = config['port_forwards'] as List;
    List<_PortForward> result = List.empty(growable: true);
    for (var e in infos) {
      result.add(_PortForward.fromJson(e));
    }
    pfs.value = result;
  }

  buildRdp(BuildContext context) {
    text2(String label) => Expanded(
        child:
            Text(label, style: _cellStyle()).marginOnly(left: _kTextLeftMargin));
    return ListView.builder(
        controller: ScrollController(),
        itemCount: 2,
        itemBuilder: ((context, index) {
          if (index == 0) {
            return Container(
              height: 30,
              alignment: Alignment.centerLeft,
              decoration: const BoxDecoration(
                color: C.chrome,
                border: Border(bottom: BorderSide(color: C.hairline)),
              ),
              child: Row(children: [
                _head('Local Port'),
                const SizedBox(width: _kColumn1Width),
                _head('Remote Host'),
                _head('Remote Port'),
              ]),
            );
          } else {
            return Container(
              height: _kRowHeight,
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: C.hairline))),
              child: Row(children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: GhostButton(
                      glyph: LdIcons.portForward,
                      label: translate('New RDP'),
                      onPressed: () =>
                          bind.sessionNewRdp(sessionId: _ffi.sessionId),
                    ).marginOnly(left: _kTextLeftMargin),
                  ),
                ),
                const SizedBox(
                    width: _kColumn1Width,
                    child: Center(
                        child: LdIcon(LdIcons.arrowRight,
                            size: 16, color: C.textFaint))),
                text2('localhost'),
                text2('RDP'),
              ]),
            );
          }
        }));
  }

  @override
  bool get wantKeepAlive => true;
}

/// Ending one tunnel.
///
/// Red only once the cursor is on the control itself, never on every row the
/// pointer crosses: the same rule the session tab's close obeys, because it is
/// the same act.
class _RemoveTunnelButton extends StatefulWidget {
  const _RemoveTunnelButton({Key? key, required this.onRemove})
      : super(key: key);

  final VoidCallback onRemove;

  @override
  State<_RemoveTunnelButton> createState() => _RemoveTunnelButtonState();
}

class _RemoveTunnelButtonState extends State<_RemoveTunnelButton> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: widget.onRemove,
        child: WindowButtonSurface(
          hover: hover,
          boxSize: 30,
          color: C.textFaint,
          hoverColor: C.bad,
          iconBuilder: (fg) => LdIcon(LdIcons.close, size: 13, color: fg),
        ),
      ),
    );
  }
}
