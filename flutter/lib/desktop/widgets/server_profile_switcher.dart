// Home-page selector for server profiles, with a manual status refresh.
// Profiles are managed under Settings > Network > Server profiles.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/labdesk_profiles.dart';
import 'package:get/get.dart';

class ServerProfileSwitcher extends StatefulWidget {
  const ServerProfileSwitcher({Key? key}) : super(key: key);

  @override
  State<ServerProfileSwitcher> createState() => _ServerProfileSwitcherState();
}

class _ServerProfileSwitcherState extends State<ServerProfileSwitcher> {
  @override
  void initState() {
    super.initState();
    ServerProfilesModel.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final labelColor = Theme.of(context).textTheme.titleLarge?.color;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 6, 11, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translate('Server profile'),
            style: TextStyle(
              fontSize: 11,
              color: labelColor?.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Obx(() {
                    final names = ServerProfilesModel.profiles
                        .map((p) => p.name)
                        .toList();
                    final value =
                        names.contains(ServerProfilesModel.active.value)
                        ? ServerProfilesModel.active.value
                        : (names.isEmpty ? null : names.first);
                    return DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: value,
                        isExpanded: true,
                        isDense: true,
                        borderRadius: BorderRadius.circular(8),
                        style: TextStyle(fontSize: 12, color: labelColor),
                        items: names
                            .map(
                              (n) => DropdownMenuItem(
                                value: n,
                                child: Text(n, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: (n) {
                          if (n != null &&
                              n != ServerProfilesModel.active.value) {
                            ServerProfilesModel.activate(n);
                          }
                        },
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(width: 4),
              Obx(
                () => IconButton(
                  splashRadius: 15,
                  tooltip: translate('Refresh status'),
                  onPressed: labdeskStatusChecking.value
                      ? null
                      : () => labdeskRefreshStatus(),
                  icon: labdeskStatusChecking.value
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: MyTheme.accent,
                          ),
                        )
                      : Icon(Icons.refresh, size: 18, color: MyTheme.accent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
