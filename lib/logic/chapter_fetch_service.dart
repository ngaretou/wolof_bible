import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'data_initializer.dart';

/// A wrapper for the data returned by the fetch service.
/// Contains the list of parsed lines and flags to indicate if the data
/// represents the beginning or end of the entire Bible content.
class FetchResult {
  final List<ParsedLine> lines;
  final bool isAtBeginning;
  final bool isAtEnd;

  FetchResult({
    required this.lines,
    this.isAtBeginning = false,
    this.isAtEnd = false,
  });
}

/// A service to fetch and parse chapter data from the pre-processed JSON files.
class ChapterFetchService {
  // A cache to hold the table of contents for each collection to avoid re-reading files.
  final Map<String, Map<String, dynamic>> _tocCache = {};

  /// Fetches an initial chunk of data centered around a specific chapter.
  Future<FetchResult> getInitialChunk({
    required String collectionId,
    required String bookId,
    required int chapter,
  }) async {
    final toc = await _getCollectionToc(collectionId);
    if (toc.isEmpty) return FetchResult(lines: []);

    final bookIds = toc.keys.toList();
    final List<ParsedLine> allLines = [];

    // Determine previous, current, and next chapters
    final currentChapterInfo = _ChapterInfo(bookId, chapter);
    final prevChapterInfo = _getPreviousChapterInfo(toc, bookIds, currentChapterInfo);
    final nextChapterInfo = _getNextChapterInfo(toc, bookIds, currentChapterInfo);

    // Fetch previous chapter if it exists
    if (prevChapterInfo != null) {
      allLines.addAll(await _fetchAndParseChapter(
          collectionId, prevChapterInfo.bookId, prevChapterInfo.chapter));
    }

    // Fetch current chapter
    allLines.addAll(
        await _fetchAndParseChapter(collectionId, bookId, chapter));

    // Fetch next chapter if it exists
    if (nextChapterInfo != null) {
      allLines.addAll(await _fetchAndParseChapter(
          collectionId, nextChapterInfo.bookId, nextChapterInfo.chapter));
    }

    return FetchResult(
      lines: allLines,
      isAtBeginning: prevChapterInfo == null,
      isAtEnd: nextChapterInfo == null,
    );
  }

  /// Fetches the next chunk of data when the user scrolls forward.
  Future<FetchResult> getNextChunk({
    required String collectionId,
    required String bookId,
    required int lastChapter,
  }) async {
    final toc = await _getCollectionToc(collectionId);
    if (toc.isEmpty) return FetchResult(lines: []);

    final bookIds = toc.keys.toList();
    final currentChapterInfo = _ChapterInfo(bookId, lastChapter);
    final nextChapterInfo = _getNextChapterInfo(toc, bookIds, currentChapterInfo);

    if (nextChapterInfo == null) {
      return FetchResult(lines: [], isAtEnd: true);
    }

    final lines = await _fetchAndParseChapter(
        collectionId, nextChapterInfo.bookId, nextChapterInfo.chapter);

    // Check if the new chunk is the very last chapter
    final isAtEnd = _getNextChapterInfo(toc, bookIds, nextChapterInfo) == null;

    return FetchResult(lines: lines, isAtEnd: isAtEnd);
  }

  /// Fetches the previous chunk of data when the user scrolls backward.
  Future<FetchResult> getPreviousChunk({
    required String collectionId,
    required String bookId,
    required int firstChapter,
  }) async {
    final toc = await _getCollectionToc(collectionId);
    if (toc.isEmpty) return FetchResult(lines: []);

    final bookIds = toc.keys.toList();
    final currentChapterInfo = _ChapterInfo(bookId, firstChapter);
    final prevChapterInfo = _getPreviousChapterInfo(toc, bookIds, currentChapterInfo);

    if (prevChapterInfo == null) {
      return FetchResult(lines: [], isAtBeginning: true);
    }

    final lines = await _fetchAndParseChapter(
        collectionId, prevChapterInfo.bookId, prevChapterInfo.chapter);
        
    // Check if the new chunk is the very first chapter
    final isAtBeginning = _getPreviousChapterInfo(toc, bookIds, prevChapterInfo) == null;

    return FetchResult(lines: lines, isAtBeginning: isAtBeginning);
  }

  // --- Private Helper Methods ---

  _ChapterInfo? _getPreviousChapterInfo(
      Map<String, dynamic> toc, List<String> bookIds, _ChapterInfo current) {
    if (current.chapter > 1) {
      return _ChapterInfo(current.bookId, current.chapter - 1);
    }

    final currentBookIndex = bookIds.indexOf(current.bookId);
    if (currentBookIndex > 0) {
      final prevBookId = bookIds[currentBookIndex - 1];
      final prevBookChapters = toc[prevBookId]['chapters'] as Map<String, dynamic>;
      final lastChapterOfPrevBook = prevBookChapters.keys.length;
      return _ChapterInfo(prevBookId, lastChapterOfPrevBook);
    }

    return null; // At the beginning of the collection
  }

  _ChapterInfo? _getNextChapterInfo(
      Map<String, dynamic> toc, List<String> bookIds, _ChapterInfo current) {
    final currentBookChapters = toc[current.bookId]['chapters'] as Map<String, dynamic>;
    final lastChapterOfCurrentBook = currentBookChapters.keys.length;

    if (current.chapter < lastChapterOfCurrentBook) {
      return _ChapterInfo(current.bookId, current.chapter + 1);
    }

    final currentBookIndex = bookIds.indexOf(current.bookId);
    if (currentBookIndex < bookIds.length - 1) {
      final nextBookId = bookIds[currentBookIndex + 1];
      return _ChapterInfo(nextBookId, 1);
    }

    return null; // At the end of the collection
  }

  /// Helper function to load and cache the Table of Contents for a collection.
  Future<Map<String, dynamic>> _getCollectionToc(String collectionId) async {
    if (_tocCache.containsKey(collectionId)) {
      return _tocCache[collectionId]!;
    }
    try {
      final path = 'assets/json/${collectionId}_toc.json';
      final jsonString = await rootBundle.loadString(path);
      final Map<String, dynamic> toc = json.decode(jsonString);
      _tocCache[collectionId] = toc;
      return toc;
    } catch (e) {
      print('Error loading TOC for $collectionId: $e');
      return {};
    }
  }

  /// Helper function to fetch a single chapter's JSON and parse it into ParsedLine objects.
  Future<List<ParsedLine>> _fetchAndParseChapter(
      String collectionId, String bookId, int chapter) async {
    final path = 'assets/json/$collectionId/$bookId/$chapter.json';
    
    try {
      final jsonString = await rootBundle.loadString(path);
      final List<dynamic> jsonData = json.decode(jsonString);

      // Map the JSON objects to ParsedLine objects
      return jsonData.map((lineJson) {
        return ParsedLine(
          collectionid: collectionId,
          book: bookId,
          chapter: chapter.toString(),
          verse: lineJson['verse']?.toString() ?? '',
          verseFragment: '', // Not in our current JSON structure
          audioMarker: '', // Not in our current JSON structure
          verseText: lineJson['text'] ?? '',
          verseStyle: lineJson['style'] ?? '',
        );
      }).toList();
    } catch (e) {
      print('Error fetching or parsing chapter $collectionId/$bookId/$chapter: $e');
      return [];
    }
  }
}

/// A private helper class to hold book and chapter information.
class _ChapterInfo {
  final String bookId;
  final int chapter;

  _ChapterInfo(this.bookId, this.chapter);
}