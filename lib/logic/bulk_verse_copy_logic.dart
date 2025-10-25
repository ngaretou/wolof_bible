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

final referenceRegex = RegExp(
  r'^(.+?)\s+(\d+)(?:[.:]\s*(\d+(?:[-,;]\d+)*)(?:[-–](\d+)(?:[.:](\d+))?)?)?$',
  caseSensitive: false,
);

List<VerseRange> parseReferences(List<String> refs) {
  final List<VerseRange> results = [];

  for (var ref in refs) {
    final match = referenceRegex.firstMatch(ref.trim());
    if (match != null) {
      final rawBook = match.group(1)!.trim();
      final chapter = int.parse(match.group(2)!);
      final versesPart = match.group(3);

      // Normalize book name
      final bookCode = bookAliases[rawBook] ?? rawBook.toUpperCase();

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
    }
  }

  return results;
}

// void main() {
//   final refs = [
//     'GEN 1.1',
//     'GEN 1:1',
//     'Genesis 1.1',
//     'Genesis 1:1',
//     'Genèse 1.1',
//     'Actes 22. 3',
//     'Colossiens 1. 26',
//     '2 Timothée 3. 16',
//     '2 Pierre 1. 21',
//     '1 Pierre 4. 14',
//     '1 Pierre 4. 19',
//     'Actes 7. 60',
//     'Galates 1. 11',
//     'Hébreux 12. 6-10',
//     'Psaume 89. 9,10',
//     'Jean 3. 16;17',
//   ];

//   final parsed = parseReferences(refs);
//   for (var r in parsed) {
//     print(r);
//   }
// }

const Map<String, String> bookAliases = {
  // Pentateuch
  'Genèse': 'GEN', 'Genesis': 'GEN', 'GEN': 'GEN',
  'Exode': 'EXO', 'Exodus': 'EXO', 'EXO': 'EXO',
  'Lévitique': 'LEV', 'Leviticus': 'LEV', 'LEV': 'LEV',
  'Nombres': 'NUM', 'Numbers': 'NUM', 'NUM': 'NUM',
  'Deutéronome': 'DEU', 'Deuteronomy': 'DEU', 'DEU': 'DEU',

  // Historical
  'Josué': 'JOS', 'Joshua': 'JOS', 'JOS': 'JOS',
  'Juges': 'JDG', 'Judges': 'JDG', 'JDG': 'JDG',
  'Ruth': 'RUT', 'RUT': 'RUT',
  '1 Samuel': '1SA', '1SA': '1SA',
  '2 Samuel': '2SA', '2SA': '2SA',
  '1 Rois': '1KI', '1 Kings': '1KI', '1KI': '1KI',
  '2 Rois': '2KI', '2 Kings': '2KI', '2KI': '2KI',
  '1 Chroniques': '1CH', '1 Chronicles': '1CH', '1CH': '1CH',
  '2 Chroniques': '2CH', '2 Chronicles': '2CH', '2CH': '2CH',
  'Esdras': 'EZR', 'Ezra': 'EZR', 'EZR': 'EZR',
  'Néhémie': 'NEH', 'Nehemiah': 'NEH', 'NEH': 'NEH',
  'Esther': 'EST', 'EST': 'EST',

  // Wisdom
  'Job': 'JOB', 'JOB': 'JOB',
  'Psaume': 'PSA', 'Psaumes': 'PSA', 'Psalms': 'PSA', 'Psalm': 'PSA',
  'PSA': 'PSA',
  'Proverbes': 'PRO', 'Proverbs': 'PRO', 'PRO': 'PRO',
  'Ecclésiaste': 'ECC', 'Ecclesiastes': 'ECC', 'ECC': 'ECC',
  'Cantique': 'SNG', 'Cantique des cantiques': 'SNG', 'Song of Songs': 'SNG',
  'Song of Solomon': 'SNG', 'SNG': 'SNG',

  // Major Prophets
  'Ésaïe': 'ISA', 'Isaiah': 'ISA', 'ISA': 'ISA',
  'Jérémie': 'JER', 'Jeremiah': 'JER', 'JER': 'JER',
  'Lamentations': 'LAM', 'LAM': 'LAM',
  'Ézéchiel': 'EZK', 'Ezekiel': 'EZK', 'EZK': 'EZK',
  'Daniel': 'DAN', 'DAN': 'DAN',

  // Minor Prophets
  'Osée': 'HOS', 'Hosea': 'HOS', 'HOS': 'HOS',
  'Joël': 'JOL', 'Joel': 'JOL', 'JOL': 'JOL',
  'Amos': 'AMO', 'AMO': 'AMO',
  'Abdias': 'OBA', 'Obadiah': 'OBA', 'OBA': 'OBA',
  'Jonas': 'JON', 'Jonah': 'JON', 'JON': 'JON',
  'Michée': 'MIC', 'Micah': 'MIC', 'MIC': 'MIC',
  'Nahum': 'NAM', 'NAM': 'NAM',
  'Habacuc': 'HAB', 'Habakkuk': 'HAB', 'HAB': 'HAB',
  'Sophonie': 'ZEP', 'Zephaniah': 'ZEP', 'ZEP': 'ZEP',
  'Aggée': 'HAG', 'Haggai': 'HAG', 'HAG': 'HAG',
  'Zacharie': 'ZEC', 'Zechariah': 'ZEC', 'ZEC': 'ZEC',
  'Malachie': 'MAL', 'Malachi': 'MAL', 'MAL': 'MAL',

  // NT
  'Matthieu': 'MAT', 'Matthew': 'MAT', 'MAT': 'MAT',
  'Marc': 'MRK', 'Mark': 'MRK', 'MRK': 'MRK',
  'Luc': 'LUK', 'Luke': 'LUK', 'LUK': 'LUK',
  'Jean': 'JHN', 'John': 'JHN', 'JHN': 'JHN',
  'Actes': 'ACT', 'Acts': 'ACT', 'ACT': 'ACT',
  'Romains': 'ROM', 'Romans': 'ROM', 'ROM': 'ROM',
  '1 Corinthiens': '1CO', '1 Corinthians': '1CO', '1CO': '1CO',
  '2 Corinthiens': '2CO', '2 Corinthians': '2CO', '2CO': '2CO',
  'Galates': 'GAL', 'Galatians': 'GAL', 'GAL': 'GAL',
  'Éphésiens': 'EPH', 'Ephesians': 'EPH', 'EPH': 'EPH',
  'Philippiens': 'PHP', 'Philippians': 'PHP', 'PHP': 'PHP',
  'Colossiens': 'COL', 'Colossians': 'COL', 'COL': 'COL',
  '1 Thessaloniciens': '1TH', '1 Thessalonians': '1TH', '1TH': '1TH',
  '2 Thessaloniciens': '2TH', '2 Thessalonians': '2TH', '2TH': '2TH',
  '1 Timothée': '1TI', '1 Timothy': '1TI', '1TI': '1TI',
  '2 Timothée': '2TI', '2 Timothy': '2TI', '2TI': '2TI',
  'Tite': 'TIT', 'Titus': 'TIT', 'TIT': 'TIT',
  'Philémon': 'PHM', 'Philemon': 'PHM', 'PHM': 'PHM',
  'Hébreux': 'HEB', 'Hebrews': 'HEB', 'HEB': 'HEB',
  'Jacques': 'JAS', 'James': 'JAS', 'JAS': 'JAS',
  '1 Pierre': '1PE', '1 Peter': '1PE', '1PE': '1PE',
  '2 Pierre': '2PE', '2 Peter': '2PE', '2PE': '2PE',
  '1 Jean': '1JN', '1 John': '1JN', '1JN': '1JN',
  '2 Jean': '2JN', '2 John': '2JN', '2JN': '2JN',
  '3 Jean': '3JN', '3 John': '3JN', '3JN': '3JN',
  'Jude': 'JUD', 'JUD': 'JUD',
  'Apocalypse': 'REV', 'Revelation': 'REV', 'REV': 'REV',
};
