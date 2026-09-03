// Server profiles: named ID/Relay/API/key configurations that can be
// switched from the home screen and managed under Settings > Network.
// Stored locally as JSON in the 'labdesk-server-profiles' local option;
// the live option keys stay the source of truth for the rest of the app.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/labdesk_status_binding.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

const _kProfilesKey = 'labdesk-server-profiles';
const _kActiveKey = 'labdesk-active-server-profile';

const kLiveServerKeys = <String>[
  'custom-rendezvous-server',
  'relay-server',
  'api-server',
  'key',
];

class ServerProfile {
  String name;
  String host;
  String relay;
  String api;
  String key;

  ServerProfile({
    required this.name,
    this.host = '',
    this.relay = '',
    this.api = '',
    this.key = '',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'host': host,
    'relay': relay,
    'api': api,
    'key': key,
  };

  static ServerProfile fromJson(Map<String, dynamic> m) => ServerProfile(
    name: m['name'] as String? ?? '',
    host: m['host'] as String? ?? '',
    relay: m['relay'] as String? ?? '',
    api: m['api'] as String? ?? '',
    key: m['key'] as String? ?? '',
  );
}

class ServerProfilesModel {
  ServerProfilesModel._();

  static final RxList<ServerProfile> profiles = RxList<ServerProfile>();
  static final RxString active = ''.obs;
  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final s = bind.mainGetLocalOption(key: _kProfilesKey);
      if (s.isNotEmpty) {
        profiles.assignAll(
          (jsonDecode(s) as List)
              .whereType<Map<String, dynamic>>()
              .map(ServerProfile.fromJson)
              .toList(),
        );
      }
    } catch (e) {
      debugPrint('failed to load server profiles: $e');
    }
    active.value = bind.mainGetLocalOption(key: _kActiveKey);
    if (profiles.isEmpty) {
      await _migrate();
    }
    await _syncActiveFromLive();
  }

  // Build the initial profile list, picking up the legacy A/B slots if
  // they exist, otherwise seeding a single profile from the live config.
  static Future<void> _migrate() async {
    Future<List<String>> read(List<String> keys) async {
      final out = <String>[];
      for (final k in keys) {
        out.add(await bind.mainGetOption(key: k));
      }
      return out;
    }

    final live = await read(kLiveServerKeys);
    final oldActive = await bind.mainGetOption(key: 'active-profile');
    if (oldActive.isNotEmpty) {
      final aStash = await read([
        'profile-a-host',
        'profile-a-relay',
        'profile-a-api',
        'profile-a-key',
      ]);
      final bStash = await read([
        'profile-b-host',
        'profile-b-relay',
        'profile-b-api',
        'profile-b-key',
      ]);
      final aName = await bind.mainGetOption(key: 'profile-a-name');
      final bName = await bind.mainGetOption(key: 'profile-b-name');
      final a = oldActive == 'a' ? live : aStash;
      final b = oldActive == 'b' ? live : bStash;
      profiles.assignAll([
        ServerProfile(
          name: aName.isEmpty ? 'A' : aName,
          host: a[0],
          relay: a[1],
          api: a[2],
          key: a[3],
        ),
        ServerProfile(
          name: bName.isEmpty ? 'B' : bName,
          host: b[0],
          relay: b[1],
          api: b[2],
          key: b[3],
        ),
      ]);
      active.value = oldActive == 'b' ? profiles[1].name : profiles[0].name;
      for (final k in [
        'active-profile',
        'profile-a-host',
        'profile-a-relay',
        'profile-a-api',
        'profile-a-key',
        'profile-b-host',
        'profile-b-relay',
        'profile-b-api',
        'profile-b-key',
        'profile-a-name',
        'profile-b-name',
      ]) {
        await bind.mainSetOption(key: k, value: '');
      }
    } else {
      profiles.add(
        ServerProfile(
          name: 'Default',
          host: live[0],
          relay: live[1],
          api: live[2],
          key: live[3],
        ),
      );
      active.value = 'Default';
    }
    await save();
  }

  // If the live keys were edited elsewhere (e.g. the ID/Relay server
  // dialog), fold those values back into the active profile.
  static Future<void> _syncActiveFromLive() async {
    final p = byName(active.value);
    if (p == null) {
      if (profiles.isNotEmpty) {
        active.value = profiles.first.name;
        await save();
      }
      return;
    }
    final host = await bind.mainGetOption(key: kLiveServerKeys[0]);
    final relay = await bind.mainGetOption(key: kLiveServerKeys[1]);
    final api = await bind.mainGetOption(key: kLiveServerKeys[2]);
    final key = await bind.mainGetOption(key: kLiveServerKeys[3]);
    if (p.host != host || p.relay != relay || p.api != api || p.key != key) {
      p.host = host;
      p.relay = relay;
      p.api = api;
      p.key = key;
      await save();
    }
  }

  static ServerProfile? byName(String name) =>
      profiles.firstWhereOrNull((p) => p.name == name);

  static Future<void> save() async {
    await bind.mainSetLocalOption(
      key: _kProfilesKey,
      value: profiles.isEmpty
          ? ''
          : jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
    await bind.mainSetLocalOption(key: _kActiveKey, value: active.value);
    profiles.refresh();
  }

  static Future<void> applyLive(ServerProfile p) async {
    final oldApi = await bind.mainGetApiServer();
    await bind.mainSetOption(key: kLiveServerKeys[0], value: p.host);
    await bind.mainSetOption(key: kLiveServerKeys[1], value: p.relay);
    await bind.mainSetOption(key: kLiveServerKeys[2], value: p.api);
    await bind.mainSetOption(key: kLiveServerKeys[3], value: p.key);
    final newApi = await bind.mainGetApiServer();
    if (oldApi.isNotEmpty && oldApi != newApi && gFFI.userModel.isLogin) {
      gFFI.userModel.logOut(apiServer: oldApi);
    }
  }

  static Future<void> activate(String name) async {
    final p = byName(name);
    if (p == null) return;
    active.value = name;
    await applyLive(p);
    await save();
    showToast('${translate('Server profile')}: $name');
    labdeskRefreshStatus();
  }

  static String uniqueName(String base, {ServerProfile? ignore}) {
    var name = base.trim().isEmpty ? 'Profile' : base.trim();
    var i = 2;
    while (profiles.any((p) => p != ignore && p.name == name)) {
      name = '$base $i';
      i++;
    }
    return name;
  }

  static Future<void> addOrUpdate(
    ServerProfile? existing,
    String name,
    String host,
    String relay,
    String api,
    String key,
  ) async {
    if (existing == null) {
      final p = ServerProfile(
        name: uniqueName(name),
        host: host,
        relay: relay,
        api: api,
        key: key,
      );
      profiles.add(p);
      if (profiles.length == 1) {
        active.value = p.name;
        await applyLive(p);
      }
    } else {
      final wasActive = existing.name == active.value;
      existing.name = uniqueName(name, ignore: existing);
      existing.host = host;
      existing.relay = relay;
      existing.api = api;
      existing.key = key;
      if (wasActive) {
        active.value = existing.name;
        await applyLive(existing);
        labdeskRefreshStatus();
      }
    }
    await save();
  }

  static Future<void> remove(ServerProfile p) async {
    if (profiles.length <= 1) return;
    final wasActive = p.name == active.value;
    profiles.remove(p);
    if (wasActive) {
      await activate(profiles.first.name);
    }
    await save();
  }
}

// Peer status: green = reachable, red = unreachable, amber = checking.
// A status query is in flight whenever [labdeskStatusChecking] is true;
// it is set on profile switches, manual refresh and network-affecting
// events, and cleared when the next query_onlines response arrives.
final RxBool labdeskStatusChecking = false.obs;
Timer? _checkingTimeout;

void labdeskStatusTick() {
  _checkingTimeout?.cancel();
  labdeskStatusChecking.value = false;
}

void labdeskMarkStatusStale() {
  labdeskStatusChecking.value = true;
  _checkingTimeout?.cancel();
  _checkingTimeout = Timer(const Duration(seconds: 10), () {
    labdeskStatusChecking.value = false;
  });
}

// Settings > Network card body: list, add, edit, delete server profiles.
class ServerProfilesSettings extends StatefulWidget {
  const ServerProfilesSettings({Key? key}) : super(key: key);

  @override
  State<ServerProfilesSettings> createState() => _ServerProfilesSettingsState();
}

class _ServerProfilesSettingsState extends State<ServerProfilesSettings> {
  @override
  void initState() {
    super.initState();
    ServerProfilesModel.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final items = <Widget>[];
      for (final p in ServerProfilesModel.profiles) {
        final isActive = p.name == ServerProfilesModel.active.value;
        items.add(
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Radio<String>(
              value: p.name,
              groupValue: ServerProfilesModel.active.value,
              onChanged: (v) {
                if (v != null) ServerProfilesModel.activate(v);
              },
            ),
            title: Text(
              p.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            subtitle: Text(
              p.host.isEmpty ? translate('Public server') : p.host,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  splashRadius: 16,
                  tooltip: translate('Edit profile'),
                  icon: const Icon(Icons.edit, size: 16),
                  onPressed: () => showServerProfileEditDialog(context, p),
                ),
                IconButton(
                  splashRadius: 16,
                  tooltip: translate('Delete profile'),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: ServerProfilesModel.profiles.length <= 1
                        ? null
                        : Colors.red,
                  ),
                  onPressed: ServerProfilesModel.profiles.length <= 1
                      ? null
                      : () => showConfirmDeleteProfile(context, p),
                ),
              ],
            ),
          ),
        );
      }
      items.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => showServerProfileEditDialog(context, null),
            icon: Icon(Icons.add, size: 18, color: MyTheme.accent),
            label: Text(
              translate('Add profile'),
              style: TextStyle(color: MyTheme.accent),
            ),
          ).marginOnly(left: 8, bottom: 4),
        ),
      );
      return Column(children: items);
    });
  }
}

void showConfirmDeleteProfile(BuildContext context, ServerProfile p) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${translate('Delete profile')}: ${p.name}'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(translate('Cancel')),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            ServerProfilesModel.remove(p);
          },
          child: Text(
            translate('OK'),
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ],
    ),
  );
}

Future<void> showServerProfileEditDialog(
  BuildContext context,
  ServerProfile? p,
) async {
  final name = TextEditingController(text: p?.name ?? '');
  final host = TextEditingController(text: p?.host ?? '');
  final relay = TextEditingController(text: p?.relay ?? '');
  final api = TextEditingController(text: p?.api ?? '');
  final key = TextEditingController(text: p?.key ?? '');

  Widget field(
    String label,
    TextEditingController c, {
    bool autofocus = false,
  }) {
    return TextField(
      controller: c,
      autofocus: autofocus,
      decoration: InputDecoration(labelText: translate(label), isDense: true),
    ).marginOnly(bottom: 12);
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(translate(p == null ? 'Add profile' : 'Edit profile')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            field('Name', name, autofocus: p == null),
            field('ID Server', host),
            field('Relay Server', relay),
            // No API server field: the LabDesk account is global and always
            // lives at lab-desk.net, whichever profile is active. The value is
            // kept in the profile for older configs but never edited here.
            field('Server key', key),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(translate('Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(translate('OK')),
        ),
      ],
    ),
  );
  if (ok == true) {
    await ServerProfilesModel.addOrUpdate(
      p,
      name.text,
      host.text.trim(),
      relay.text.trim(),
      api.text.trim(),
      key.text.trim(),
    );
  }
}

Future<void> labdeskRefreshStatus() async {
  labdeskMarkStatusStale();
  bind.mainLoadRecentPeers();
  bind.mainLoadFavPeers();
  final ids = <String>{};
  for (final p in gFFI.recentPeersModel.peers) {
    ids.add(p.id);
  }
  for (final p in gFFI.favoritePeersModel.peers) {
    ids.add(p.id);
  }
  for (final p in gFFI.peerTabModel.currentTabCachedPeers) {
    ids.add(p.id);
  }
  if (ids.isNotEmpty) {
    // Mark the ask before it goes out, so the console can show it as open
    // until the server answers or the binding writes it off.
    labdeskStatus.beginQuery(ids);
    bind.queryOnlines(ids: ids.toList(growable: false));
  }
}
