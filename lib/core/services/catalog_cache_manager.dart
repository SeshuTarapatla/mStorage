import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Long-lived cache for catalog images (thumbnails, posters).
/// Movie posters are static — 30-day TTL avoids redundant re-downloads.
class CatalogCacheManager extends CacheManager with ImageCacheManager {
  static const _key = 'catalogImages';
  static final instance = CatalogCacheManager._();
  CatalogCacheManager._()
      : super(Config(
          _key,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 300,
        ));
}
