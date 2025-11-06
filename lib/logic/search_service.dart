import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:wolof_bible/logic/bulk_verse_copy_logic.dart';
import 'package:wolof_bible/logic/data_initializer.dart';
import 'package:wolof_bible/logic/text_utils.dart';
import 'package:wolof_bible/logic/verse_composer.dart';
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

class HydratedVerseResult {
  final String composedText;
  final String reference;

  const HydratedVerseResult({
    required this.composedText,
    required this.reference,
  });
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

  Stream<SearchResult> search({
    required List<String> collectionIds,
    required String query,
    required Map<String, String> collectionLanguages,
  }) async* {
    if (query.trim().isEmpty) return;

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
          final locationsForTerm =
              (indexShard[term] as List<dynamic>).map((loc) {
            return _VerseLocation(
                collectionId, loc[0], loc[1], loc[2].toString());
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
      return;
    }

    yield* _hydrateResults(finalLocations.toList());
  }

  ///
  Future<List<HydratedVerseResult>> getVerseRanges({
    required String collectionId,
    required List<VerseRange> verseRanges,
    required List<Collection> collections,
    bool includeVerseNumbers = false,
  }) async {
    final Collection currentCollection =
        collections.firstWhere((c) => c.id == collectionId);

    final futures = verseRanges
        .map((vRange) => _hydrateVerseRange(
            vRange, collectionId, currentCollection, includeVerseNumbers))
        .toList();

    final results = await Future.wait(futures);

    return results.whereType<HydratedVerseResult>().toList();
  }

  Future<HydratedVerseResult?> _hydrateVerseRange(
      VerseRange vRange,
      String collectionId,
      Collection collection,
      bool includeVerseNumbers) async {
    final List<ParsedLine> verseLines = [];

    final int startChapter = vRange.chapter;
    final int endChapter = vRange.endingChapter ?? vRange.chapter;

    for (int ch = startChapter; ch <= endChapter; ch++) {
      final chapterPath = 'assets/json/$collectionId/${vRange.book}/$ch.json';
      try {
        final List<dynamic> chapterData = await _getChapterData(chapterPath);
        final parsedLines = chapterData.map((item) {
          return ParsedLine(
            collectionid: collectionId,
            book: vRange.book,
            chapter: ch.toString(),
            verse: item['verse']?.toString() ?? '',
            verseFragment: item['vfrag']?.toString() ?? '',
            audioMarker: item['audio']?.toString() ?? '',
            verseText: item['text']?.toString() ?? '',
            verseStyle: item['style']?.toString() ?? '',
          );
        }).toList();
        verseLines.addAll(parsedLines);
      } catch (e) {
        print('Could not load chapter $chapterPath: $e');
      }
    }

    if (verseLines.isEmpty) return null;

    // Filter verses based on range
    List<ParsedLine> selectedLines;
    if (vRange.startVerse == null) {
      // whole chapter(s)
      selectedLines = verseLines;
    } else {
      final int startVerse = vRange.startVerse!;
      final endVerse = vRange.endingVerse ?? startVerse;

      selectedLines = verseLines.where((line) {
        final verseStr = line.verse; // verse number as string
        if (verseStr.isEmpty) return false;

        // in case we're dealing with a verse number that looks like "15-17"
        final firstVerseInLine = int.parse(_getFirstOfDashedVerses(verseStr));
        final lastVerseInLine = int.parse(_getLastOfDashedVerses(verseStr));

        final lineChapter = int.parse(line.chapter);

        if (startChapter == endChapter) {
          return firstVerseInLine <= endVerse && lastVerseInLine >= startVerse;
        } else {
          // Multi-chapter range
          if (lineChapter == startChapter) {
            return lastVerseInLine >= startVerse;
          } else if (lineChapter == endChapter) {
            return firstVerseInLine <= endVerse;
          } else if (lineChapter > startChapter && lineChapter < endChapter) {
            return true;
          }
        }

        return false;
      }).toList();
    }

    // Ensure that if the selection ends mid-verse, the entire verse is included.
    // if (selectedLines.isNotEmpty) {
    //   final lastLineInSelection = selectedLines.last;
    //   final originalIndexInVerseLines = verseLines.indexOf(lastLineInSelection);

    //   if (originalIndexInVerseLines != -1) {
    //     for (int i = originalIndexInVerseLines + 1;
    //         i < verseLines.length;
    //         i++) {
    //       final currentLine = verseLines[i];
    //       // Check if the current line belongs to the same verse as the last line in selection
    //       if (currentLine.book == lastLineInSelection.book &&
    //           currentLine.chapter == lastLineInSelection.chapter &&
    //           currentLine.verse == lastLineInSelection.verse) {
    //         selectedLines.add(currentLine);
    //       } else {
    //         // We've reached a different verse/chapter/book, so stop.
    //         break;
    //       }
    //     }
    //   }
    // }

    // Now compose text
    final StringBuffer buffer = StringBuffer();
    for (final line in selectedLines) {
      if (isHeader(line.verseStyle)) continue;

      if (isParagraph(line.verseStyle)) {
        buffer.write('\n    ');
      }
      String composedText = verseComposer(
        line: line,
        includeFootnotes: false,
      ).versesAsString.trim();

      if (includeVerseNumbers &&
          line.verse.isNotEmpty &&
          line.verse != '0' &&
          line.verseStyle == 'v') {
        buffer.write('${toSuperscript(line.verse)}\u202f');
      }

      buffer.write('$composedText ');
    }

    // Format reference
    final String bookName =
        collection.books.firstWhere((b) => b.id == vRange.book).name;
    String reference;
    if (vRange.startVerse == null) {
      reference = '$bookName ${vRange.chapter}';
    } else if (vRange.endingVerse == null) {
      reference = '$bookName ${vRange.chapter}:${vRange.startVerse}';
    } else if (vRange.endingChapter == null ||
        vRange.endingChapter == vRange.chapter) {
      reference =
          '$bookName ${vRange.chapter}:${vRange.startVerse}-${vRange.endingVerse}';
    } else {
      reference =
          '$bookName ${vRange.chapter}:${vRange.startVerse}-${vRange.endingChapter}:${vRange.endingVerse}';
    }
    // reference += ' (${collection.name})';

    return HydratedVerseResult(
        composedText: buffer.toString().trim(), reference: reference);
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

  Future<List<dynamic>> _getChapterData(String chapterPath) async {
    if (_chapterCache.containsKey(chapterPath)) {
      return _chapterCache[chapterPath]!;
    }
    try {
      final jsonString = await rootBundle.loadString(chapterPath);
      final chapterData = json.decode(jsonString) as List<dynamic>;
      _chapterCache[chapterPath] = chapterData;
      return chapterData;
    } catch (e) {
      return [];
    }
  }

  Stream<SearchResult> _hydrateResults(List<_VerseLocation> locations) async* {
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
        final List<dynamic> chapterData = await _getChapterData(chapterPath);
        if (chapterData.isEmpty) continue;

        final versesInChapter = entry.value;
        for (final loc in versesInChapter) {
          // Find all lines for the specific verse to handle multi-line verses
          final verseLines = chapterData
              .where((line) => line['verse']?.toString() == loc.verse)
              .toList();

          if (verseLines.isNotEmpty) {
            // Assemble the full text from all parts of the verse, ignoring empty lines (like paragraph markers)
            final composedText = verseLines
                .map((line) => line['text']?.toString() ?? '')
                .where((text) => text.isNotEmpty)
                .join(' '); // Join with a space for a clean, readable preview

            if (composedText.isNotEmpty) {
              yield SearchResult(
                text: composedText,
                collection: loc.collectionId,
                book: loc.bookId,
                chapter: loc.chapter.toString(),
                verse: loc.verse,
              );
            }
          }
        }
      } catch (e) {
        print('Error hydrating results for $chapterPath: $e');
      }
    }
  }
}

String _getFirstOfDashedVerses(String vs) {
  RegExpMatch? match = RegExp(r'^(\d+)').firstMatch(vs);
  return match?.group(1) ?? vs;
}

String _getLastOfDashedVerses(String vs) {
  RegExpMatch? match = RegExp(r'(\d+)$').firstMatch(vs);
  return match?.group(1) ?? vs;
}
