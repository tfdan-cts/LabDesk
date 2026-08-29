import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/common/labdesk_profiles.dart';
import 'package:flutter_hbb/common/labdesk_status_binding.dart';
import 'package:flutter_hbb/common/widgets/labdesk_groups.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/widgets/server_profile_switcher.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import 'console_data.dart';
import 'models/machine_row.dart';
import 'screens/actions_screen.dart';
import 'screens/console_shell.dart';
import 'screens/settings_screen.dart';
import 'screens/this_machine_screen.dart';
import 'theme/console_theme.dart';

/// The console, driven by the real client.
///
/// This is the only file in `lib/labdesk` that touches the FFI. Everything
/// behind it takes plain values and hands back callbacks, which is what lets
/// the whole surface be rendered and judged from `lib/labdesk_preview.dart`
/// without a peer, a Rust core or a generated bridge.
///
/// What is wired, and what is honestly not: connecting, opening a terminal and
/// transferring files all go through the client's own `connect`, so they work.
/// Capturing a screen and restarting a machine need a session that is already
/// open, and the main window holds no registry of open sessions, because on
/// desktop each one runs in its own window. Rather than invent that registry
/// here, the console reports no connected machines, so those two actions render
/// disabled with their explanation intact. The Health screen says the same
/// thing about its own panels. That is the design the screens were built to:
/// an absent capability is shown as absent, never as a control that does
/// nothing.
class LabDeskConsolePage extends StatefulWidget {
  const LabDeskConsolePage({super.key});

  @override
  State<LabDeskConsolePage> createState() => _LabDeskConsolePageState();
}

class _LabDeskConsolePageState extends State<LabDeskConsolePage> {
  Timer? _tick;
  bool _refreshing = false;
  DateTime? _lastRefreshed;

  /// Lets controls that mean "go to settings" move the console rather than
  /// open a second settings surface in its own tab.
  final _sectionRequest = ValueNotifier(ConsoleSection.connect);
  var _settingsTab = SettingsTabKey.general;
  var _section = ConsoleSection.connect;

  /// The stop-service flag the client's own widgets read.
  ///
  /// DesktopHomePage used to own this, and both ConnectionPage
  /// (connection_page.dart:36) and Settings > General
  /// (desktop_setting_page.dart:409) resolve it with Get.find, which throws
  /// when nothing has registered it. Unmounting the home page took the
  /// registration with it, so the console has to own it now: it hosts both of
  /// those widgets.
  final _svcStopped = false.obs;

  void _goToSettings(SettingsTabKey tab) {
    setState(() => _settingsTab = tab);
    // Setting the value is enough. When the console is already on settings the
    // notifier does not fire, but the setState above has already rebuilt the
    // hosted page against the new key, which is the only thing that needed to
    // change.
    _sectionRequest.value = ConsoleSection.settings;
  }

  @override
  void initState() {
    super.initState();
    LabDeskGroupsModel.ensureLoaded();
    ServerProfilesModel.ensureLoaded();
    if (!Get.isRegistered<RxBool>(tag: 'stop-service')) {
      Get.put<RxBool>(_svcStopped, tag: 'stop-service');
    }
    // ponytail: a one second repaint rather than plumbing change notification
    // through a store that is deliberately plain Dart. This is a monitoring
    // surface whose figures are seconds old by nature, and the alternative is
    // reactive wiring in a layer kept free of it on purpose.
    //
    // Only while Fleet is showing, though. Everything else here is either the
    // application's own widget or a screen with nothing that changes second to
    // second, and rebuilding the hosted connect page or a settings page once a
    // second is work nobody asked for.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) async {
      // This machine's own id arrives by polling and nothing else. The home
      // page fetched it every second and took that with it when it was
      // unmounted, which left the id reading "Generating ..." forever.
      // fetchID notifies, so the Consumer around ThisMachineScreen rebuilds
      // itself when the id lands; no setState is needed for it.
      await gFFI.serverModel.fetchID();
      // The service flag is polled for the same reason: nothing signals a
      // change in the service's state.
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != _svcStopped.value) _svcStopped.value = v;
      if (mounted && _section == ConsoleSection.fleet) setState(() {});
    });
    // Ask once on open so the fleet is not blank while waiting for the client's
    // own poll to come round.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _sectionRequest.dispose();
    Get.delete<RxBool>(tag: 'stop-service');
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await labdeskRefreshStatus();
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _lastRefreshed = DateTime.now();
        });
      }
    }
  }

  /// Recent sessions, favourites and whichever peer tab is open. Three stores
  /// that overlap; the adapter folds them.
  Iterable<ConsolePeer> get _peers sync* {
    for (final list in [
      gFFI.recentPeersModel.peers,
      gFFI.favoritePeersModel.peers,
      gFFI.peerTabModel.currentTabCachedPeers,
    ]) {
      for (final p in list) {
        yield (
          id: p.id,
          hostname: p.hostname,
          platform: p.platform,
          alias: p.alias,
          username: p.username,
        );
      }
    }
  }

  String? _groupOf(String id) {
    for (final g in LabDeskGroupsModel.groups) {
      if (g.peers.contains(id)) return g.name;
    }
    return null;
  }

  List<MachineRow> get _machines => buildMachineRows(
        peers: _peers,
        store: labdeskStatus.store,
        historyOf: labdeskStatus.historyOf,
        groupOf: _groupOf,
      );

  List<ProfileRow> get _profiles => [
        for (final p in ServerProfilesModel.profiles)
          ProfileRow(
            name: p.name,
            host: p.host,
            relay: p.relay,
            api: p.api,
            hasKey: p.key.isNotEmpty,
            active: p.name == ServerProfilesModel.active.value,
          )
      ];

  void _runAction(String machineId, MachineAction action) {
    switch (action.id) {
      case 'connect':
        connect(context, machineId);
        break;
      case 'terminal':
        connect(context, machineId, isTerminal: true);
        break;
      case 'transfer':
        connect(context, machineId, isFileTransfer: true);
        break;
      default:
        // screenshot and reboot need an open session. The screen disables them
        // while there is none, so reaching here would mean the screen and this
        // switch disagree about what is possible.
        debugPrint('labdesk: no handler for action ${action.id}');
    }
  }

  /// The application's own connect surface: the remote-id card and every peer
  /// tab, including LabDesk's groups. Mounted whole rather than reimplemented,
  /// so none of the behaviour behind those ~200 controls is lost in the move.
  Widget _connect(BuildContext context) => ConnectionPage();

  /// One settings page, with no navigation of its own.
  ///
  /// Mounting DesktopSettingPage whole put a second navigation rail beside the
  /// console's, which is two sidebars for one interface. Its pages are nested
  /// in the console's own sidebar instead, and only the body renders here.
  Widget _settings(BuildContext context) => Container(
        color: C.bg,
        child: settingsPageBody(_settingsTab),
      );

  Widget _thisMachine(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(
        builder: (context, model, _) => ThisMachineScreen(
          machineId: model.serverId.text,
          password: model.serverPasswd.text,
          passwordIsTemporary:
              model.verificationMethod != kUsePermanentPassword,
          serviceRunning: model.isStart,
          profileSwitcher: const ServerProfileSwitcher(),
          // Both of these existed on the old left rail and would have been lost
          // in the move. The catalogue of the old interface is what caught it.
          onRefreshPassword: () => bind.mainUpdateTemporaryPassword(),
          onEditPassword: () => _goToSettings(SettingsTabKey.safety),
          onStartService: model.isStart ? null : () => start_service(true),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final machines = _machines;
    return Container(
      color: C.bg,
      child: ConsoleShell(
        machines: machines,
        samples: labdeskStatus.samples,
        profiles: _profiles,
        profileName: ServerProfilesModel.active.value,
        isRefreshing: _refreshing || labdeskStatus.isQuerying,
        // The fleet is only genuinely loading before anything has been asked.
        isLoading: machines.isEmpty && _lastRefreshed == null,
        lastRefreshed: _lastRefreshed,
        onRefresh: _refresh,
        connectedIds: const {},
        onRunAction: _runAction,
        sectionRequest: _sectionRequest,
        onSectionChanged: (s) => setState(() => _section = s),
        subItems: {
          ConsoleSection.settings: [
            for (final p in settingsPages())
              ConsoleSubItem(id: p.key.name, label: p.label, icon: p.icon),
          ],
        },
        selectedSubItem: _settingsTab.name,
        onSubItemSelected: (section, id) {
          if (section != ConsoleSection.settings) return;
          for (final p in settingsPages()) {
            if (p.key.name == id) {
              setState(() => _settingsTab = p.key);
              break;
            }
          }
        },
        hosted: {
          ConsoleSection.connect: _connect,
          ConsoleSection.thisMachine: _thisMachine,
          ConsoleSection.settings: _settings,
        },
      ),
    );
  }
}
