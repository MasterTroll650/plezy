import 'dart:convert';

import '../../media/media_kind.dart';
import '../../models/catalog/catalog_item.dart';
import '../../utils/trailer_urls.dart';
import 'trailer_lookup.dart';

/// Looks up trailers by catalog ID and spoken language in KinoCheck.
class KinoCheckTrailers {
  static bool canLookUp(CatalogItem item) =>
      (item.kind == MediaKind.movie || item.kind == MediaKind.show) &&
      (item.ids.tmdb != null || item.ids.imdb?.isNotEmpty == true);

  static Future<Uri?> findTrailer(CatalogItem item, {required String language}) async {
    if (!canLookUp(item)) return null;
    final tmdb = item.ids.tmdb;
    final url = Uri.https('api.kinocheck.com', item.kind == MediaKind.movie ? '/movies' : '/shows', {
      if (tmdb != null) 'tmdb_id': '$tmdb' else 'imdb_id': item.ids.imdb!,
      'language': language,
      'categories': 'Trailer',
    });
    return requestTrailer<Uri>(
      url,
      source: 'KinoCheck',
      timeout: const Duration(seconds: 3),
      parse: (body) => _parseResponse(body, language),
    );
  }

  static Uri? _parseResponse(String body, String language) {
    final data = jsonDecode(body);
    if (data is! Map<String, dynamic>) throw const FormatException('Invalid KinoCheck trailer response');
    final trailer = _trailerUrl(data['trailer'], language);
    if (trailer != null) return trailer;
    final videos = data['videos'];
    if (videos is List) {
      for (final video in videos) {
        final url = _trailerUrl(video, language);
        if (url != null) return url;
      }
    }
    return null;
  }

  static Uri? _trailerUrl(Object? video, String language) {
    if (video is! Map<String, dynamic> || video['language'] != language) return null;
    final categories = video['categories'];
    final id = video['youtube_video_id'];
    if (categories is! List || !categories.contains('Trailer') || id is! String) return null;
    final url = youTubeTrailerUrl(id);
    if (youTubeVideoId(url) != id) return null;
    return Uri.parse(url!);
  }
}
