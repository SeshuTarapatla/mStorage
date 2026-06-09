import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'update_model.dart';

class UpdateService {
  static const _owner = 'SeshuTarapatla';
  static const _repo = 'mStorage';

  static bool isNewer(String latest, String current) {
    final l = _parseVersion(latest);
    final c = _parseVersion(current);
    for (int i = 0; i < 3; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }

  static List<int> _parseVersion(String v) {
    return v.replaceFirst(RegExp(r'^v'), '').split('.').map((s) => int.tryParse(s) ?? 0).toList();
  }

  Future<UpdateInfo?> checkForUpdate(String currentVersion) async {
    final response = await http.get(
      Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases/latest'),
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'mStorage-app',
      },
    );

    if (response.statusCode == 404) return null; // no releases yet
    if (response.statusCode != 200) {
      throw Exception('GitHub API returned ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final tagName = json['tag_name'] as String? ?? '';
    final latestVersion = tagName.replaceFirst(RegExp(r'^v'), '');

    if (!isNewer(latestVersion, currentVersion)) return null;

    final assets = (json['assets'] as List? ?? []).cast<Map<String, dynamic>>();
    final asset = assets.firstWhere(
      (a) => (a['name'] as String? ?? '').endsWith('.exe'),
      orElse: () => {},
    );

    final assetUrl = asset['browser_download_url'] as String? ?? '';
    if (assetUrl.isEmpty) throw Exception('No .exe asset found in release');

    return UpdateInfo(
      version: latestVersion,
      releaseNotes: json['body'] as String? ?? '',
      assetUrl: assetUrl,
      assetName: asset['name'] as String? ?? 'mStorage_Setup.exe',
    );
  }

  Future<String> downloadUpdate(
    UpdateInfo info,
    void Function(double) onProgress,
  ) async {
    final tmpDir = await getTemporaryDirectory();
    final updateDir = Directory(p.join(tmpDir.path, 'mstorage_update'));

    // Remove any stale installers before downloading.
    if (updateDir.existsSync()) {
      for (final f in updateDir.listSync().whereType<File>()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    await updateDir.create(recursive: true);

    final destPath = p.join(updateDir.path, info.assetName);
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(info.assetUrl));
      final response = await client.send(request);
      final total = response.contentLength ?? 0;
      final sink = File(destPath).openWrite();
      int received = 0;

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress(received / total);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
    } finally {
      client.close();
    }

    return destPath;
  }

  Future<void> launchInstaller(String installerPath) async {
    await Process.start(
      installerPath,
      [],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
  }
}
