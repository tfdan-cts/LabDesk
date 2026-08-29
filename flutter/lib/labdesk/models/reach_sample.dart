/// One sample of how many machines answered at a point in time.
///
/// A plain value type with no Flutter import, because the status binding
/// produces these and the binding is reached from peer_model. Living in the
/// chart file meant the shipping app's model layer pulled the whole chart and
/// the console theme in behind it, for the sake of three fields.
class ReachSample {
  const ReachSample(this.at, this.online, this.total);

  final DateTime at;
  final int online;
  final int total;

  double get ratio => total == 0 ? 0 : online / total;
}
