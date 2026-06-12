import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'catalog_notifier.dart';

class SheetConfig {
  final String? requestFormUrl;
  final String? requestResUrl;

  const SheetConfig({this.requestFormUrl, this.requestResUrl});

  bool get hasRequestFeature =>
      requestFormUrl != null && requestFormUrl!.isNotEmpty;
}

final sheetConfigProvider =
    StateNotifierProvider<SheetConfigNotifier, AsyncValue<SheetConfig>>((ref) {
  final notifier = SheetConfigNotifier(ref);
  final url = ref.read(sheetUrlProvider);
  if (url != null) notifier.load(url);
  ref.listen<String?>(sheetUrlProvider, (_, next) {
    if (next != null) notifier.load(next);
  });
  return notifier;
});

class SheetConfigNotifier extends StateNotifier<AsyncValue<SheetConfig>> {
  SheetConfigNotifier(Ref ref) : super(const AsyncValue.data(SheetConfig()));

  static const _kCacheTtl = Duration(minutes: 30);

  static String? _extractSheetId(String url) {
    final m = RegExp(r'/spreadsheets/d/([a-zA-Z0-9_-]+)').firstMatch(url);
    return m?.group(1);
  }

  Future<void> load(String sheetUrl) async {
    final sheetId = _extractSheetId(sheetUrl);
    if (sheetId == null) return;

    final cached = await _loadCache(sheetId);
    if (cached != null) {
      if (mounted) state = AsyncValue.data(cached.config);
      if (DateTime.now().difference(cached.fetchedAt) < _kCacheTtl) return;
      unawaited(_fetch(sheetId, silent: true));
      return;
    }

    await _fetch(sheetId, silent: false);
  }

  Future<void> _fetch(String sheetId, {required bool silent}) async {
    if (!silent && mounted) state = const AsyncValue.loading();
    try {
      final url =
          'https://docs.google.com/spreadsheets/d/$sheetId/gviz/tq?tqx=out:csv&sheet=Config';
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 ||
          response.body.trimLeft().startsWith('<')) {
        if (!silent && mounted) {
          state = const AsyncValue.data(SheetConfig());
        }
        return;
      }
      final config = _parse(response.body);
      unawaited(_saveCache(sheetId, config));
      if (mounted) state = AsyncValue.data(config);
    } catch (_) {
      if (!silent && mounted) state = const AsyncValue.data(SheetConfig());
    }
  }

  static SheetConfig _parse(String csvBody) {
    final normalized =
        csvBody.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rows = const CsvToListConverter(eol: '\n').convert(normalized);
    final map = <String, String>{};
    for (final row in rows) {
      if (row.length >= 2) {
        final key = row[0].toString().trim();
        final value = row[1].toString().trim();
        if (key.isNotEmpty && value.isNotEmpty) map[key] = value;
      }
    }
    return SheetConfig(
      requestFormUrl: map['request_form_url'],
      requestResUrl: map['request_res_url'],
    );
  }

  // ── Cache helpers ──────────────────────────────────────────────────────────

  Future<({SheetConfig config, DateTime fetchedAt})?> _loadCache(
      String sheetId) async {
    try {
      final dir = (await getApplicationSupportDirectory()).path;
      final file = File(p.join(dir, 'sheet_config_$sheetId.json'));
      if (!file.existsSync()) return null;
      final map =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final at = DateTime.tryParse(map['fetchedAt'] as String? ?? '');
      if (at == null) return null;
      final data = map['data'] as Map<String, dynamic>;
      return (
        config: SheetConfig(
          requestFormUrl: data['request_form_url'] as String?,
          requestResUrl: data['request_res_url'] as String?,
        ),
        fetchedAt: at,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache(String sheetId, SheetConfig config) async {
    try {
      final dir = (await getApplicationSupportDirectory()).path;
      await File(p.join(dir, 'sheet_config_$sheetId.json')).writeAsString(
        jsonEncode({
          'fetchedAt': DateTime.now().toIso8601String(),
          'data': {
            if (config.requestFormUrl != null)
              'request_form_url': config.requestFormUrl,
            if (config.requestResUrl != null)
              'request_res_url': config.requestResUrl,
          },
        }),
      );
    } catch (_) {}
  }
}
