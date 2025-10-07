import 'dart:convert';
import 'dart:io';
import 'package:xml/xml.dart';

// Note: This script is intended to be run from the root of the `sfm_parser` directory.

void main(List<String> arguments) async {
  print('Starting SFM to JSON pre-processing...');

  final appDefPath = 'project/appDef.appDef';
  final file = File(appDefPath);

  if (!await file.exists()) {
    print('Error: appDef.appDef not found at $appDefPath');
    print('Please run this script from the `sfm_parser` directory.');
    return;
  }

  final document = XmlDocument.parse(await file.readAsString());

  // Get global text changes from appDef.appDef
  final Map<String, String> changes = {};
  final xmlChanges = document
      .getElement('app-definition')!
      .getElement('changes')
      ?.findAllElements('change');

  if (xmlChanges != null) {
    for (var xmlChange in xmlChanges) {
      final findText = xmlChange.getElement('find')?.innerText;
      final replaceText = xmlChange.getElement('replace')?.innerText;
      if (findText != null && replaceText != null) {
        changes[findText] = replaceText;
      }
    }
  }

  final collections = document.findAllElements('books');
  print('Found ${collections.length} collections.');

  for (final collection in collections) {
    final collectionId = collection.getAttribute('id');
    final books = collection.findAllElements('book');

    print('Processing collection: $collectionId (${books.length} books)');

    for (final book in books) {
      final bookId = book.getAttribute('id');
      final bookName = book.getElement('name')?.innerText;
      final bookFilename = book.getElement('filename')?.innerText;

      if (bookId == null || bookFilename == null || bookName == null) {
        print('Skipping book with missing id, name, or filename.');
        continue;
      }

      final sfmFilePath = 'project/data/books/$collectionId/$bookFilename';
      final sfmFile = File(sfmFilePath);

      if (await sfmFile.exists()) {
        print('  - Processing SFM file for book: $bookId');

        String bookText = await sfmFile.readAsString();

        // 1. Apply global and hardcoded text replacements
        for (var k in changes.keys) {
          String findString = k.replaceAll(r'\', '\\');
          bookText = bookText.replaceAll(RegExp(findString), changes[k]!);
        }
        bookText = bookText.replaceAll(RegExp(r'\+fw\s*'), '');
        var wMarkers = RegExp(r'(\\\w\s)(.*?)(\|\\w\*)');
        bookText = bookText.replaceAllMapped(wMarkers, (Match m) => '${m[2]}');

        // 2. Split book into chapters
        final chapters = bookText.split(r'\c ');
        chapters.removeAt(0); // Remove header content before the first \c

        // 3. Process each chapter
        for (var chapterContent in chapters) {
          final match = RegExp(r'(\d+)(\s|$)').firstMatch(chapterContent);
          if (match == null) continue;

          final chapterNumber = match.group(1)!;
          final lines = chapterContent.split('\n');
          lines.removeAt(0); // Remove chapter number line

          final List<Map<String, dynamic>> chapterData = [];
          String currentVerseNumber = '';

          // Add book title as the first element of the first chapter
          if (chapterNumber == '1') {
            chapterData.add({'style': 'mt1', 'text': bookName});
          }

          for (var line in lines) {
            if (line.trim().isEmpty) continue;

            final lineMatch = RegExp(r'\\(\w+)\s*(.*)').firstMatch(line);
            if (lineMatch == null) continue;

            final style = lineMatch.group(1)!;
            String text = lineMatch.group(2)!;

            final Map<String, dynamic> lineData = {'style': style};

            if (style == 'v') {
              final verseMatch = RegExp(r'(\d+)\s+(.*)').firstMatch(text);
              if (verseMatch != null) {
                currentVerseNumber = verseMatch.group(1)!;
                text = verseMatch.group(2)!;
                lineData['verse'] = currentVerseNumber;
              }
            } else {
              // This line is not a verse start, but should be associated with the last verse number
              if (currentVerseNumber.isNotEmpty) {
                // lineData['verse'] = currentVerseNumber; // Decide if we need this
              }
            }

            lineData['text'] = text;
            chapterData.add(lineData);
          }

          // 4. Write chapter to JSON file
          if (chapterData.isNotEmpty) {
            final outputDir = Directory('../assets/json/$collectionId/$bookId');
            if (!await outputDir.exists()) {
              await outputDir.create(recursive: true);
            }
            final outputFile = File('${outputDir.path}/$chapterNumber.json');
            final jsonContent = json.encode(chapterData);
            await outputFile.writeAsString(jsonContent);
          }
        }
      } else {
        print('  - SFM file not found for book: $bookId at $sfmFilePath');
      }
    }
  }

  print('Pre-processing complete. JSON files generated in `data/json`.');
}
