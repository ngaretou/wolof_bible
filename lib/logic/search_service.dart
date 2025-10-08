import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'text_processor.dart';

class SearchResult {
  final String text;
  final String collection;
  final String book;
  final String chapter;
  final String verse;

  const SearchResult(
      {required this.text,
      required this.collection,
      required this.book,
      required this.chapter,
      required this.verse});
}

class _VerseLocation {
  final String collectionId;
  final String bookId;
  final int chapter;
  final String verse;

  _VerseLocation(this.collectionId, this.bookId, this.chapter, this.verse);

  // Override equals and hashCode to allow for using this class in a Set
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _VerseLocation &&
          runtimeType == other.runtimeType &&
          collectionId == other.collectionId &&
          bookId == other.bookId &&
          chapter == other.chapter &&
          verse == other.verse;

  @override
  int get hashCode =>
      collectionId.hashCode ^
      bookId.hashCode ^
      chapter.hashCode ^
      verse.hashCode;
}

class SearchService {
  final Map<String, Map<String, dynamic>> _indexShardCache = {};
  final Map<String, List<dynamic>> _chapterCache = {};

  Future<List<SearchResult>> search({
    required List<String> collectionIds,
    required String query,
    required Map<String, String> collectionLanguages,
  }) async {
    if (query.trim().isEmpty) return [];

    Set<_VerseLocation>? finalLocations;

    // Process the query for each collection's language
    for (String collectionId in collectionIds) {
      final lang = collectionLanguages[collectionId] ?? 'en'; // Fallback
      final textProcessor = TextProcessor(lang);
      final processedQuery = textProcessor.process(query); // cleans the query

      if (processedQuery.isEmpty) continue;

      Set<_VerseLocation>? collectionResults;

      for (final term in processedQuery) {
        final firstLetter = term[0];
        final indexShard = await _getIndexShard(collectionId, firstLetter);
        
        if (indexShard.containsKey(term)) {
          final locationsForTerm = (indexShard[term] as List<dynamic>).map((loc) {
            return _VerseLocation(collectionId, loc[0], loc[1], loc[2].toString());
          }).toSet();

          if (collectionResults == null) {
            collectionResults = locationsForTerm;
          } else {
            // Intersect results for an "AND" search
            collectionResults.retainAll(locationsForTerm);
          }
        } else {
          // If any term is not found, this collection has no results for the full query
          collectionResults = {};
          break;
        }
      }

      if (collectionResults != null && collectionResults.isNotEmpty) {
        if (finalLocations == null) {
          finalLocations = collectionResults;
        } else {
          finalLocations.addAll(collectionResults);
        }
      }
    }

    if (finalLocations == null || finalLocations.isEmpty) {
      return [];
    }

    return _hydrateResults(finalLocations.toList());
  }

  Future<Map<String, dynamic>> _getIndexShard(
      String collectionId, String firstLetter) async {
    final path = 'assets/json/$collectionId/index/$firstLetter.json';
    if (_indexShardCache.containsKey(path)) {
      return _indexShardCache[path]!;
    }
    try {
      final jsonString = await rootBundle.loadString(path);
      final indexData = json.decode(jsonString) as Map<String, dynamic>;
      _indexShardCache[path] = indexData;
      return indexData;
    } catch (e) {
      // It's normal for some index files not to exist (e.g., x.json)
      return {};
    }
  }

  Future<List<SearchResult>> _hydrateResults(
      List<_VerseLocation> locations) async {
    final results = <SearchResult>[];
    final Map<String, List<_VerseLocation>> groupedByChapter = {};

    // Group locations by chapter to fetch each chapter file only once
    for (final loc in locations) {
      final key = '${loc.collectionId}/${loc.bookId}/${loc.chapter}';
      groupedByChapter.putIfAbsent(key, () => []).add(loc);
    }

    for (final entry in groupedByChapter.entries) {
      final parts = entry.key.split('/');
      final collectionId = parts[0];
      final bookId = parts[1];
      final chapter = parts[2];
      final chapterPath = 'assets/json/$collectionId/$bookId/$chapter.json';

      try {
        List<dynamic> chapterData;
        if (_chapterCache.containsKey(chapterPath)) {
          chapterData = _chapterCache[chapterPath]!;
        } else {
          final jsonString = await rootBundle.loadString(chapterPath);
          chapterData = json.decode(jsonString) as List<dynamic>;
          _chapterCache[chapterPath] = chapterData;
        }

        final versesInChapter = entry.value;
        for (final loc in versesInChapter) {
          // Find the specific verse line within the chapter data
          final verseLine = chapterData.firstWhere(
            (line) => line['verse']?.toString() == loc.verse,
            orElse: () => null,
          );

          if (verseLine != null) {
            results.add(SearchResult(
              text: verseLine['text'] ?? '',
              collection: loc.collectionId,
              book: loc.bookId,
              chapter: loc.chapter.toString(),
              verse: loc.verse,
            ));
          }
        }
      } catch (e) {
        print('Error hydrating results for $chapterPath: $e');
      }
    }
    return results;
  }
}
