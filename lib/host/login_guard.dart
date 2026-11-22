/// Blocks an IP address for a while after too many failed logins.
class LoginGuard {
  static final LoginGuard i = LoginGuard();
  static const maxFails = 6;
  static const window = Duration(minutes: 10);
  static const lockFor = Duration(minutes: 10);

  final Map<String, List<DateTime>> _fails = {};
  final Map<String, DateTime> _locked = {};

  bool isLocked(String ip) {
    final t = _locked[ip];
    if (t == null) return false;
    if (DateTime.now().isAfter(t)) {
      _locked.remove(ip);
      _fails.remove(ip);
      return false;
    }
    return true;
  }

  void fail(String ip) {
    final now = DateTime.now();
    final l = _fails.putIfAbsent(ip, () => []);
    l.removeWhere((t) => now.difference(t) > window);
    l.add(now);
    if (l.length >= maxFails) _locked[ip] = now.add(lockFor);
    if (_fails.length > 2000) _fails.clear();
  }

  void ok(String ip) => _fails.remove(ip);

  void clear() {
    _fails.clear();
    _locked.clear();
  }
}
