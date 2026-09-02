// original cm window in Sciter version.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/audio_input.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/labdesk/theme/console_theme.dart';
import 'package:flutter_hbb/labdesk/theme/ld_icons.dart';
import 'package:flutter_hbb/labdesk/theme/session_toolbar_skin.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/cm_file_model.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../common.dart';
import '../../common/widgets/chat_page.dart';
import '../../models/file_model.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';

class DesktopServerPage extends StatefulWidget {
  const DesktopServerPage({Key? key}) : super(key: key);

  @override
  State<DesktopServerPage> createState() => _DesktopServerPageState();
}

class _DesktopServerPageState extends State<DesktopServerPage>
    with WindowListener, AutomaticKeepAliveClientMixin {
  final tabController = gFFI.serverModel.tabController;

  _DesktopServerPageState() {
    gFFI.ffiModel.updateEventListener(gFFI.sessionId, "");
    Get.put<DesktopTabController>(tabController);
    tabController.onRemoved = (_, id) {
      onRemoveId(id);
    };
  }

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    Future.wait([gFFI.serverModel.closeAll(), gFFI.close()]).then((_) {
      if (isMacOS) {
        RdPlatformChannel.instance.terminate();
      } else {
        windowManager.setPreventClose(false);
        windowManager.close();
      }
    });
    super.onWindowClose();
  }

  void onRemoveId(String id) {
    if (tabController.state.value.tabs.isEmpty) {
      windowManager.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: gFFI.serverModel),
        ChangeNotifierProvider.value(value: gFFI.chatModel),
      ],
      child: Consumer<ServerModel>(
        builder: (context, serverModel, child) {
          // One theme over the whole window, so the chat page and the file
          // transfer log it hosts speak the console's dialect too.
          final body = Theme(
            data: cmThemeData(context),
            child: Scaffold(
              backgroundColor: C.bg,
              body: ConnectionManager(),
            ),
          );
          return isLinux
              ? buildVirtualWindowFrame(context, body)
              : workaroundWindowBorder(
                  context,
                  Container(
                    decoration:
                        BoxDecoration(border: Border.all(color: C.hairline)),
                    child: body,
                  ));
        },
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class ConnectionManager extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => ConnectionManagerState();
}

class ConnectionManagerState extends State<ConnectionManager>
    with WidgetsBindingObserver {
  final RxBool _controlPageBlock = false.obs;
  final RxBool _sidePageBlock = false.obs;

  ConnectionManagerState() {
    gFFI.serverModel.tabController.onSelected = (client_id_str) {
      final client_id = int.tryParse(client_id_str);
      if (client_id != null) {
        final client =
            gFFI.serverModel.clients.firstWhereOrNull((e) => e.id == client_id);
        if (client != null) {
          gFFI.chatModel.changeCurrentKey(MessageKey(client.peerId, client.id));
          if (client.unreadChatMessageCount.value > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              client.unreadChatMessageCount.value = 0;
              gFFI.chatModel.showChatPage(MessageKey(client.peerId, client.id));
            });
          }
          windowManager.setTitle(getWindowNameWithId(client.peerId));
          gFFI.cmFileModel.updateCurrentClientId(client.id);
        }
      }
    };
    gFFI.chatModel.isConnManager = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      if (!allowRemoteCMModification()) {
        shouldBeBlocked(_controlPageBlock, null);
        shouldBeBlocked(_sidePageBlock, null);
      }
    }
  }

  @override
  void initState() {
    gFFI.serverModel.updateClientState();
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    pointerHandler(PointerEvent e) {
      if (serverModel.cmHiddenTimer != null) {
        serverModel.cmHiddenTimer!.cancel();
        serverModel.cmHiddenTimer = null;
        debugPrint("CM hidden timer has been canceled");
      }
    }

    return serverModel.clients.isEmpty
        ? Column(
            children: [
              buildTitleBar(),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const LdIcon(LdIcons.connect,
                          size: 26, color: C.textFaint),
                      const SizedBox(height: 12),
                      Text(translate("Waiting"),
                          style: C.small(color: C.textMuted)),
                    ],
                  ),
                ),
              ),
            ],
          )
        : Listener(
            onPointerDown: pointerHandler,
            onPointerMove: pointerHandler,
            child: DesktopTab(
              showTitle: false,
              showMaximize: false,
              showMinimize: true,
              showClose: true,
              onWindowCloseButton: handleWindowCloseButton,
              controller: serverModel.tabController,
              selectedBorderColor: C.accent,
              maxLabelWidth: 100,
              tail: null, //buildScrollJumper(),
              tabBuilder: (key, icon, label, themeConf) {
                final client = serverModel.clients
                    .firstWhereOrNull((client) => client.id.toString() == key);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Tooltip(
                        message: key,
                        waitDuration: Duration(seconds: 1),
                        child: label),
                    unreadMessageCountBuilder(client?.unreadChatMessageCount)
                        .marginOnly(left: 4),
                  ],
                );
              },
              pageViewBuilder: (pageView) => LayoutBuilder(
                builder: (context, constrains) {
                  var borderWidth = 0.0;
                  if (constrains.maxWidth >
                      kConnectionManagerWindowSizeClosedChat.width) {
                    borderWidth = kConnectionManagerWindowSizeOpenChat.width -
                        constrains.maxWidth;
                  } else {
                    borderWidth = kConnectionManagerWindowSizeClosedChat.width -
                        constrains.maxWidth;
                  }
                  if (borderWidth < 0 || borderWidth > 50) {
                    borderWidth = 0;
                  }
                  final realClosedWidth =
                      kConnectionManagerWindowSizeClosedChat.width -
                          borderWidth;
                  final realChatPageWidth =
                      constrains.maxWidth - realClosedWidth;
                  final row = Row(children: [
                    if (constrains.maxWidth >
                        kConnectionManagerWindowSizeClosedChat.width)
                      Consumer<ChatModel>(
                          builder: (_, model, child) => SizedBox(
                                width: realChatPageWidth,
                                child: allowRemoteCMModification()
                                    ? buildSidePage()
                                    : buildRemoteBlock(
                                        child: buildSidePage(),
                                        block: _sidePageBlock,
                                        mask: true),
                              )),
                    SizedBox(
                        width: realClosedWidth,
                        child: SizedBox(
                            width: realClosedWidth,
                            child: allowRemoteCMModification()
                                ? pageView
                                : buildRemoteBlock(
                                    child: _buildKeyEventBlock(pageView),
                                    block: _controlPageBlock,
                                    mask: false,
                                  ))),
                  ]);
                  return Container(color: C.bg, child: row);
                },
              ),
            ),
          );
  }

  Widget buildSidePage() {
    final selected = gFFI.serverModel.tabController.state.value.selected;
    if (selected < 0 || selected >= gFFI.serverModel.clients.length) {
      return Offstage();
    }
    final clientType = gFFI.serverModel.clients[selected].type_();
    if (clientType == ClientType.file) {
      return _FileTransferLogPage();
    } else {
      return ChatPage(type: ChatPageType.desktopCM);
    }
  }

  Widget _buildKeyEventBlock(Widget child) {
    return ExcludeFocus(child: child, excluding: true);
  }

  Widget buildTitleBar() {
    return Container(
      height: kDesktopRemoteTabBarHeight,
      color: C.chrome,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _AppIcon(),
          Expanded(
            child: GestureDetector(
              onPanStart: (d) {
                windowManager.startDragging();
              },
              child: Container(color: C.chrome),
            ),
          ),
          const SizedBox(
            width: 4.0,
          ),
          const _CloseButton()
        ],
      ),
    );
  }

  Widget buildScrollJumper() {
    final offstage = gFFI.serverModel.clients.length < 2;
    final sc = gFFI.serverModel.tabController.state.value.scrollController;
    return Offstage(
        offstage: offstage,
        child: Row(
          children: [
            ActionIcon(
                icon: Icons.arrow_left, iconSize: 22, onTap: sc.backward),
            ActionIcon(
                icon: Icons.arrow_right, iconSize: 22, onTap: sc.forward),
          ],
        ));
  }

  Future<bool> handleWindowCloseButton() async {
    var tabController = gFFI.serverModel.tabController;
    final connLength = tabController.length;
    if (connLength <= 1) {
      windowManager.close();
      return true;
    } else {
      final bool res;
      if (!option2bool(kOptionEnableConfirmClosingTabs,
          bind.mainGetLocalOption(key: kOptionEnableConfirmClosingTabs))) {
        res = true;
      } else {
        res = await closeConfirmDialog();
      }
      if (res) {
        windowManager.close();
      }
      return res;
    }
  }
}

Widget buildConnectionCard(Client client) {
  return Consumer<ServerModel>(
    builder: (context, value, child) {
      final showPermissions = !(client.type_() == ClientType.file ||
          client.type_() == ClientType.portForward ||
          client.type_() == ClientType.terminal ||
          client.disconnected);
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        key: ValueKey(client.id),
        children: [
          _CmHeader(client: client),
          const SizedBox(height: CmSkin.pad),
          // The permission set takes the height that is left, so the two
          // answers stay pinned to the foot of the window whatever the set
          // contains. Without a set there is nothing to give the height to.
          if (showPermissions)
            Expanded(child: _PrivilegeBoard(client: client))
          else
            const Spacer(),
          _CmControlPanel(client: client),
        ],
      ).paddingSymmetric(vertical: CmSkin.pad, horizontal: CmSkin.pad);
    },
  );
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 8.0),
      // The strip is 28 pixels tall; the mark has to live inside it.
      child: loadIcon(16),
    );
  }
}

/// The window's own close, wearing the same pad as every other control in
/// every other session window.
class _CloseButton extends StatefulWidget {
  const _CloseButton({Key? key}) : super(key: key);

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: () {
          windowManager.close();
        },
        child: WindowButtonSurface(
          hover: hover,
          boxSize: kDesktopRemoteTabBarHeight,
          color: C.textMuted,
          hoverColor: C.bad,
          iconBuilder: (fg) => LdIcon(LdIcons.close, size: 13, color: fg),
        ),
      ),
    );
  }
}

class _CmHeader extends StatefulWidget {
  final Client client;

  const _CmHeader({Key? key, required this.client}) : super(key: key);

  @override
  State<_CmHeader> createState() => _CmHeaderState();
}

class _CmHeaderState extends State<_CmHeader>
    with AutomaticKeepAliveClientMixin {
  Client get client => widget.client;

  final _time = 0.obs;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(Duration(seconds: 1), (_) {
      if (client.authorized && !client.disconnected) {
        _time.value = _time.value + 1;
      }
    });
    // Call onSelected in post frame callback, since we cannot guarantee that the callback will not call setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      gFFI.serverModel.tabController.onSelected?.call(client.id.toString());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// What is being asked for, in words. Every string here already exists in the
  /// product's dictionary; the window says which kind of access is on the table
  /// rather than leaving the person to infer it from a tab icon.
  ({String glyph, String label}) get _kind {
    switch (client.type_()) {
      case ClientType.terminal:
        return (glyph: LdIcons.terminal, label: translate("Terminal"));
      case ClientType.file:
        return (glyph: LdIcons.fileTransfer, label: translate("Transfer file"));
      case ClientType.camera:
        return (glyph: LdIcons.camera, label: translate("View camera"));
      case ClientType.portForward:
        return (
          glyph: LdIcons.portForward,
          label: "Port Forward: ${client.portForward}"
        );
      case ClientType.remote:
        return (
          glyph: LdIcons.display,
          label: translate("Control Remote Desktop")
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final kind = _kind;
    // Built outside the Obx: the panel below rebuilds once a second to move the
    // clock, and the avatar is the one thing in it that decodes an image.
    final avatar = _buildClientAvatar();
    final showAction = client.authorized &&
        (client.type_() == ClientType.remote ||
            client.type_() == ClientType.file ||
            client.type_() == ClientType.camera);
    return Obx(() {
      // Read unconditionally: an Obx that touches nothing observable throws,
      // and this one is only allowed to show the figure once the session is up.
      final seconds = _time.value;
      return CmIdentity(
        name: client.name,
        peerId: client.peerId,
        kindGlyph: kind.glyph,
        kindLabel: kind.label,
        pending: !client.authorized,
        statusColor: client.authorized
            ? (client.disconnected ? C.idle : C.ok)
            : C.accent,
        statusLabel: client.authorized
            ? client.disconnected
                ? translate("Disconnected")
                : translate("Connected")
            : "${translate("Request access to your device")}...",
        elapsed: client.authorized
            ? formatDurationToTime(Duration(seconds: seconds))
            : null,
        avatar: avatar,
        action: !showAction
            ? null
            : _HeaderAction(
                glyph: client.type_() == ClientType.file
                    ? LdIcons.fileTransfer
                    : LdIcons.chat,
                onTap: () => checkClickTime(client.id, () {
                  if (client.type_() == ClientType.file) {
                    gFFI.chatModel.toggleCMFilePage();
                  } else {
                    gFFI.chatModel
                        .toggleCMChatPage(MessageKey(client.peerId, client.id));
                  }
                }),
              ),
      );
    });
  }

  @override
  bool get wantKeepAlive => true;

  Widget _buildClientAvatar() {
    return buildAvatarWidget(
          avatar: client.avatar,
          size: 40,
          borderRadius: C.radius,
          fallback: _buildInitialAvatar(),
        ) ??
        _buildInitialAvatar();
  }

  /// The peer's initial. The colour the app derives from the name is spent on
  /// the block's edge and its letter rather than on a filled tile, so a caller
  /// whose name happens to hash to something loud cannot out-shout the consent
  /// question sitting above it.
  Widget _buildInitialAvatar() =>
      CmInitialAvatar(name: client.name, color: str2color(client.name));
}

/// The header's one control: open the chat, or the file-transfer log.
class _HeaderAction extends StatefulWidget {
  const _HeaderAction({Key? key, required this.glyph, required this.onTap})
      : super(key: key);

  final String glyph;
  final VoidCallback onTap;

  @override
  State<_HeaderAction> createState() => _HeaderActionState();
}

class _HeaderActionState extends State<_HeaderAction> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: WindowButtonSurface(
          hover: hover,
          boxSize: 30,
          color: C.textMuted,
          hoverColor: C.text,
          iconBuilder: (fg) => LdIcon(widget.glyph, size: 16, color: fg),
        ),
      ),
    );
  }
}

class _PrivilegeBoard extends StatefulWidget {
  final Client client;

  const _PrivilegeBoard({Key? key, required this.client}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _PrivilegeBoardState();
}

class _PrivilegeBoardState extends State<_PrivilegeBoard> {
  late final client = widget.client;

  /// One permission, as a labelled row that states its own condition.
  ///
  /// The message the tile carried is kept, and is now what the row is called
  /// to a screen reader rather than something painted over the two rows under
  /// it.
  Widget buildPermissionIcon(bool enabled, String glyph, Function(bool)? onTap,
      String tooltipText,
      {required bool canModify}) {
    return CmPermissionRow(
      glyph: glyph,
      label: tooltipText,
      tooltip: "$tooltipText: ${enabled ? "ON" : "OFF"}",
      on: enabled,
      canModify: canModify,
      onChanged: (value) =>
          checkClickTime(widget.client.id, () => onTap?.call(value)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canModifyPermission =
        bind.mainGetBuildinOption(key: kOptionEnablePermChangeInAcceptWindow) !=
            'N';
    return Container(
      width: double.infinity,
      child: CmPermissionPanel(
        label: translate("Permissions"),
        locked: !canModifyPermission,
        rows: client.type_() == ClientType.camera
                  ? [
                      buildPermissionIcon(
                        client.audio,
                        LdIcons.audio,
                        (enabled) {
                          bind.cmSwitchPermission(
                              connId: client.id,
                              name: "audio",
                              enabled: enabled);
                          setState(() {
                            client.audio = enabled;
                          });
                        },
                        translate('Enable audio'),
                        canModify: canModifyPermission,
                      ),
                      buildPermissionIcon(
                        client.recording,
                        LdIcons.record,
                        (enabled) {
                          bind.cmSwitchPermission(
                              connId: client.id,
                              name: "recording",
                              enabled: enabled);
                          setState(() {
                            client.recording = enabled;
                          });
                        },
                        translate('Enable recording session'),
                        canModify: canModifyPermission,
                      ),
                    ]
                  : [
                      buildPermissionIcon(
                        client.keyboard,
                        LdIcons.keyboard,
                        (enabled) {
                          bind.cmSwitchPermission(
                              connId: client.id,
                              name: "keyboard",
                              enabled: enabled);
                          setState(() {
                            client.keyboard = enabled;
                          });
                        },
                        translate('Enable keyboard/mouse'),
                        canModify: canModifyPermission,
                      ),
                      buildPermissionIcon(
                        client.clipboard,
                        LdIcons.clipboard,
                        (enabled) {
                          bind.cmSwitchPermission(
                              connId: client.id,
                              name: "clipboard",
                              enabled: enabled);
                          setState(() {
                            client.clipboard = enabled;
                          });
                        },
                        translate('Enable clipboard'),
                        canModify: canModifyPermission,
                      ),
                      buildPermissionIcon(
                        client.audio,
                        LdIcons.audio,
                        (enabled) {
                          bind.cmSwitchPermission(
                              connId: client.id,
                              name: "audio",
                              enabled: enabled);
                          setState(() {
                            client.audio = enabled;
                          });
                        },
                        translate('Enable audio'),
                        canModify: canModifyPermission,
                      ),
                      buildPermissionIcon(
                        client.file,
                        LdIcons.fileTransfer,
                        (enabled) {
                          bind.cmSwitchPermission(
                              connId: client.id,
                              name: "file",
                              enabled: enabled);
                          setState(() {
                            client.file = enabled;
                          });
                        },
                        translate('Enable file copy and paste'),
                        canModify: canModifyPermission,
                      ),
                      buildPermissionIcon(
                        client.restart,
                        LdIcons.restart,
                        (enabled) {
                          bind.cmSwitchPermission(
                              connId: client.id,
                              name: "restart",
                              enabled: enabled);
                          setState(() {
                            client.restart = enabled;
                          });
                        },
                        translate('Enable remote restart'),
                        canModify: canModifyPermission,
                      ),
                      buildPermissionIcon(
                        client.recording,
                        LdIcons.record,
                        (enabled) {
                          bind.cmSwitchPermission(
                              connId: client.id,
                              name: "recording",
                              enabled: enabled);
                          setState(() {
                            client.recording = enabled;
                          });
                        },
                        translate('Enable recording session'),
                        canModify: canModifyPermission,
                      ),
                      // only windows support block input
                      if (isWindows)
                        buildPermissionIcon(
                          client.blockInput,
                          LdIcons.blockInput,
                          (enabled) {
                            bind.cmSwitchPermission(
                                connId: client.id,
                                name: "block_input",
                                enabled: enabled);
                            setState(() {
                              client.blockInput = enabled;
                            });
                          },
                          translate('Enable blocking user input'),
                          canModify: canModifyPermission,
                        ),
                      if (bind.mainSupportedPrivacyModeImpls() != '[]')
                        buildPermissionIcon(
                          client.privacyMode,
                          LdIcons.privacy,
                          (enabled) {
                            bind.cmSwitchPermission(
                                connId: client.id,
                                name: "privacy_mode",
                                enabled: enabled);
                            setState(() {
                              client.privacyMode = enabled;
                            });
                          },
                          translate('Enable privacy mode'),
                          canModify: canModifyPermission,
                        )
                    ],
      ),
    );
  }
}

const double buttonBottomMargin = 8;

/// The gap between two answers. Wide enough that the hand cannot mistake one
/// for the other on a 300-pixel window.
const double buttonGap = 8;

class _CmControlPanel extends StatelessWidget {
  final Client client;

  const _CmControlPanel({Key? key, required this.client}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return client.authorized
        ? client.disconnected
            ? buildDisconnected(context)
            : buildAuthorized(context)
        : buildUnAuthorized(context);
  }

  buildAuthorized(BuildContext context) {
    final bool canElevate = bind.cmCanElevate();
    final model = Provider.of<ServerModel>(context);
    final showElevation = canElevate &&
        model.showElevation &&
        client.type_() == ClientType.remote;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Offstage(
          offstage: !client.inVoiceCall,
          child: Row(
            children: [
              Expanded(
                child: buildButton(context,
                    tone: CmTone.accent,
                    glyph: LdIcons.mic,
                    onClick: null, onTapDown: (details) async {
                  final devicesInfo =
                      await AudioInput.getDevicesInfo(true, true);
                  List<String> devices = devicesInfo['devices'] as List<String>;
                  if (devices.isEmpty) {
                    msgBox(
                      gFFI.sessionId,
                      'custom-nocancel-info',
                      'Prompt',
                      'no_audio_input_device_tip',
                      '',
                      gFFI.dialogManager,
                    );
                    return;
                  }

                  String currentDevice = devicesInfo['current'] as String;
                  final x = details.globalPosition.dx;
                  final y = details.globalPosition.dy;
                  final position = RelativeRect.fromLTRB(x, y, x, y);
                  showMenu(
                    context: context,
                    position: position,
                    items: devices
                        .map((d) => PopupMenuItem<String>(
                              value: d,
                              height: 18,
                              padding: EdgeInsets.zero,
                              onTap: () => AudioInput.setDevice(d, true, true),
                              child: IgnorePointer(
                                  child: RadioMenuButton(
                                value: d,
                                groupValue: currentDevice,
                                onChanged: (v) {
                                  if (v != null)
                                    AudioInput.setDevice(v, true, true);
                                },
                                child: Container(
                                  child: Text(
                                    d,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                  constraints: BoxConstraints(
                                      maxWidth:
                                          kConnectionManagerWindowSizeClosedChat
                                                  .width -
                                              80),
                                ),
                              )),
                            ))
                        .toList(),
                  );
                }, text: "Audio input"),
              ),
              const SizedBox(width: buttonGap),
              Expanded(
                child: buildButton(
                  context,
                  tone: CmTone.danger,
                  glyph: LdIcons.callEnd,
                  onClick: () => closeVoiceCall(),
                  text: "Stop voice call",
                ),
              )
            ],
          ).marginOnly(bottom: buttonGap),
        ),
        Offstage(
          offstage: !client.incomingVoiceCall,
          child: Row(
            children: [
              Expanded(
                child: buildButton(context,
                    tone: CmTone.accent,
                    glyph: LdIcons.call,
                    onClick: () => handleVoiceCall(true),
                    text: "Accept"),
              ),
              const SizedBox(width: buttonGap),
              Expanded(
                child: buildButton(
                  context,
                  // Declining a call that has not started destroys nothing, so
                  // it is not drawn in the colour that means something is being
                  // ended. Stopping a call that is running, above, is.
                  tone: CmTone.neutral,
                  onClick: () => handleVoiceCall(false),
                  text: "Dismiss",
                ),
              )
            ],
          ).marginOnly(bottom: buttonGap),
        ),
        Offstage(
          offstage: !client.fromSwitch,
          child: buildButton(context,
                  tone: CmTone.accent,
                  glyph: LdIcons.switchSides,
                  onClick: () => handleSwitchBack(context),
                  text: "Switch Sides")
              .marginOnly(bottom: buttonGap),
        ),
        Offstage(
          offstage: !showElevation,
          child: buildButton(
            context,
            tone: CmTone.accent,
            glyph: LdIcons.shield,
            onClick: () {
              handleElevate(context);
              windowManager.minimize();
            },
            text: 'Elevate',
          ).marginOnly(bottom: buttonGap),
        ),
        buildButton(context,
            tone: CmTone.danger,
            glyph: LdIcons.disconnect,
            onClick: handleDisconnect,
            text: 'Disconnect'),
      ],
    ).marginOnly(bottom: buttonBottomMargin);
  }

  buildDisconnected(BuildContext context) {
    return buildButton(context,
            tone: CmTone.neutral, onClick: handleClose, text: 'Close')
        .marginOnly(bottom: buttonBottomMargin);
  }

  buildUnAuthorized(BuildContext context) {
    final bool canElevate = bind.cmCanElevate();
    final model = Provider.of<ServerModel>(context);
    final showElevation = canElevate &&
        model.showElevation &&
        client.type_() == ClientType.remote;
    final showAccept = model.approveMode != 'password';
    // The two answers are the same size, the same type at the same weight, and
    // both labels are set in the console's full-strength text. Accept is told
    // apart by its accent frame and its lock, not by being the only one that
    // looks like a button — a person deciding under time pressure should have
    // to aim at it, not fall into it.
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Offstage(
          offstage: !showElevation || !showAccept,
          child: buildButton(context, tone: CmTone.accent, onClick: () {
            handleAccept(context);
            handleElevate(context);
            windowManager.minimize();
          },
                  text: 'Accept and Elevate',
                  glyph: LdIcons.shield,
                  tooltip: 'accept_and_elevate_btn_tooltip')
              .marginOnly(bottom: buttonGap),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showAccept) ...[
              Expanded(
                child: buildButton(
                  context,
                  tone: CmTone.accent,
                  glyph: LdIcons.check,
                  onClick: () {
                    handleAccept(context);
                    windowManager.minimize();
                  },
                  text: 'Accept',
                ),
              ),
              const SizedBox(width: buttonGap),
            ],
            Expanded(
              child: buildButton(
                context,
                tone: CmTone.neutral,
                glyph: LdIcons.close,
                onClick: handleDisconnect,
                text: 'Cancel',
              ),
            ),
          ],
        ),
      ],
    ).marginOnly(bottom: buttonBottomMargin);
  }

  /// Every answer this window offers, drawn by what it means.
  ///
  /// The click still goes through [checkClickTime]: the guard against a click
  /// that arrived before the person could have read what they were clicking is
  /// the reason this window is safe, and it is untouched.
  Widget buildButton(BuildContext context,
      {required CmTone tone,
      GestureTapCallback? onClick,
      String? glyph,
      required String text,
      String? tooltip,
      GestureTapDownCallback? onTapDown}) {
    assert(!(onClick == null && onTapDown == null));
    return CmActionButton(
      label: translate(text),
      tone: tone,
      glyph: glyph,
      tooltip: tooltip == null ? null : translate(tooltip),
      onPressed: onClick == null
          ? null
          : () {
              checkClickTime(client.id, onClick);
            },
      onTapDown: onTapDown == null
          ? null
          : (details) {
              checkClickTime(client.id, () {
                onTapDown.call(details);
              });
            },
    );
  }

  void handleDisconnect() {
    bind.cmCloseConnection(connId: client.id);
  }

  void handleAccept(BuildContext context) {
    final model = Provider.of<ServerModel>(context, listen: false);
    model.sendLoginResponse(client, true);
  }

  void handleElevate(BuildContext context) {
    final model = Provider.of<ServerModel>(context, listen: false);
    model.setShowElevation(false);
    bind.cmElevatePortable(connId: client.id);
  }

  void handleClose() async {
    await bind.cmRemoveDisconnectedConnection(connId: client.id);
    if (await bind.cmGetClientsLength() == 0) {
      windowManager.close();
    }
  }

  void handleSwitchBack(BuildContext context) {
    bind.cmSwitchBack(connId: client.id);
  }

  void handleVoiceCall(bool accept) {
    bind.cmHandleIncomingVoiceCall(id: client.id, accept: accept);
  }

  void closeVoiceCall() {
    bind.cmCloseVoiceCall(id: client.id);
  }
}

void checkClickTime(int id, Function() callback) async {
  if (allowRemoteCMModification()) {
    callback();
    return;
  }
  var clickCallbackTime = DateTime.now().millisecondsSinceEpoch;
  await bind.cmCheckClickTime(connId: id);
  Timer(const Duration(milliseconds: 120), () async {
    var d = clickCallbackTime - await bind.cmGetClickTime();
    if (d > 120) callback();
  });
}

bool allowRemoteCMModification() {
  return option2bool(kOptionAllowRemoteCmModification,
      bind.mainGetLocalOption(key: kOptionAllowRemoteCmModification));
}

class _FileTransferLogPage extends StatefulWidget {
  _FileTransferLogPage({Key? key}) : super(key: key);

  @override
  State<_FileTransferLogPage> createState() => __FileTransferLogPageState();
}

class __FileTransferLogPageState extends State<_FileTransferLogPage> {
  @override
  Widget build(BuildContext context) {
    return statusList();
  }

  Widget generateCard(Widget child) {
    return Container(decoration: CmSkin.panel, child: child);
  }

  /// What the far end did, glyph over word. The direction of a transfer is the
  /// whole point of the entry, so it is an arrow rather than a chevron.
  Widget _actionLabel(String glyph, String label) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LdIcon(glyph, size: 17, color: C.textMuted),
          const SizedBox(height: 5),
          Text(label,
              textAlign: TextAlign.center,
              style: C.micro(color: C.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      );

  iconLabel(CmFileLog item) {
    switch (item.action) {
      case CmFileAction.none:
        return Container();
      case CmFileAction.localToRemote:
      case CmFileAction.remoteToLocal:
        return _actionLabel(
            item.action == CmFileAction.remoteToLocal
                ? LdIcons.arrowUp
                : LdIcons.arrowDown,
            item.action == CmFileAction.remoteToLocal
                ? translate('Send')
                : translate('Receive'));
      case CmFileAction.remove:
        return _actionLabel(LdIcons.trash, translate('Delete'));
      case CmFileAction.createDir:
        return _actionLabel(LdIcons.folderAdd, translate('Create Folder'));
      case CmFileAction.rename:
        return _actionLabel(LdIcons.rename, translate('Rename'));
    }
  }

  Widget statusList() {
    return PreferredSize(
      preferredSize: const Size(200, double.infinity),
      child: Container(
          padding: const EdgeInsets.all(12.0),
          child: Obx(
            () {
              final jobTable = gFFI.cmFileModel.currentJobTable;
              statusListView(List<CmFileLog> jobs) => ListView.builder(
                    controller: ScrollController(),
                    itemBuilder: (BuildContext context, int index) {
                      final item = jobs[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: generateCard(
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 50,
                                    child: iconLabel(item),
                                  ).paddingOnly(left: 15),
                                  const SizedBox(
                                    width: 16.0,
                                  ),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.fileName,
                                          style: C.small(
                                              color: C.text,
                                              w: FontWeight.w600),
                                        ).paddingSymmetric(vertical: 8),
                                        if (item.totalSize > 0)
                                          Text(
                                            '${translate("Total")} ${readableFileSize(item.totalSize.toDouble())}',
                                            style: C.data(
                                                size: 11, color: C.textMuted),
                                          ),
                                        if (item.totalSize > 0)
                                          Offstage(
                                            offstage: item.state !=
                                                JobState.inProgress,
                                            child: Text(
                                              '${translate("Speed")} ${readableFileSize(item.speed)}/s',
                                              style: C.data(
                                                  size: 11, color: C.textMuted),
                                            ),
                                          ),
                                        Offstage(
                                          offstage: !(item.isTransfer() &&
                                              item.state !=
                                                  JobState.inProgress),
                                          child: Text(
                                            translate(
                                              item.display(),
                                            ),
                                            style: C.small(color: C.textMuted),
                                          ),
                                        ),
                                        if (item.totalSize > 0)
                                          Offstage(
                                            offstage: item.state !=
                                                JobState.inProgress,
                                            child: LinearPercentIndicator(
                                              padding:
                                                  EdgeInsets.only(right: 15),
                                              animateFromLastPercent: true,
                                              center: Text(
                                                '${(item.finishedSize / item.totalSize * 100).toStringAsFixed(0)}%',
                                                style: C.data(
                                                    size: 11, color: C.text),
                                              ),
                                              barRadius:
                                                  Radius.circular(C.radiusSm),
                                              percent: item.finishedSize /
                                                  item.totalSize,
                                              progressColor: C.accent,
                                              backgroundColor: C.surfaceHi,
                                              lineHeight: 18,
                                            ).paddingSymmetric(vertical: 12),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [],
                                  ),
                                ],
                              ),
                            ],
                          ).paddingSymmetric(vertical: 10),
                        ),
                      );
                    },
                    itemCount: jobTable.length,
                  );

              return jobTable.isEmpty
                  ? generateCard(
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const LdIcon(LdIcons.fileTransfer,
                                    size: 28, color: C.textFaint)
                                .paddingOnly(bottom: 12),
                            Text(
                              translate("No transfers in progress"),
                              textAlign: TextAlign.center,
                              style: C.small(color: C.textMuted),
                            ),
                          ],
                        ),
                      ),
                    )
                  : statusListView(jobTable);
            },
          )),
    );
  }
}
