import 'dart:io';

class GhAuthService {
  static final _instance = GhAuthService._();
  factory GhAuthService() => _instance;
  GhAuthService._();

  bool? _authorized;

  Future<bool> isAuthorized() async {
    if (_authorized != null) return _authorized!;
    try {
      final result = await Process.run(
        'gh', ['auth', 'status'],
        stdoutEncoding: systemEncoding,
        stderrEncoding: systemEncoding,
      );
      // gh auth status writes primarily to stderr
      final output = '${result.stdout}\n${result.stderr}';
      _authorized = output.contains('SeshuTarapatla');
    } catch (_) {
      _authorized = false;
    }
    return _authorized!;
  }
}
