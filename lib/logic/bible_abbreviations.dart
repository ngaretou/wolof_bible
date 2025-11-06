import 'text_utils.dart';

/// BibleAbbreviations helper
/// - Maintains canonical → variants
/// - Builds fast lookup map
/// - Normalizes input for robust matching
/// Source of truth: Paratext 3‑letter code → list of variants
class BibleAbbreviations {
  /// Canonical Paratext 3‑letter code → list of known variants
  static final Map<String, List<String>> _variants = {
    // Old Testament
    "GEN": ["Gen", "Gen.", "Gn", "Ge", "Genese", "Genesis", "GEN"],
    "EXO": ["Ex", "Exod", "Exo", "Ex.", "Exode", "Exodus", "EXO"],
    "LEV": ["Lev", "Le", "Lv", "Levitique", "Leviticus", "LEV"],
    "NUM": ["Num", "Nu", "Nm", "Nb", "Nombres", "Numbers", "NUM"],
    "DEU": ["Deut", "De", "Dt", "Deuteronome", "Deuteronomy", "DEU"],
    "JOS": ["Josh", "Jos", "Jsh", "Josue", "Joshua", "JOS"],
    "JDG": ["Judg", "Jdg", "Jg", "Jdgs", "Juges", "Judges", "JDG"],
    "RUT": ["Ruth", "Rth", "Ru", "RUT"],
    "1SA": [
      "1 Sam.",
      "1 Sm",
      "1 Sa",
      "1 S",
      "I Sam.",
      "I Sa",
      "1Sam",
      "1Sa",
      "1S",
      "1st Samuel",
      "First Samuel",
      "1 Samuel",
      "1SA"
    ],
    "2SA": [
      "2 Sam.",
      "2 Sm",
      "2 Sa",
      "2 S",
      "II Sam.",
      "II Sa",
      "2Sam",
      "2Sa",
      "2S",
      "2nd Samuel",
      "Second Samuel",
      "2 Samuel",
      "2SA"
    ],
    "1KI": [
      "1 Kings",
      "1 Kgs",
      "1 Ki",
      "1Kgs",
      "1Kin",
      "1Ki",
      "I Kgs",
      "I Ki",
      "1st Kings",
      "First Kings",
      "1 Rois",
      "1KI"
    ],
    "2KI": [
      "2 Kings",
      "2 Kgs",
      "2 Ki",
      "2Kgs",
      "2Kin",
      "2Ki",
      "II Kgs",
      "II Ki",
      "2nd Kings",
      "Second Kings",
      "2 Rois",
      "2KI"
    ],
    "1CH": [
      "1 Chron.",
      "1 Chr.",
      "1 Ch.",
      "1Chron.",
      "1Chr.",
      "1Ch.",
      "I Chron.",
      "I Chr.",
      "I Ch.",
      "1st Chronicles",
      "First Chronicles",
      "1 Chroniques",
      "1 Chronicles",
      "1CH"
    ],
    "2CH": [
      "2 Chron.",
      "2 Chr.",
      "2 Ch.",
      "2Chron.",
      "2Chr.",
      "2Ch.",
      "II Chron.",
      "II Chr.",
      "II Ch.",
      "2nd Chronicles",
      "Second Chronicles",
      "2 Chroniques",
      "2 Chronicles",
      "2CH"
    ],
    "EZR": ["Ezra", "Ezr.", "Ez.", "Esdras", "EZR"],
    "NEH": ["Neh.", "Ne.", "Nehemie", "Nehemiah", "NEH"],
    "EST": ["Est.", "Esth.", "Es.", "Esther", "EST"],
    "JOB": ["Job", "Jb.", "JOB"],
    "PSA": [
      "Ps.",
      "Psalm",
      "Pslm.",
      "Psa.",
      "Psm.",
      "Pss.",
      "Psaume",
      "Psaumes",
      "Psalms",
      "PSA"
    ],
    "PRO": ["Prov", "Pro.", "Prv.", "Pr.", "Proverbes", "Proverbs", "PRO"],
    "ECC": [
      "Eccles.",
      "Eccle.",
      "Ecc.",
      "Ec.",
      "Qoh.",
      "Ecclesiaste",
      "Ecclesiastes",
      "ECC"
    ],
    "SNG": [
      "Song",
      "Song of Songs",
      "SOS.",
      "So.",
      "Canticles",
      "Cant.",
      "Cantique",
      "Cantique des cantiques",
      "Song of Solomon",
      "SNG"
    ],
    "ISA": ["Isa.", "Is.", "Esaie", "Isaiah", "ISA"],
    "JER": ["Jer.", "Je.", "Jr.", "Jeremie", "Jeremiah", "JER"],
    "LAM": ["Lam.", "La.", "Lamentations", "LAM", "Lamentation de Jérémie"],
    "EZK": ["Ezek.", "Eze.", "Ezk.", "Ezechiel", "Ezekiel", "EZK"],
    "DAN": ["Dan.", "Da.", "Dn.", "Daniel", "DAN"],
    "HOS": ["Hos.", "Ho.", "Osee", "Hosea", "HOS"],
    "JOL": ["Joel", "Jl.", "JOL"],
    "AMO": ["Amos", "Am.", "AMO"],
    "OBA": ["Obad.", "Ob.", "Abdias", "Obadiah", "OBA"],
    "JON": ["Jonah", "Jnh.", "Jon.", "Jonas", "JON"],
    "MIC": ["Mic.", "Mc.", "Michee", "Micah", "MIC"],
    "NAM": ["Nah.", "Na.", "Nahum", "NAM"],
    "HAB": ["Hab.", "Hb.", "Habacuc", "Habakkuk", "HAB"],
    "ZEP": ["Zeph.", "Zep.", "Zp.", "Sophonie", "Zephaniah", "ZEP"],
    "HAG": ["Hag.", "Hg.", "Aggee", "Haggai", "HAG"],
    "ZEC": ["Zech.", "Zec.", "Zc.", "Zacharie", "Zechariah", "ZEC"],
    "MAL": ["Mal.", "Ml.", "Malachie", "Malachi", "MAL"],

    // New Testament
    "MAT": ["Matt.", "Mt.", "Matthieu", "Matthew", "MAT"],
    "MRK": ["Mark", "Mrk", "Mar", "Mk", "Mr", "Marc", "MRK"],
    "LUK": ["Luke", "Luk", "Lk", "Luc", "LUK"],
    "JHN": ["John", "Joh", "Jhn", "Jn", "Jean", "JHN"],
    "ACT": ["Acts", "Act", "Ac", "Actes", "ACT"],
    "ROM": ["Rom.", "Ro.", "Rm.", "Romains", "Romans", "ROM"],
    "1CO": [
      "1 Cor.",
      "1 Co.",
      "I Cor.",
      "I Co.",
      "1Cor.",
      "1Co.",
      "1st Corinthians",
      "First Corinthians",
      "1 Corinthiens",
      "1 Corinthians",
      "1CO"
    ],
    "2CO": [
      "2 Cor.",
      "2 Co.",
      "II Cor.",
      "II Co.",
      "2Cor.",
      "2Co.",
      "2nd Corinthians",
      "Second Corinthians",
      "2 Corinthiens",
      "2 Corinthians",
      "2CO"
    ],
    "GAL": ["Gal.", "Ga.", "Galates", "Galatians", "GAL"],
    "EPH": ["Eph.", "Ephes.", "Ephesiens", "Ephesians", "EPH"],
    "PHP": ["Phil.", "Php.", "Pp.", "Philippiens", "Philippians", "PHP"],
    "COL": ["Col.", "Co.", "Colossiens", "Colossians", "COL"],
    "1TH": [
      "1 Thess.",
      "1 Thes.",
      "1 Th.",
      "I Thess.",
      "I Thes.",
      "I Th.",
      "1Thess.",
      "1Th.",
      "1st Thessalonians",
      "First Thessalonians",
      "1 Thessaloniciens",
      "1 Thessalonians",
      "1TH"
    ],
    "2TH": [
      "2 Thess.",
      "2 Thes.",
      "2 Th.",
      "II Thess.",
      "II Thes.",
      "II Th.",
      "2Thess.",
      "2Th.",
      "2nd Thessalonians",
      "Second Thessalonians",
      "2 Thessaloniciens",
      "2 Thessalonians",
      "2TH"
    ],
    "1TI": [
      "1 Tim.",
      "1 Ti.",
      "I Tim.",
      "I Ti.",
      "1Tim.",
      "1Ti.",
      "1st Timothy",
      "First Timothy",
      "1 Timothee",
      "1 Timothy",
      "1TI"
    ],
    "2TI": [
      "2 Tim.",
      "2 Ti.",
      "II Tim.",
      "II Ti.",
      "2Tim.",
      "2Ti.",
      "2nd Timothy",
      "Second Timothy",
      "2 Timothee",
      "2 Timothy",
      "2TI"
    ],
    "TIT": ["Titus", "Tit", "Ti", "Tite", "TIT"],
    "PHM": ["Philem.", "Phm.", "Pm.", "Philemon", "PHM"],
    "HEB": ["Heb.", "Hebreux", "Hebrews", "HEB"],
    "JAS": ["James", "Jas", "Jm", "Jacques", "JAS"],
    "1PE": [
      "1 Pet.",
      "1 Pe.",
      "1 Pt.",
      "1 P.",
      "I Pet.",
      "I Pt.",
      "I Pe.",
      "1Pet.",
      "1Pe.",
      "1Pt.",
      "1P.",
      "1st Peter",
      "First Peter",
      "1 Pierre",
      "1 Peter",
      "1PE"
    ],
    "2PE": [
      "2 Pet.",
      "2 Pe.",
      "2 Pt.",
      "2 P.",
      "II Pet.",
      "II Pt.",
      "II Pe.",
      "2Pet.",
      "2Pe.",
      "2Pt.",
      "2P.",
      "2nd Peter",
      "Second Peter",
      "2 Pierre",
      "2 Peter",
      "2PE"
    ],
    "1JN": [
      "1 John",
      "1 Jhn.",
      "1 Jn.",
      "1 J.",
      "1Joh.",
      "1Jn.",
      "1Jo.",
      "1J.",
      "I John",
      "I Jhn.",
      "I Joh.",
      "I Jn.",
      "I Jo.",
      "1st John",
      "First John",
      "1 Jean",
      "1JN"
    ],
    "2JN": [
      "2 John",
      "2 Jhn.",
      "2 Jn.",
      "2 J.",
      "2Joh.",
      "2Jn.",
      "2Jo.",
      "2J.",
      "II John",
      "II Jhn.",
      "II Joh.",
      "II Jn.",
      "II Jo.",
      "2nd John",
      "Second John",
      "2 Jean",
      "2JN"
    ],
    "3JN": [
      "3 John",
      "3 Jhn.",
      "3 Jn.",
      "3 J.",
      "3Joh.",
      "3Jn.",
      "3Jo.",
      "3J.",
      "III John",
      "III Jhn.",
      "III Joh.",
      "III Jn.",
      "III Jo.",
      "3rd John",
      "Third John",
      "3 Jean",
      "3JN"
    ],
    "JUD": ["Jude", "Jud.", "Jd.", "JUD"],
    "REV": ["Rev", "Re", "The Revelation", "Apocalypse", "Revelation", "REV"]
  };

  static Map<String, List<String>> get abbreviations {
    return _variants;
  }

  /// Flat lookup map: variant → canonical
  static final Map<String, String> _lookup = _buildLookup();

  

  /// Normalize input: lowercase, strip punctuation/whitespace
  static String _normalize(String input) {
    return removeDiacritics(input)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), ''); // keep only alphanumerics
  }

  /// Build lookup map from variants
  static Map<String, String> _buildLookup() {
    final map = <String, String>{};
    for (final entry in _variants.entries) {
      for (final variant in entry.value) {
        map[_normalize(variant)] = entry.key;
      }
    }
    return map;
  }

  /// Public lookup method
  static String? lookup(String input) {
    return _lookup[_normalize(input)];
  }
}
