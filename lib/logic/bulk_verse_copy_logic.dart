import 'package:wolof_bible/logic/bible_abbreviations.dart';

class VerseRange {
  final String book; // Paratext 3-letter code
  final int chapter;
  final int? startVerse;
  final int? endingChapter;
  final int? endingVerse;

  VerseRange(
    this.book,
    this.chapter, {
    this.startVerse,
    this.endingChapter,
    this.endingVerse,
  });

  @override
  String toString() {
    return 'VerseReference(book: $book, chapter: $chapter, '
        'startVerse: $startVerse, endingChapter: $endingChapter, '
        'endingVerse: $endingVerse)';
  }
}

class RangesAndErrors {
  final List<VerseRange> ranges;
  final List<String> errors;
  RangesAndErrors(this.ranges, this.errors);
}

final referenceRegex = RegExp(
  r'^(?!.*,)(.+?)\s+(\d+?)(?:[.:]\s*(\d+(?:-\d+)*)(?:[-–](\d+)(?:[.:](\d+))?)?)?$',
  caseSensitive: false,
);

RangesAndErrors parseReferences(List<String> refs) {
  final List<VerseRange> results = [];
  final List<String> errors = [];

  for (var ref in refs) {
    final match = referenceRegex.firstMatch(ref.trim());
    if (match != null) {
      final rawBook = match.group(1)!.trim();
      final chapter = int.parse(match.group(2)!);
      final versesPart = match.group(3);

      // Normalize book name
      final String? bookCode = BibleAbbreviations.lookup(rawBook);
      if (bookCode == null) {
        errors.add(ref);
        continue;
      }

      if (versesPart == null) {
        // Whole chapter reference
        results.add(VerseRange(bookCode, chapter));
      } else {
        // Split on commas/semicolons
        final parts = versesPart.split(RegExp(r'[;,]')).map((s) => s.trim());
        for (var part in parts) {
          if (part.contains('-')) {
            final range =
                part.split('-').map((s) => int.parse(s.trim())).toList();
            results.add(
              VerseRange(
                bookCode,
                chapter,
                startVerse: range[0],
                endingVerse: range[1],
              ),
            );
          } else {
            final verse = int.parse(part);
            results.add(
              VerseRange(
                bookCode,
                chapter,
                startVerse: verse,
              ),
            );
          }
        }
      }
    } else {
      errors.add(ref);
    }
  }

  return RangesAndErrors(results, errors);
}


