import 'dart:convert';
import 'dart:io';
import 'package:xml/xml.dart';

// Note: This script is intended to be run from the root of the `sfm_parser` directory.

void sfmToJson() async {
  print('Starting SFM to JSON pre-processing...');

  final projectDir = Directory('project');
  File? appDefFile;

  try {
    await for (final entity in projectDir.list()) {
      if (entity is File && entity.path.endsWith('.appDef')) {
        appDefFile = entity;
        break;
      }
    }
  } catch (e) {
    print('Error reading project directory: $e');
    return;
  }

  if (appDefFile == null) {
    print('Error: No .appDef file found in the `project` directory.');
    print('Please run this script from the `sfm_parser` directory.');
    return;
  }

  print('Using app definition file: ${appDefFile.path}');

  // Derive data folder name from appDef file name
  String appDefFilename = appDefFile.path.split('/').last;
  int dotIndex = appDefFilename.lastIndexOf('.');
  String appDefName = (dotIndex != -1) ? appDefFilename.substring(0, dotIndex) : appDefFilename;
  final String dataFolderName = '${appDefName}_data';
  print('Using data folder: $dataFolderName');

  final document = XmlDocument.parse(await appDefFile.readAsString());

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

    // TOC data structure for the current collection
    final Map<String, dynamic> collectionToc = {};

    print('Processing collection: $collectionId (${books.length} books)');

    for (final book in books) {
      final bookId = book.getAttribute('id');
      final bookName = book.getElement('name')?.innerText;
      final bookFilename = book.getElement('filename')?.innerText;

      if (bookId == null || bookFilename == null || bookName == null) {
        print('Skipping book with missing id, name, or filename.');
        continue;
      }

      // TOC data structure for the current book
      final Map<String, dynamic> bookToc = {
        'name': bookName,
        'chapters': <String, String>{},
      };

      final sfmFilePath = 'project/$dataFolderName/books/$collectionId/$bookFilename';
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
          String lastVerseLabel = ''; // For TOC

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
              // Updated regex to handle verse ranges like '15-16'
              final verseMatch = RegExp(r'([\w-]+)\s+(.*)').firstMatch(text);
              if (verseMatch != null) {
                currentVerseNumber = verseMatch.group(1)!;
                lastVerseLabel = currentVerseNumber; // Track last verse for TOC
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

          // Add chapter's last verse to the book's TOC
          if (lastVerseLabel.isNotEmpty) {
            bookToc['chapters']![chapterNumber] = lastVerseLabel;
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
        // Add the completed book TOC to the collection TOC
        collectionToc[bookId] = bookToc;

      } else {
        print('  - SFM file not found for book: $bookId at $sfmFilePath');
      }
    }

    // Write the TOC for the entire collection
    if (collectionId != null) {
      final outputDir = Directory('../assets/json/');
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }
      final tocFile = File('${outputDir.path}/${collectionId}_toc.json');
      final jsonContent = json.encode(collectionToc);
      await tocFile.writeAsString(jsonContent);
      print('Generated TOC for $collectionId at ${tocFile.path}');
    }
  }

  print('Pre-processing complete. JSON files generated in `assets/json`.');
}

void copyAppDef() async {
  print('testParser: Copying .appDef file to assets/json/appDef.appDef');

  final projectDir = Directory('project');
  File? sourceFile;

  try {
    await for (final entity in projectDir.list()) {
      if (entity is File && entity.path.endsWith('.appDef')) {
        sourceFile = entity;
        break;
      }
    }
  } catch (e) {
    print('Error reading project directory: $e');
    return;
  }

  if (sourceFile == null) {
    print('Error: No .appDef file found in the `project` directory.');
    print('Please run this script from the `sfm_parser` directory.');
    return;
  }

  final destinationPath = '../assets/json/appDef.appDef';

  try {
    final destinationFile = File(destinationPath);
    await destinationFile.parent.create(recursive: true);
    await sourceFile.copy(destinationPath);
    print('Successfully copied ${sourceFile.path} to $destinationPath');
  } catch (e) {
    print('An error occurred during file copy: $e');
  }
}

Future<void> deleteExistingJsonFiles() async {
  print('Deleting contents of ../assets/json/');
  final jsonDir = Directory('../assets/json');

  if (await jsonDir.exists()) {
    try {
      final entities = jsonDir.list();
      await for (final entity in entities) {
        await entity.delete(recursive: true);
      }
      print('Successfully deleted contents of ${jsonDir.path}');
    } catch (e) {
      print('An error occurred while deleting files: $e');
    }
  } else {
    print('JSON directory not found, nothing to delete.');
  }
}

void main(List<String> arguments) async {
  await deleteExistingJsonFiles();
  copyAppDef();
  sfmToJson();
}
