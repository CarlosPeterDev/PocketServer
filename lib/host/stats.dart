/// Live traffic / activity counters. One instance per isolate that runs servers;
/// a JSON snapshot travels to the UI inside HostStatus.
class Stats {
  static final Stats i = Stats();

  int inBytes = 0; // uploaded to this device
  int outBytes = 0; // downloaded from this device
  int requests = 0;
  int logins = 0;
  int failedLogins = 0;
  int ftpConnections = 0;
  final Map<String, int> inBy = {};
  final Map<String, int> outBy = {};
  final List<Map<String, dynamic>> events = []; // newest last
  final List<double> speedIn = [];
  final List<double> speedOut = [];
  int _lastIn = 0, _lastOut = 0;
  final DateTime started = DateTime.now();

  void addIn(int n, String server) {
    inBytes += n;
    inBy[server] = (inBy[server] ?? 0) + n;
  }

  void addOut(int n, String server) {
    outBytes += n;
    outBy[server] = (outBy[server] ?? 0) + n;
  }

  void event(String server, String kind, String text) {
    events.add({'t': DateTime.now().millisecondsSinceEpoch, 's': server, 'k': kind, 'x': text});
    if (events.length > 80) events.removeRange(0, events.length - 80);
    if (kind == 'login') logins++;
    if (kind == 'failed') failedLogins++;
  }

  /// Call once per second.
  void sample() {
    speedIn.add((inBytes - _lastIn).toDouble());
    speedOut.add((outBytes - _lastOut).toDouble());
    _lastIn = inBytes;
    _lastOut = outBytes;
    if (speedIn.length > 60) speedIn.removeAt(0);
    if (speedOut.length > 60) speedOut.removeAt(0);
  }

  Map<String, dynamic> toJson() => {
        'in': inBytes,
        'out': outBytes,
        'req': requests,
        'logins': logins,
        'failed': failedLogins,
        'conns': ftpConnections,
        'inBy': inBy,
        'outBy': outBy,
        'events': events.reversed.take(40).toList(),
        'sIn': speedIn,
        'sOut': speedOut,
        'since': started.millisecondsSinceEpoch,
      };
}
