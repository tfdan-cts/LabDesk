// Local machine groups and per-peer icon overrides, stored as JSON in the
// 'labdesk-groups' and 'labdesk-peer-icons' local options. The Groups tab
// draws its peers from the recent-sessions store.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import 'dialog.dart';
import 'peer_card.dart';

// The 10 selectable machine icons (plus platform default).
const Map<String, IconData> kLabDeskIcons = {
  'pc': Icons.desktop_windows,
  'laptop': Icons.laptop,
  'server': Icons.dns,
  'nas': Icons.storage,
  'home': Icons.home,
  'business': Icons.business,
  'warehouse': Icons.warehouse,
  'router': Icons.router,
  'phone': Icons.smartphone,
  'cloud': Icons.cloud,
};

const _kGroupsKey = 'labdesk-groups';
const _kPeerIconsKey = 'labdesk-peer-icons';

class LabDeskGroup {
  String name;
  String icon; // key in kLabDeskIcons, '' = default folder
  bool collapsed;
  List<String> peers;

  LabDeskGroup({
    required this.name,
    this.icon = '',
    this.collapsed = false,
    List<String>? peers,
  }) : peers = peers ?? [];

  Map<String, dynamic> toJson() => {
    'name': name,
    'icon': icon,
    'collapsed': collapsed,
    'peers': peers,
  };

  static LabDeskGroup fromJson(Map<String, dynamic> m) => LabDeskGroup(
    name: m['name'] as String? ?? '',
    icon: m['icon'] as String? ?? '',
    collapsed: m['collapsed'] as bool? ?? false,
    peers: (m['peers'] as List?)?.whereType<String>().toList(),
  );
}

class LabDeskGroupsModel {
  LabDeskGroupsModel._();

  static final RxList<LabDeskGroup> groups = RxList<LabDeskGroup>();
  static final RxMap<String, String> peerIcons = RxMap<String, String>();
  static bool _loaded = false;

  static void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      final s = bind.mainGetLocalOption(key: _kGroupsKey);
      if (s.isNotEmpty) {
        groups.assignAll(
          (jsonDecode(s) as List)
              .whereType<Map<String, dynamic>>()
              .map(LabDeskGroup.fromJson)
              .toList(),
        );
      }
    } catch (e) {
      debugPrint('labdesk: failed to load groups: $e');
    }
    try {
      final s = bind.mainGetLocalOption(key: _kPeerIconsKey);
      if (s.isNotEmpty) {
        peerIcons.assignAll(Map<String, String>.from(jsonDecode(s)));
      }
    } catch (e) {
      debugPrint('labdesk: failed to load peer icons: $e');
    }
  }

  static Future<void> saveGroups() async {
    await bind.mainSetLocalOption(
      key: _kGroupsKey,
      value: groups.isEmpty
          ? ''
          : jsonEncode(groups.map((g) => g.toJson()).toList()),
    );
    groups.refresh();
  }

  static Future<void> savePeerIcons() async {
    await bind.mainSetLocalOption(
      key: _kPeerIconsKey,
      value: peerIcons.isEmpty
          ? ''
          : jsonEncode(Map<String, String>.from(peerIcons)),
    );
    peerIcons.refresh();
  }

  static Future<void> setPeerIcon(String id, String icon) async {
    if (icon.isEmpty) {
      peerIcons.remove(id);
    } else {
      peerIcons[id] = icon;
    }
    await savePeerIcons();
  }
}

/// Icon for a peer card: the user-chosen themed icon, or the platform image.
Widget labdeskPeerIcon(Peer peer, double size) {
  LabDeskGroupsModel.ensureLoaded();
  return Obx(() {
    final icon = kLabDeskIcons[LabDeskGroupsModel.peerIcons[peer.id]];
    return icon == null
        ? getPlatformImage(peer.platform, size: size)
        : Icon(icon, size: size, color: Colors.white);
  });
}

/// Dialog: pick one of the 10 themed icons (or reset to platform default).
Future<void> showLabDeskIconPicker(BuildContext context, String peerId) async {
  LabDeskGroupsModel.ensureLoaded();
  final current = LabDeskGroupsModel.peerIcons[peerId] ?? '';
  final picked = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(translate('Choose icon')),
      content: SizedBox(
        width: 300,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _iconChoice(
              context,
              '',
              Icons.devices_other,
              translate('Default'),
              current,
            ),
            ...kLabDeskIcons.entries.map(
              (e) => _iconChoice(context, e.key, e.value, e.key, current),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(translate('Cancel')),
        ),
      ],
    ),
  );
  if (picked != null) {
    await LabDeskGroupsModel.setPeerIcon(peerId, picked);
  }
}

Widget _iconChoice(
  BuildContext context,
  String key,
  IconData icon,
  String tooltip,
  String current,
) {
  final selected = key == current;
  return Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: () => Navigator.of(context).pop(key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: selected ? MyTheme.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? MyTheme.accent : MyTheme.border),
        ),
        child: Icon(
          icon,
          size: 28,
          color: selected
              ? Colors.white
              : Theme.of(context).textTheme.titleLarge?.color,
        ),
      ),
    ),
  );
}

/// Dialog: check/uncheck the groups a peer belongs to.
Future<void> showLabDeskAssignDialog(
  BuildContext context,
  String peerId,
) async {
  LabDeskGroupsModel.ensureLoaded();
  if (LabDeskGroupsModel.groups.isEmpty) {
    showToast(translate('No groups yet'));
    return;
  }
  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(translate('Groups')),
      content: Container(
        width: 300,
        constraints: const BoxConstraints(maxHeight: 320),
        child: Obx(
          () => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: LabDeskGroupsModel.groups
                  .map(
                    (g) => CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(g.name),
                      value: g.peers.contains(peerId),
                      onChanged: (v) {
                        if (v == true) {
                          g.peers.add(peerId);
                        } else {
                          g.peers.remove(peerId);
                        }
                        LabDeskGroupsModel.saveGroups();
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(translate('OK')),
        ),
      ],
    ),
  );
}

/// Dialog: create or edit a group (name, icon, members).
Future<void> _showGroupEditDialog(
  BuildContext context, {
  LabDeskGroup? group,
  required List<Peer> knownPeers,
}) async {
  final isNew = group == null;
  final nameController = TextEditingController(text: group?.name ?? '');
  final icon = (group?.icon ?? '').obs;
  final members = RxList<String>(group?.peers.toList() ?? []);
  // Known peers first; keep members that are no longer in recents visible too.
  final ids = knownPeers.map((p) => p.id).toList();
  final extraMembers = members
      .where((id) => !ids.contains(id))
      .toList(growable: false);

  String peerLabel(String id) {
    final p = knownPeers.firstWhereOrNull((p) => p.id == id);
    if (p == null) return id;
    final alias = p.alias.isEmpty ? formatID(p.id) : p.alias;
    return p.hostname.isEmpty ? alias : '$alias (${p.hostname})';
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(translate(isNew ? 'New group' : 'Edit group')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              autofocus: isNew,
              maxLength: 24,
              decoration: InputDecoration(labelText: translate('Group name')),
            ),
            const SizedBox(height: 8),
            Obx(
              () => Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _groupIconChip(context, '', Icons.folder, icon),
                  ...kLabDeskIcons.entries.map(
                    (e) => _groupIconChip(context, e.key, e.value, icon),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              translate('Machines'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(
              height: 260,
              child: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: Obx(
                    () => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [...ids, ...extraMembers]
                          .map(
                            (id) => CheckboxListTile(
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                peerLabel(id),
                                overflow: TextOverflow.ellipsis,
                              ),
                              value: members.contains(id),
                              onChanged: (v) {
                                if (v == true) {
                                  if (!members.contains(id)) {
                                    members.add(id);
                                  }
                                } else {
                                  members.remove(id);
                                }
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
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
  if (ok != true) return;
  final name = nameController.text.trim();
  if (name.isEmpty) return;
  if (isNew) {
    LabDeskGroupsModel.groups.add(
      LabDeskGroup(name: name, icon: icon.value, peers: members.toList()),
    );
  } else {
    group!.name = name;
    group.icon = icon.value;
    group.peers = members.toList();
  }
  await LabDeskGroupsModel.saveGroups();
}

Widget _groupIconChip(
  BuildContext context,
  String key,
  IconData iconData,
  RxString icon,
) {
  final selected = icon.value == key;
  return InkWell(
    onTap: () => icon.value = key,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: selected ? MyTheme.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: selected ? MyTheme.accent : MyTheme.border),
      ),
      child: Icon(
        iconData,
        size: 20,
        color: selected
            ? Colors.white
            : Theme.of(context).textTheme.titleLarge?.color,
      ),
    ),
  );
}

/// The Groups tab: collapsible group sections over the recent-sessions store.
class LocalGroupsView extends StatefulWidget {
  final EdgeInsets? menuPadding;
  const LocalGroupsView({Key? key, this.menuPadding}) : super(key: key);

  @override
  State<LocalGroupsView> createState() => _LocalGroupsViewState();
}

class _LocalGroupsViewState extends State<LocalGroupsView> {
  @override
  void initState() {
    super.initState();
    LabDeskGroupsModel.ensureLoaded();
    bind.mainLoadRecentPeers();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<Peers>.value(
      value: gFFI.recentPeersModel,
      child: Consumer<Peers>(
        builder: (context, peers, child) => Obx(() {
          final groups = LabDeskGroupsModel.groups;
          final byId = {for (final p in peers.peers) p.id: p};
          final grouped = groups.expand((g) => g.peers).toSet();
          final ungrouped = peers.peers
              .where((p) => !grouped.contains(p.id))
              .toList();
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _showGroupEditDialog(
                        context,
                        knownPeers: peers.peers,
                      ),
                      icon: Icon(
                        Icons.create_new_folder_outlined,
                        size: 18,
                        color: MyTheme.accent,
                      ),
                      label: Text(
                        translate('New group'),
                        style: TextStyle(color: MyTheme.accent),
                      ),
                    ),
                  ],
                ),
                ...groups.map(
                  (g) => _buildGroupSection(context, g, byId, peers.peers),
                ),
                if (ungrouped.isNotEmpty)
                  _buildSectionHeader(
                    context,
                    icon: Icons.folder_open,
                    name: translate('Ungrouped'),
                    count: ungrouped.length,
                    collapsed: false,
                    onToggle: null,
                  ),
                if (ungrouped.isNotEmpty) _buildPeerList(ungrouped),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildGroupSection(
    BuildContext context,
    LabDeskGroup g,
    Map<String, Peer> byId,
    List<Peer> knownPeers,
  ) {
    final members = g.peers.map((id) => byId[id]).whereType<Peer>().toList();
    final missing = g.peers.where((id) => !byId.containsKey(id)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          context,
          icon: kLabDeskIcons[g.icon] ?? Icons.folder,
          name: g.name,
          count: g.peers.length,
          collapsed: g.collapsed,
          onToggle: () {
            g.collapsed = !g.collapsed;
            LabDeskGroupsModel.saveGroups();
          },
          onEdit: () =>
              _showGroupEditDialog(context, group: g, knownPeers: knownPeers),
          onDelete: () {
            deleteConfirmDialog(() async {
              LabDeskGroupsModel.groups.remove(g);
              await LabDeskGroupsModel.saveGroups();
            }, '${translate('Delete group')}: ${g.name}');
          },
        ),
        if (!g.collapsed) _buildPeerList(members, missingIds: missing),
      ],
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String name,
    required int count,
    required bool collapsed,
    VoidCallback? onToggle,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    final color = Theme.of(context).textTheme.titleLarge?.color;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(6),
              child: Row(
                children: [
                  Icon(
                    collapsed ? Icons.chevron_right : Icons.expand_more,
                    size: 20,
                    color: onToggle == null
                        ? Colors.transparent
                        : color?.withOpacity(0.7),
                  ),
                  Icon(
                    icon,
                    size: 18,
                    color: MyTheme.accent,
                  ).marginOnly(right: 6),
                  Flexible(
                    child: Text(
                      '$name ($count)',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ).paddingSymmetric(vertical: 6),
            ),
          ),
          if (onEdit != null)
            IconButton(
              splashRadius: 16,
              icon: Icon(Icons.edit, size: 16, color: color?.withOpacity(0.7)),
              tooltip: translate('Edit group'),
              onPressed: onEdit,
            ),
          if (onDelete != null)
            IconButton(
              splashRadius: 16,
              icon: const Icon(
                Icons.delete_outline,
                size: 16,
                color: Colors.red,
              ),
              tooltip: translate('Delete group'),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }

  Widget _buildPeerList(List<Peer> peers, {List<String>? missingIds}) {
    final space = 12.0;
    return Obx(() {
      final isGrid = peerCardUiType.value == PeerUiType.grid;
      final cards = peers
          .map(
            (p) => isGrid
                ? SizedBox(
                    width: 220,
                    height: 140,
                    child: RecentPeerCard(
                      peer: p,
                      menuPadding: widget.menuPadding,
                    ),
                  )
                : Container(
                    height: 45,
                    margin: EdgeInsets.only(bottom: space / 2),
                    child: RecentPeerCard(
                      peer: p,
                      menuPadding: widget.menuPadding,
                    ),
                  ),
          )
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          isGrid
              ? Wrap(spacing: space, runSpacing: space / 2, children: cards)
              : Column(children: cards),
          if (missingIds != null && missingIds.isNotEmpty)
            Text(
              '${translate('Not in recent sessions')}: ${missingIds.join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ).paddingOnly(left: 26, bottom: 4),
        ],
      ).paddingOnly(left: 20, top: 2);
    });
  }
}
