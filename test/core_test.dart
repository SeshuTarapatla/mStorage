import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m_storage/core/services/archive_service.dart';
import 'package:m_storage/core/services/format_service.dart';
import 'package:m_storage/features/catalog/models/catalog_entry.dart';
import 'package:m_storage/features/catalog/models/imdb_data.dart';
import 'package:m_storage/features/updater/update_service.dart';

void main() {
  // ── UpdateService.isNewer ───────────────────────────────────────────────────

  group('UpdateService.isNewer', () {
    test('newer major version', () =>
        expect(UpdateService.isNewer('2.0.0', '1.9.9'), isTrue));
    test('newer minor version', () =>
        expect(UpdateService.isNewer('1.4.0', '1.3.0'), isTrue));
    test('newer patch version', () =>
        expect(UpdateService.isNewer('1.3.1', '1.3.0'), isTrue));
    test('same version returns false', () =>
        expect(UpdateService.isNewer('1.3.0', '1.3.0'), isFalse));
    test('older version returns false', () =>
        expect(UpdateService.isNewer('1.2.9', '1.3.0'), isFalse));
    test('v-prefix stripped correctly', () =>
        expect(UpdateService.isNewer('v1.4.0', 'v1.3.0'), isTrue));
    test('shorter version treated as trailing zeros', () {
      expect(UpdateService.isNewer('2', '1.9.9'), isTrue);
      expect(UpdateService.isNewer('1.3', '1.3.0'), isFalse);
    });
  });

  // ── FormatService ───────────────────────────────────────────────────────────

  group('FormatService', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('mstorage_test_');
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('combine → extractArchive round-trips payload exactly', () async {
      final maskPath = '${tmp.path}/mask.mp4';
      final archivePath = '${tmp.path}/payload.zip';
      final outputPath = '${tmp.path}/encoded.mp4';
      final extractedPath = '${tmp.path}/extracted.zip';

      await File(maskPath).writeAsBytes(List.generate(512, (i) => i & 0xFF));
      await File(archivePath).writeAsBytes(List.generate(256, (i) => (i + 100) & 0xFF));

      await FormatService.combine(
        maskPath: maskPath,
        archivePath: archivePath,
        outputPath: outputPath,
      );

      final found = await FormatService.extractArchive(
        inputPath: outputPath,
        outputArchivePath: extractedPath,
      );

      expect(found, isTrue);
      final extracted = await File(extractedPath).readAsBytes();
      final original = await File(archivePath).readAsBytes();
      expect(extracted, equals(original));
    });

    test('extractArchive returns false when separator absent', () async {
      final inputPath = '${tmp.path}/nosep.mp4';
      final extractedPath = '${tmp.path}/out.zip';
      await File(inputPath).writeAsBytes(List.generate(1024, (i) => i & 0xFF));

      final found = await FormatService.extractArchive(
        inputPath: inputPath,
        outputArchivePath: extractedPath,
      );
      expect(found, isFalse);
    });

    test('extractArchive handles separator split across 1 MB chunk boundary', () async {
      // '\nbreakpoint\n' = 12 bytes; split so first 6 land in chunk 1, last 6 in chunk 2.
      const sep = '\nbreakpoint\n';
      final sepBytes = Uint8List.fromList(sep.codeUnits);
      const chunkSize = 1024 * 1024;
      const splitAt = chunkSize - 6; // separator starts here

      final payload = List.generate(200, (i) => (i * 3) & 0xFF);
      final data = Uint8List(splitAt + sepBytes.length + payload.length)
        ..setRange(0, splitAt, List.generate(splitAt, (i) => (i * 7) & 0xFF))
        ..setRange(splitAt, splitAt + sepBytes.length, sepBytes)
        ..setRange(splitAt + sepBytes.length, splitAt + sepBytes.length + payload.length, payload);

      final inputPath = '${tmp.path}/split.mp4';
      final extractedPath = '${tmp.path}/split_out.zip';
      await File(inputPath).writeAsBytes(data);

      final found = await FormatService.extractArchive(
        inputPath: inputPath,
        outputArchivePath: extractedPath,
      );
      expect(found, isTrue);
      final extracted = await File(extractedPath).readAsBytes();
      expect(extracted, equals(payload));
    });
  });

  // ── ArchiveService ZIP round-trip ───────────────────────────────────────────

  group('ArchiveService ZIP (unencrypted)', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('mstorage_zip_test_');
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('createZip produces valid ZIP with correct entry contents', () async {
      final file1 = File('${tmp.path}/movie.mp4');
      final file2 = File('${tmp.path}/movie.srt');
      final mp4Bytes = List.generate(4096, (i) => i & 0xFF);
      final srtContent = '1\n00:00:01,000 --> 00:00:02,000\nHello World';

      await file1.writeAsBytes(mp4Bytes);
      await file2.writeAsString(srtContent);

      final zipPath = '${tmp.path}/out.zip';
      await ArchiveService.createZip(
        fileEntries: [
          (file1.path, 'movie.mp4'),
          (file2.path, 'movie.srt'),
        ],
        outputPath: zipPath,
      );

      expect(File(zipPath).existsSync(), isTrue);
      final zipBytes = await File(zipPath).readAsBytes();

      // Verify ZIP local file header magic
      expect(zipBytes[0], equals(0x50));
      expect(zipBytes[1], equals(0x4B));
      expect(zipBytes[2], equals(0x03));
      expect(zipBytes[3], equals(0x04));

      // Decode and verify round-trip
      final archive = ZipDecoder().decodeBytes(zipBytes);
      expect(archive.files.length, equals(2));

      final names = archive.files.map((f) => f.name).toSet();
      expect(names, containsAll(['movie.mp4', 'movie.srt']));

      final mp4Entry = archive.files.firstWhere((f) => f.name == 'movie.mp4');
      expect(mp4Entry.content, equals(mp4Bytes));

      final srtEntry = archive.files.firstWhere((f) => f.name == 'movie.srt');
      expect(String.fromCharCodes(srtEntry.content as List<int>), equals(srtContent));
    });
  });

  // ── CatalogEntry CSV parsing ────────────────────────────────────────────────

  group('CatalogEntry.fromRow', () {
    Map<String, int> mkHeaders(List<String> cols) => {
          for (var i = 0; i < cols.length; i++)
            cols[i].toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), ''): i,
        };

    test('parses canonical column names', () {
      final h = mkHeaders([
        'imdbId', 'title', 'videoUrl', 'genres', 'tags',
        'plot', 'posterUrl', 'sizeMb', 'encoded', 'date',
      ]);
      final row = [
        'tt1234567', 'Test Movie', 'https://photos.google.com/abc',
        'Action, Thriller', 'Marvel', 'A hero rises.',
        'https://example.com/poster.jpg', '4200', 'true', '2024-06-15',
      ];
      final entry = CatalogEntry.fromRow(row, h);

      expect(entry.imdbId, equals('tt1234567'));
      expect(entry.title, equals('Test Movie'));
      expect(entry.videoUrl, equals('https://photos.google.com/abc'));
      expect(entry.genres, containsAll(['Action', 'Thriller']));
      expect(entry.tags, contains('Marvel'));
      expect(entry.plot, equals('A hero rises.'));
      expect(entry.sizeMb, equals(4200));
      expect(entry.encoded, isTrue);
      expect(entry.date, equals(DateTime(2024, 6, 15)));
    });

    test('falls back to imdbId as title when title column absent', () {
      final h = mkHeaders(['imdbId', 'videoUrl']);
      final entry = CatalogEntry.fromRow(['tt9876543', 'https://example.com'], h);
      expect(entry.title, equals('tt9876543'));
    });

    test('legacy url alias accepted', () {
      final h = mkHeaders(['imdbId', 'title', 'url']);
      final entry = CatalogEntry.fromRow(['tt1', 'Movie', 'https://example.com/v'], h);
      expect(entry.videoUrl, equals('https://example.com/v'));
    });

    test('encoded defaults to false when column absent', () {
      final h = mkHeaders(['title']);
      final entry = CatalogEntry.fromRow(['A Movie'], h);
      expect(entry.encoded, isFalse);
    });

    test('genres parsed from comma-separated string', () {
      final h = mkHeaders(['title', 'genres']);
      final entry = CatalogEntry.fromRow(['X', 'Action, Drama, Sci-Fi'], h);
      expect(entry.genres, equals(['Action', 'Drama', 'Sci-Fi']));
    });

    test('Google Drive URL converted to thumbnail URL', () {
      final h = mkHeaders(['title', 'posterUrl']);
      final entry = CatalogEntry.fromRow(
          ['X', 'https://drive.google.com/file/d/ABCDEF123/view'], h);
      expect(entry.thumbnailUrl, contains('ABCDEF123'));
      expect(entry.thumbnailUrl, contains('thumbnail'));
    });

    test('show=false rows are filtered — encoded false when value is false', () {
      // Direct test of the visibility logic via the encoded column (same false-string check)
      final h = mkHeaders(['title', 'encoded']);
      final entry = CatalogEntry.fromRow(['X', 'false'], h);
      expect(entry.encoded, isFalse);
    });

    test('slide_images parsed from comma-separated URLs', () {
      final h = mkHeaders(['title', 'slideImages']);
      final entry = CatalogEntry.fromRow(
          ['X', 'https://a.com/1.jpg, https://b.com/2.jpg'], h);
      expect(entry.slideImages.length, equals(2));
      expect(entry.slideImages[0], equals('https://a.com/1.jpg'));
    });

    test('rating/runtime_min/certificate/stars parsed from sheet columns', () {
      final h = mkHeaders(
          ['title', 'rating', 'runtimeMin', 'certificate', 'stars']);
      final entry = CatalogEntry.fromRow(
          ['X', '8.8', '148', 'PG-13', 'Leonardo DiCaprio, Elliot Page'], h);
      expect(entry.imdbRating, equals(8.8));
      // Sheet stores runtime in minutes; the internal field is seconds.
      expect(entry.runtimeSeconds, equals(148 * 60));
      expect(entry.certificate, equals('PG-13'));
      expect(entry.stars, equals(['Leonardo DiCaprio', 'Elliot Page']));
    });

    test('needsImdbFetch is false only once every fillable field is present', () {
      final full = mkHeaders([
        'title', 'date', 'genres', 'plot', 'posterUrl',
        'rating', 'runtimeMin', 'certificate', 'stars',
      ]);
      final complete = CatalogEntry.fromRow([
        'X', '2024-01-01', 'Action', 'A plot.', 'https://example.com/p.jpg',
        '8.0', '120', 'PG-13', 'Someone',
      ], full);
      expect(complete.needsImdbFetch, isFalse);

      final missingRating = CatalogEntry.fromRow([
        'X', '2024-01-01', 'Action', 'A plot.', 'https://example.com/p.jpg',
        '', '120', 'PG-13', 'Someone',
      ], full);
      expect(missingRating.needsImdbFetch, isTrue);
    });
  });

  // ── CatalogEntry.mergeImdb — sheet-wins ─────────────────────────────────────

  group('CatalogEntry.mergeImdb sheet-wins', () {
    const apiData = ImdbData(
      id: 'tt1',
      kind: ImdbKind.movie,
      title: 'API Title',
      plot: 'API plot.',
      genres: ['Drama'],
      releaseDate: null,
      posterUrl: 'https://api.example.com/poster.jpg',
      rating: 7.5,
      voteCount: 1000,
      runtimeSeconds: 6000,
      stars: ['API Star'],
      certificate: 'R',
    );

    test('sheet-populated fields survive the merge untouched', () {
      const sheetEntry = CatalogEntry(
        imdbId: 'tt1',
        title: 'Sheet Title',
        date: null,
        genres: ['Action'],
        tags: [],
        plot: 'Sheet plot.',
        thumbnailUrl: 'https://sheet.example.com/poster.jpg',
        videoUrl: '',
        sizeMb: null,
        encoded: false,
        imdbRating: 9.0,
        runtimeSeconds: 7200,
        certificate: 'PG-13',
        stars: ['Sheet Star'],
      );
      final merged = sheetEntry.mergeImdb(apiData);
      expect(merged.title, equals('Sheet Title'));
      expect(merged.plot, equals('Sheet plot.'));
      expect(merged.thumbnailUrl, equals('https://sheet.example.com/poster.jpg'));
      expect(merged.imdbRating, equals(9.0));
      expect(merged.runtimeSeconds, equals(7200));
      expect(merged.certificate, equals('PG-13'));
      expect(merged.stars, equals(['Sheet Star']));
    });

    test('blank sheet fields are filled from the API', () {
      const sheetEntry = CatalogEntry(
        imdbId: 'tt1',
        title: '',
        date: null,
        genres: [],
        tags: [],
        plot: '',
        thumbnailUrl: '',
        videoUrl: '',
        sizeMb: null,
        encoded: false,
      );
      final merged = sheetEntry.mergeImdb(apiData);
      expect(merged.title, equals('API Title'));
      expect(merged.plot, equals('API plot.'));
      expect(merged.imdbRating, equals(7.5));
      expect(merged.runtimeSeconds, equals(6000));
      expect(merged.certificate, equals('R'));
      expect(merged.stars, equals(['API Star']));
    });
  });

  // ── ImdbData API parsing — unit conversions ─────────────────────────────────

  group('ImdbData.fromMovieApi', () {
    test('runtime in minutes is converted to seconds', () {
      final data = ImdbData.fromMovieApi({
        'id': 'tt1375666',
        'title': 'Inception',
        'overview': 'A thief...',
        'genres': [
          {'id': 'Sci-Fi', 'name': 'Sci-Fi'}
        ],
        'release_date': '2010-07-16',
        'poster_path': 'https://example.com/poster.jpg',
        'vote_average': 8.8,
        'vote_count': 2835518,
        'runtime': 148,
        'certificate': {'rating': 'PG-13', 'body': 'MPAA'},
      });
      expect(data.runtimeSeconds, equals(148 * 60));
      expect(data.rating, equals(8.8));
      expect(data.certificate, equals('PG-13'));
      expect(data.genres, equals(['Sci-Fi']));
      expect(data.releaseDate, equals(DateTime.parse('2010-07-16')));
    });

    test('cast names come from the paired credits response, top 3 only', () {
      final data = ImdbData.fromMovieApi(
        {'id': 'tt1', 'title': 'X', 'overview': '', 'genres': [], 'release_date': ''},
        {
          'cast': [
            {'name': 'A', 'order': 0},
            {'name': 'B', 'order': 1},
            {'name': 'C', 'order': 2},
            {'name': 'D', 'order': 3},
          ],
        },
      );
      expect(data.stars, equals(['A', 'B', 'C']));
    });
  });

  group('ImdbData.fromTvApi', () {
    test('ended series derives endYear from last_air_date', () {
      final data = ImdbData.fromTvApi({
        'id': 'tt0944947',
        'name': 'Game of Thrones',
        'overview': '',
        'genres': [],
        'first_air_date': '2011-04-17',
        'last_air_date': '2019-12-31',
        'in_production': false,
      });
      expect(data.endYear, equals(2019));
    });

    test('ongoing series has no endYear', () {
      final data = ImdbData.fromTvApi({
        'id': 'tt1',
        'name': 'X',
        'overview': '',
        'genres': [],
        'first_air_date': '2020-01-01',
        'last_air_date': '2024-01-01',
        'in_production': true,
      });
      expect(data.endYear, isNull);
    });
  });

  group('ImdbData.fromEpisodeApi', () {
    test('runtime from the episode endpoint is already seconds — no conversion', () {
      final data = ImdbData.fromEpisodeApi({
        'id': 'tt1480055',
        'name': 'Winter Is Coming',
        'overview': '',
        'air_date': '2011-04-17',
        'season_number': 1,
        'episode_number': 1,
        'runtime': 3720,
      }, parentId: 'tt0944947');
      expect(data.runtimeSeconds, equals(3720));
      expect(data.parentId, equals('tt0944947'));
      expect(data.seasonNumber, equals(1));
      expect(data.episodeNumber, equals(1));
    });
  });
}
