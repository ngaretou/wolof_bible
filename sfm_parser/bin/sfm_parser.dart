import 'dart:convert';
import 'dart:io';
import 'package:xml/xml.dart';
import 'stopwords.dart';
import 'package:snowball_stemmer/snowball_stemmer.dart';


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
  final document = XmlDocument.parse(await appDefFile.readAsString());

  // Get default language as a fallback
  final defaultLang =
      document
          .getElement('app-definition')!
          .getElement('translation-mappings')
          ?.getAttribute('default-lang') ??
      'en';

  // Derive data folder name from appDef file name
  String appDefFilename = appDefFile.path.split('/').last;
  int dotIndex = appDefFilename.lastIndexOf('.');
  String appDefName = (dotIndex != -1)
      ? appDefFilename.substring(0, dotIndex)
      : appDefFilename;
  final String dataFolderName = '${appDefName}_data';
  print('Using data folder: $dataFolderName');

  final collections = document.findAllElements('books');
  print('Found ${collections.length} collections.');

  for (final collection in collections) {
    final collectionId = collection.getAttribute('id');
    final books = collection.findAllElements('book');

    // Determine language for this collection
    final lang =
        collection.getElement('writing-system')?.getAttribute('code') ??
        defaultLang;
    print(
      'Processing collection: $collectionId (${books.length} books) with language: $lang',
    );

    // Select processor based on language
    final stemmer = (lang == 'en')
        ? SnowballStemmer(Algorithm.english)
        : (lang == 'fr')
        ? SnowballStemmer(Algorithm.french)
        : null;
    final stopWords = (lang == 'en')
        ? enStopWords
        : (lang == 'fr')
        ? frStopWords
        : <String>{};

    // Data structures for TOC and Search Index
    final Map<String, dynamic> collectionToc = {};
    final Map<String, List<List<dynamic>>> invertedIndex = {};

    for (final book in books) {
      final bookId = book.getAttribute('id');
      final bookName = book.getElement('name')?.innerText;
      final bookFilename = book.getElement('filename')?.innerText;

      if (bookId == null || bookFilename == null || bookName == null) {
        print('Skipping book with missing id, name, or filename.');
        continue;
      }

      final Map<String, dynamic> bookToc = {
        'name': bookName,
        'chapters': <String, String>{},
      };

      final sfmFilePath =
          'project/$dataFolderName/books/$collectionId/$bookFilename';
      final sfmFile = File(sfmFilePath);

      if (await sfmFile.exists()) {
        print('  - Processing SFM file for book: $bookId');
        String bookText = await sfmFile.readAsString();

        final chapters = bookText.split(r'\c ');
        chapters.removeAt(0);

        for (var chapterContent in chapters) {
          final match = RegExp(r'(\d+)(\s|$)').firstMatch(chapterContent);
          if (match == null) continue;

          final chapterNumber = int.parse(match.group(1)!);
          final lines = chapterContent.split('\n');
          lines.removeAt(0);

          final List<Map<String, dynamic>> chapterData = [];
          String currentVerseNumber = '';
          String lastVerseLabel = '';

          if (chapterNumber == 1) {
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
              final verseMatch = RegExp(r'([\w-]+)\s+(.*)').firstMatch(text);
              if (verseMatch != null) {
                currentVerseNumber = verseMatch.group(1)!;
                lastVerseLabel = currentVerseNumber;
                text = verseMatch.group(2)!;
                lineData['verse'] = currentVerseNumber;
              }
            }

            lineData['text'] = text;
            chapterData.add(lineData);

            // Index the text content, avoiding titles and metadata
            if (text.isNotEmpty &&
                !{'mt1', 'h', 'toc1', 'toc2', 'toc3'}.contains(style)) {
              final tokens = text.toLowerCase().split(
                RegExp(r'[^\p{L}\p{N}]+', unicode: true),
              );
              for (var token in tokens) {
                if (token.isEmpty || stopWords.contains(token)) continue;
                final processedToken = stemmer?.stem(token) ?? token;

                final location = [bookId, chapterNumber, currentVerseNumber];
                // Add to index, but prevent duplicate locations for the same verse
                final locations = invertedIndex.putIfAbsent(
                  processedToken,
                  () => [],
                );
                if (locations.every(
                  (l) =>
                      l[0] != location[0] ||
                      l[1] != location[1] ||
                      l[2] != location[2],
                )) {
                  locations.add(location);
                }
              }
            }
          }

          if (lastVerseLabel.isNotEmpty) {
            bookToc['chapters']![chapterNumber.toString()] = lastVerseLabel;
          }

          if (chapterData.isNotEmpty) {
            final outputDir = Directory('../assets/json/$collectionId/$bookId');
            if (!await outputDir.exists()) {
              await outputDir.create(recursive: true);
            }
            final outputFile = File('${outputDir.path}/$chapterNumber.json');
            await outputFile.writeAsString(json.encode(chapterData));
          }
        }
        collectionToc[bookId] = bookToc;
      } else {
        print('  - SFM file not found for book: $bookId at $sfmFilePath');
      }
    }

    if (collectionId != null) {
      // Write TOC file
      final tocDir = Directory('../assets/json/');
      if (!await tocDir.exists()) {
        await tocDir.create(recursive: true);
      }
      final tocFile = File('${tocDir.path}/${collectionId}_toc.json');
      await tocFile.writeAsString(json.encode(collectionToc));
      print('Generated TOC for $collectionId at ${tocFile.path}');

      // Partition the index by the first letter of the token
      final Map<String, Map<String, List<List<dynamic>>>> partitionedIndex = {};
      invertedIndex.forEach((token, locations) {
        if (token.isNotEmpty) {
          final firstLetter = token[0];
          partitionedIndex.putIfAbsent(firstLetter, () => {})[token] = locations;
        }
      });

      // Write the partitioned index files
      for (var entry in partitionedIndex.entries) {
        final letter = entry.key;
        final indexData = entry.value;
        final indexDir = Directory('../assets/json/$collectionId/index');
        if (!await indexDir.exists()) {
          await indexDir.create(recursive: true);
        }
        final indexFile = File('${indexDir.path}/$letter.json');
        await indexFile.writeAsString(json.encode(indexData));
      }
      print('Generated partitioned index for $collectionId in ../assets/json/$collectionId/index/');
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

void testingsplit() {
  String text = 'Yàlla sàkk na ásamën';
  // final tokens = text.toLowerCase().split(RegExp(r'\W+'));
  final tokens = text.toLowerCase().split(
    RegExp(r'[^\p{L}\p{N}]+', unicode: true),
  );
  for (String token in tokens) {
    print(token);
  }
}

void main(List<String> arguments) async {
  await deleteExistingJsonFiles();
  copyAppDef();
  sfmToJson();
  // testingsplit();
}
