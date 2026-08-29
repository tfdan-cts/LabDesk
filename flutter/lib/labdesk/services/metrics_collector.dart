import '../models/machine_metrics.dart';

/// One command that asks a machine about itself, and the platforms it suits.
class MetricsProbe {
  const MetricsProbe({required this.platform, required this.command});

  final String platform;

  /// A single line, so it can be written to a PTY and its output read back
  /// without needing an interactive shell or a script upload.
  final String command;
}

/// Reads a machine's own numbers over the terminal channel.
///
/// LabDesk has no agent on the far end, but it already opens a headless PTY to
/// a peer for the terminal feature. That channel is enough: ask the machine
/// about itself with one command and parse what it prints.
///
/// Every field is tagged with a LABDESK_ prefix. Shell profiles print banners,
/// mail notices and login messages, and without a tag the parser would have to
/// guess which line is a number. With one, anything untagged is ignored.
class MetricsCollector {
  MetricsCollector._();

  /// Linux: CPU from /proc/stat sampled twice, memory from /proc/meminfo, disk
  /// from the root filesystem, uptime from /proc/uptime. Deliberately avoids
  /// top and vmstat, whose output differs between distributions.
  static const _linux = r'''awk '/^cpu /{a=$2+$4;t=$2+$4+$5}END{print a,t}' /proc/stat > /tmp/.ld1; sleep 1; awk -v p="$(cat /tmp/.ld1)" '/^cpu /{split(p,q," ");a=$2+$4;t=$2+$4+$5;d=t-q[2];if(d>0)printf "LABDESK_CPU=%.1f\n",(a-q[1])*100/d}' /proc/stat; awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{if(t>0){printf "LABDESK_MEM_USED=%d\nLABDESK_MEM_TOTAL=%d\n",(t-a)*1024,t*1024}}' /proc/meminfo; df -B1 / | awk 'NR==2{printf "LABDESK_DISK_USED=%d\nLABDESK_DISK_TOTAL=%d\n",$3,$2}'; awk '{printf "LABDESK_UPTIME=%d\n",$1}' /proc/uptime''';

  /// Windows: CIM rather than the deprecated wmic, in one PowerShell call.
  static const _windows =
      r'''powershell -NoProfile -Command "$os=Get-CimInstance Win32_OperatingSystem; $cpu=(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average; $d=Get-CimInstance Win32_LogicalDisk -Filter \"DeviceID='C:'\"; Write-Output ('LABDESK_CPU=' + $cpu); Write-Output ('LABDESK_MEM_USED=' + (($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) * 1024)); Write-Output ('LABDESK_MEM_TOTAL=' + ($os.TotalVisibleMemorySize * 1024)); Write-Output ('LABDESK_DISK_USED=' + ($d.Size - $d.FreeSpace)); Write-Output ('LABDESK_DISK_TOTAL=' + $d.Size); Write-Output ('LABDESK_UPTIME=' + [int]((Get-Date) - $os.LastBootUpTime).TotalSeconds)"''';

  /// macOS: page counts from vm_stat, sized by the real page size rather than
  /// an assumed 4096, which is wrong on Apple silicon.
  static const _macos = r'''ps -A -o %cpu | awk '{s+=$1}END{printf "LABDESK_CPU=%.1f\n",s/'"$(sysctl -n hw.ncpu)"'}'; vm_stat | awk -v ps="$(sysctl -n hw.pagesize)" -v tot="$(sysctl -n hw.memsize)" '/Pages free/{f=$3}/Pages inactive/{i=$3}END{gsub(/\./,"",f);gsub(/\./,"",i);printf "LABDESK_MEM_USED=%d\nLABDESK_MEM_TOTAL=%d\n",tot-(f+i)*ps,tot}'; df -k / | awk 'NR==2{printf "LABDESK_DISK_USED=%d\nLABDESK_DISK_TOTAL=%d\n",$3*1024,$2*1024}'; awk -v b="$(sysctl -n kern.boottime | sed -E 's/.*sec = ([0-9]+).*/\1/')" 'BEGIN{printf "LABDESK_UPTIME=%d\n",systime()-b}' ''';

  static const _probes = <String, MetricsProbe>{
    'linux': MetricsProbe(platform: 'linux', command: _linux),
    'windows': MetricsProbe(platform: 'windows', command: _windows),
    'macos': MetricsProbe(platform: 'macos', command: _macos),
  };

  /// The probe for a platform string as the client reports it, or null when
  /// the platform is not one this can read. Null rather than a guess: running
  /// a Linux command on an unknown system produces noise, not data.
  static MetricsProbe? probeFor(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('linux')) return _probes['linux'];
    if (p.contains('win')) return _probes['windows'];
    if (p.contains('mac') || p.contains('darwin')) return _probes['macos'];
    return null;
  }

  /// Turn raw terminal output into metrics.
  ///
  /// Only tagged lines are read, so shell banners and login notices are
  /// ignored. A field that is missing, unparseable, or paired with a zero
  /// total is dropped rather than rendered as zero, because zero reads as a
  /// measurement that was taken.
  static List<Metric> parse(String raw) {
    final fields = <String, double>{};
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (!t.startsWith('LABDESK_')) continue;
      final eq = t.indexOf('=');
      if (eq < 0) continue;
      final key = t.substring(8, eq);
      final value = double.tryParse(t.substring(eq + 1).trim());
      if (value == null || value.isNaN || value < 0) continue;
      fields[key] = value;
    }

    final out = <Metric>[];

    final cpu = fields['CPU'];
    if (cpu != null) {
      final pct = cpu.clamp(0.0, 100.0);
      out.add(Metric(
        label: 'CPU',
        value: pct.round().toString(),
        unit: '%',
        source: MetricSource.remote,
        ratio: pct / 100,
      ));
    }

    void share(String label, String usedKey, String totalKey) {
      final used = fields[usedKey];
      final total = fields[totalKey];
      if (used == null || total == null || total <= 0) return;
      final ratio = (used / total).clamp(0.0, 1.0);
      out.add(Metric(
        label: label,
        value: (ratio * 100).round().toString(),
        unit: '%',
        source: MetricSource.remote,
        ratio: ratio,
      ));
    }

    share('Memory', 'MEM_USED', 'MEM_TOTAL');
    share('Disk', 'DISK_USED', 'DISK_TOTAL');

    final up = fields['UPTIME'];
    if (up != null) {
      out.add(Metric(
        label: 'Uptime',
        value: formatUptime(up.round()),
        source: MetricSource.remote,
      ));
    }

    return out;
  }

  /// What Health shows for a platform this cannot read, so the screen states
  /// the limit rather than showing four dashes with no explanation.
  static List<Metric> unsupported() => const [
        Metric.unavailable('CPU'),
        Metric.unavailable('Memory'),
        Metric.unavailable('Disk'),
        Metric.unavailable('Uptime'),
      ];
}
