// Design harness for LabDesk UI work.
//
// Renders LabDesk widgets against fixture data with no FFI, no Rust core and
// no peer connection, so the interface can be looked at and judged in seconds
// rather than after a full application build. Run it with:
//
//   flutter run -t lib/labdesk_preview.dart -d windows
//   flutter run -t lib/labdesk_preview.dart -d chrome --web-port=5899
//
// It is a separate entry point, so it is never part of the shipped app. Nothing
// here may import the FFI layer: the moment it does, the harness stops building
// without the generated bridge and the fast loop is gone.
import 'package:flutter/material.dart';

import 'common/labdesk_peer_status.dart';
import 'labdesk/widgets/fleet_status_summary.dart';

void main() => runApp(const LabDeskPreviewApp());

class LabDeskPreviewApp extends StatefulWidget {
  const LabDeskPreviewApp({super.key});

  @override
  State<LabDeskPreviewApp> createState() => _LabDeskPreviewAppState();
}

class _LabDeskPreviewAppState extends State<LabDeskPreviewApp> {
  ThemeMode _mode = ThemeMode.dark;

  static const _seed = Color(0xFF7C5CFF);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LabDesk preview',
      themeMode: _mode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
      ),
      home: _Gallery(
        mode: _mode,
        onToggleMode: () => setState(() => _mode =
            _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark),
      ),
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.mode, required this.onToggleMode});

  final ThemeMode mode;
  final VoidCallback onToggleMode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LabDesk preview'),
        actions: [
          IconButton(
            tooltip: 'Toggle theme',
            onPressed: onToggleMode,
            icon: Icon(mode == ThemeMode.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Case(
                  title: 'Typical fleet',
                  child: FleetStatusSummary(
                    online: 12,
                    offline: 3,
                    unknown: 2,
                    isRefreshing: false,
                  ),
                ),
                _Case(
                  title: 'Refresh in flight, previous state retained',
                  child: FleetStatusSummary(
                    online: 12,
                    offline: 3,
                    unknown: 2,
                    isRefreshing: true,
                    lastRefreshed:
                        DateTime.now().subtract(const Duration(seconds: 45)),
                  ),
                ),
                const _Case(
                  title: 'Nothing known yet, a first run',
                  child: FleetStatusSummary(
                    online: 0,
                    offline: 0,
                    unknown: 0,
                  ),
                ),
                _Case(
                  title: 'Built straight from the store',
                  child: FleetStatusSummary.fromStore(_demoStore()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

LabDeskPeerStatusStore _demoStore() {
  final store = LabDeskPeerStatusStore()
    ..applyResponse(
      onlines: ['101', '102', '103', '104'],
      offlines: ['201'],
      at: DateTime.now().subtract(const Duration(seconds: 20)),
    );
  return store;
}

class _Case extends StatelessWidget {
  const _Case({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.1,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
