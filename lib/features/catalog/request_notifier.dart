import 'package:csv/csv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'config_service.dart';
import 'imdb_service.dart';
import 'models/imdb_data.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

sealed class RequestState {}

class RequestIdle extends RequestState {}

class RequestValidating extends RequestState {}

class RequestReady extends RequestState {
  final String imdbId;
  final String imdbUrl;
  final String title;
  final int? year;
  final String type;
  final String posterUrl;

  RequestReady({
    required this.imdbId,
    required this.imdbUrl,
    required this.title,
    this.year,
    required this.type,
    required this.posterUrl,
  });
}

class RequestDuplicate extends RequestState {
  final String imdbId;
  final String imdbUrl;
  final String title;
  final int? year;
  final String type;
  final String posterUrl;

  RequestDuplicate({
    required this.imdbId,
    required this.imdbUrl,
    required this.title,
    this.year,
    required this.type,
    required this.posterUrl,
  });
}

class RequestSubmitting extends RequestState {}

class RequestSuccess extends RequestState {}

class RequestError extends RequestState {
  final String message;
  RequestError(this.message);
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final requestProvider =
    StateNotifierProvider<RequestNotifier, RequestState>((ref) {
  return RequestNotifier(ref);
});

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class RequestNotifier extends StateNotifier<RequestState> {
  final Ref _ref;
  RequestNotifier(this._ref) : super(RequestIdle());

  static final _imdbUrlRe =
      RegExp(r'imdb\.com/title/(tt\d+)', caseSensitive: false);
  static final _sheetIdRe =
      RegExp(r'/spreadsheets/d/([a-zA-Z0-9_-]+)');

  String? _extractImdbId(String url) =>
      _imdbUrlRe.firstMatch(url)?.group(1);

  // ── Validate ───────────────────────────────────────────────────────────────

  Future<void> validate(String imdbUrl) async {
    final id = _extractImdbId(imdbUrl.trim());
    if (id == null) {
      state =
          RequestError('Not a valid IMDB URL. Expected: imdb.com/title/tt…');
      return;
    }

    state = RequestValidating();

    try {
      final config =
          _ref.read(sheetConfigProvider).valueOrNull ?? const SheetConfig();

      // Type is unknown ahead of time for a pasted URL — resolveUnknown
      // tries /movie then /tv and tells us definitively which one matched.
      // (It can't resolve a link to a specific episode at all — the API has
      // no way to look one up except via its parent series + season +
      // episode number, none of which is recoverable from a bare ID.)
      final results = await Future.wait([
        ImdbService().resolveUnknown([id]),
        _fetchExistingIds(config.requestResUrl),
      ]);

      if (!mounted) return;

      final imdbMap = results[0] as Map<String, ImdbData>;
      final existingIds = results[1] as Set<String>;

      final data = imdbMap[id];

      if (existingIds.contains(id)) {
        state = RequestDuplicate(
          imdbId: id,
          imdbUrl: 'https://www.imdb.com/title/$id/',
          title: data?.title ?? id,
          year: data?.releaseDate?.year,
          type: _typeLabel(data),
          posterUrl: data?.posterUrl ?? '',
        );
        return;
      }

      if (data == null) {
        state = RequestError(
          "Couldn't find this on IMDb as a movie or TV series. If this "
          "links to a specific episode, please submit the show's main "
          'IMDb page instead.',
        );
        return;
      }

      state = RequestReady(
        imdbId: id,
        imdbUrl: 'https://www.imdb.com/title/$id/',
        title: data.title,
        year: data.releaseDate?.year,
        type: _typeLabel(data),
        posterUrl: data.posterUrl,
      );
    } catch (e) {
      if (mounted) state = RequestError('Could not fetch IMDB data: $e');
    }
  }

  static String _typeLabel(ImdbData? data) {
    if (data == null) return 'Unknown';
    return data.kind == ImdbKind.tv ? 'Series' : 'Movie';
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> submit() async {
    final ready = state;
    if (ready is! RequestReady) return;

    final config =
        _ref.read(sheetConfigProvider).valueOrNull ?? const SheetConfig();
    final formUrl = config.requestFormUrl;
    if (formUrl == null || formUrl.isEmpty) return;

    state = RequestSubmitting();

    try {
      final prefill = Uri.parse(formUrl);
      final submissionPath =
          prefill.path.replaceFirst('/viewform', '/formResponse');
      final submissionUri = Uri(
        scheme: prefill.scheme,
        host: prefill.host,
        path: submissionPath,
      );

      // Extract the first entry.XXXXXXXXXX parameter from the pre-fill URL.
      final entryParam = prefill.queryParameters.entries
          .firstWhere(
            (e) => e.key.startsWith('entry.'),
            orElse: () => const MapEntry('', ''),
          )
          .key;

      if (entryParam.isEmpty) {
        if (mounted) {
          state = RequestError(
              'Form configuration error — no entry field found in the URL.');
        }
        return;
      }

      final body =
          '$entryParam=${Uri.encodeComponent(ready.imdbUrl)}';

      final response = await http
          .post(
            submissionUri,
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      // Google Forms returns 200 (thank-you HTML) on success, or a redirect.
      if (response.statusCode >= 200 && response.statusCode < 400) {
        state = RequestSuccess();
      } else {
        state = RequestError(
            'Submission failed (HTTP ${response.statusCode}). Try again.');
      }
    } catch (e) {
      if (mounted) state = RequestError('Submission failed: $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<Set<String>> _fetchExistingIds(String? resUrl) async {
    if (resUrl == null || resUrl.isEmpty) return {};
    try {
      final sheetId = _sheetIdRe.firstMatch(resUrl)?.group(1);
      if (sheetId == null) return {};

      final csvUrl =
          'https://docs.google.com/spreadsheets/d/$sheetId/gviz/tq?tqx=out:csv';
      final response = await http
          .get(Uri.parse(csvUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200 ||
          response.body.trimLeft().startsWith('<')) {
        return {};
      }

      final normalized =
          response.body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      final rows =
          const CsvToListConverter(eol: '\n').convert(normalized);
      if (rows.isEmpty) return {};

      final headers = rows[0]
          .map((h) => h.toString().trim().toLowerCase())
          .toList();
      final linkIdx = headers.indexOf('imdb link');
      if (linkIdx < 0) return {};

      final ids = <String>{};
      for (final row in rows.skip(1)) {
        if (linkIdx < row.length) {
          final m = _imdbUrlRe.firstMatch(row[linkIdx].toString());
          if (m != null) ids.add(m.group(1)!);
        }
      }
      return ids;
    } catch (_) {
      return {};
    }
  }

  void reset() => state = RequestIdle();
}
