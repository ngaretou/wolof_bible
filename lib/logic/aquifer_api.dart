import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../secrets.dart';
import '../providers/aquifer_classes.dart';
import 'package:wolof_bible/main.dart';
import 'package:flutter/services.dart' show rootBundle;

const String baseUrl = 'https://aquifer-proxy.corey-garrett.workers.dev';

class AquiferService {
  // make it a singleton
  static final AquiferService _instance = AquiferService._internal();

  factory AquiferService() {
    return _instance;
  }

  AquiferService._internal();
  // end make it a singleton

  static const String _appId = appId;
  List<ResourceCollectionInfo> _allCollections = [];
  List<ResourceLanguage> _allLanguages = [];

  List<ResourceCollectionInfo> get allCollections =>
      UnmodifiableListView(_allCollections);
  List<ResourceLanguage> get allLanguages =>
      UnmodifiableListView(_allLanguages);

  Future<List<ResourceLanguage>> refreshLanguagesFromAquifer() async {
    final uri = Uri.parse('$baseUrl/languages');
    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-App-ID': _appId, // CRITICAL: Must match the secret on Cloudflare
        },
      );

      if (response.statusCode == 200) {
        if (kDebugMode) {
          debugPrint('got languages from aquifer');
        }
        // get the format we need
        List<dynamic> responseJson = json.decode(response.body);
        // move french to the top
        int? frenchLanguageIndex;
        for (int i = 0; i < responseJson.length; i++) {
          if (responseJson[i]['code'] == 'fra') {
            frenchLanguageIndex = i;
            break;
          }
        }
        if (frenchLanguageIndex != null) {
          final frenchLanguage = responseJson.removeAt(frenchLanguageIndex);
          responseJson.insert(0, frenchLanguage);
        }
        // save to offline
        userPrefsBox.put('resourceLanguages', responseJson);
        userPrefsBox.put('resourceLanguagesLastUpdated', DateTime.now());

        return responseJson.map((e) => ResourceLanguage.fromJson(e)).toList();
      } else {
        debugPrint('Error: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('Exception: $e');
      return [];
    }
  }

  /// returns all languages in aquifer, regardless of whether there is content or not
  Future<List<ResourceLanguage>> loadLanguages(bool connected) async {
    // only initialize once per session
    if (_allLanguages.isNotEmpty) return _allLanguages;
    // if we're offline, just use the offline languages
    if (!connected) {
      return offlineLanguages.toList();
    } else {
      // we're online, and could get languages, but let's only check once a month max
      final resourceLangData = userPrefsBox.get('resourceLanguages');
      // not doing anything with the data yet, just checking it's there
      if (resourceLangData != null) {
        final DateTime lastUpdated = userPrefsBox.get(
          'resourceLanguagesLastUpdated',
        );
        if (lastUpdated.isBefore(
          // DateTime.now().subtract(const Duration(days: 0)), // testing
          DateTime.now().subtract(const Duration(days: 30)), // production
        )) {
          // if it's been a month, let's get the latest languages
          return await refreshLanguagesFromAquifer();
        } else {
          // only deal with the data if we're going to use it
          List<Map<String, dynamic>>? savedResourceLanguages =
              (resourceLangData as List)
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();

          return savedResourceLanguages
              .map((e) => ResourceLanguage.fromJson(e))
              .toList();
        }
      } else {
        // we're online and there's no saved languages - get online languages
        return await refreshLanguagesFromAquifer();
      }
    }
  }

  // multiple collection metadata retrieval
  Future<List<ResourceCollectionInfo>> loadCollections(bool connected) async {
    // only initialize when needed
    if (_allCollections.isNotEmpty) return _allCollections;

    /// Get the metadata for a single collection from Aquifer and save it to Hive
    Future<ResourceCollectionInfo?> refreshCollectionInfoFromAquifer(
      String resourceCode,
    ) async {
      final uri = Uri.parse('$baseUrl/resources/collections/$resourceCode');
      try {
        final response = await http.get(
          uri,
          headers: {'Content-Type': 'application/json', 'X-App-ID': _appId},
        );

        if (response.statusCode == 200) {
          // get it usable
          final jsonData = json.decode(response.body);
          // save it for later
          userPrefsBox.put(resourceCode, response.body);
          // send it on as a class
          return ResourceCollectionInfo.fromJson(jsonData);
        } else {
          debugPrint('Error: ${response.statusCode} - ${response.body}');
          return null;
        }
      } catch (e) {
        debugPrint('Exception: $e');
        return null;
      }
    }

    /// helper for online retreival and Listifying of a list of collections from Aquifer
    Future<List<ResourceCollectionInfo>> refreshListCollectionInfoFromAquifer(
      List<String> collectionCodes,
    ) async {
      List<ResourceCollectionInfo> collections = [];

      for (var resourceCode in collectionCodes) {
        // saved to Hive here
        final collectionInfo = await refreshCollectionInfoFromAquifer(
          resourceCode,
        );
        if (collectionInfo != null) {
          collections.add(collectionInfo);
        }
      }
      if (collections.isNotEmpty) {
        //
        userPrefsBox.put('collectionsLastUpdated', DateTime.now());
      }
      return collections;
    }

    /// set up to get all collections by type or default to StudyNotes
    Future<List<ResourceCollectionInfo>> refreshCollectionListFromAquifer({
      List<String> resourceTypes = const ['StudyNotes'],
    }) async {
      List<ResourceCollectionInfo> collections = [];
      for (final resourceType in resourceTypes) {
        final uri = Uri.parse(
          '$baseUrl/resources/collections?resourceType=$resourceType',
        );
        try {
          final response = await http.get(uri, headers: {'X-App-ID': _appId});

          if (response.statusCode == 200) {
            List<String> collectionCodes = [];
            List<dynamic> collectionInfoList = json.decode(response.body);
            for (var collectionInfo in collectionInfoList) {
              if (collectionInfo is Map<String, dynamic> &&
                  collectionInfo.containsKey('code')) {
                collectionCodes.add(collectionInfo['code']);
              }
            }
            final collections = await refreshListCollectionInfoFromAquifer(
              collectionCodes,
            );
            List<String> allCollectionCodes = collections
                .map((collection) => collection.code)
                .toList();
            userPrefsBox.put('allCollectionCodes', allCollectionCodes);
            return collections;
          } else {
            debugPrint('Error: ${response.statusCode} - ${response.body}');
            return [];
          }
        } catch (e) {
          debugPrint('Exception: $e');
          return [];
        }
      }

      return collections;
    }

    // single collection metadata retrieval
    ResourceCollectionInfo? loadCollectionInfoFromHive(String resourceCode) {
      final resourceCollectionInfo = json.decode(
        userPrefsBox.get(resourceCode),
      );

      if (resourceCollectionInfo != null) {
        return ResourceCollectionInfo.fromJson(resourceCollectionInfo);
      }
      return null;
    }

    List<ResourceCollectionInfo> loadCollectionsFromHive(
      List<String> collectionCodes,
    ) {
      /// helper for offline retreival and Listifying of online resources
      List<ResourceCollectionInfo> collections = [];
      try {
        for (var resourceCode in collectionCodes) {
          final collectionInfo = loadCollectionInfoFromHive(resourceCode);
          if (collectionInfo != null) {
            collections.add(collectionInfo);
          }
        }
        return collections;
      } catch (e) {
        debugPrint('Exception from loadCollectionsFromHive: $e');
        return [];
      }
    }

    if (!connected) {
      return offlineResources.toList();
    } else {
      bool useDefaultResourcesOnly =
          userPrefsBox.get('useDefaultResourcesOnly') ?? true;
      // we're online
      final DateTime? lastUpdated = userPrefsBox.get('collectionsLastUpdated');

      // let's only update collection info every 30 days

      if (lastUpdated == null ||
          lastUpdated.isBefore(
            // DateTime.now().subtract(const Duration(days: 0)), // testing
            DateTime.now().subtract(const Duration(days: 30)), // production
          )) {
        try {
          List<ResourceCollectionInfo> aquiferCollections =
              await refreshCollectionListFromAquifer();
          if (useDefaultResourcesOnly) {
            return aquiferCollections
                .where(
                  (collection) => defaultResources.any(
                    (resource) => resource == collection.code,
                  ),
                )
                .toList();
          } else {
            return aquiferCollections;
          }
        } catch (e) {
          // fallback to local collections if we can't get online
          return offlineResources.toList();
        }
      } else {
        try {
          if (useDefaultResourcesOnly) {
            return loadCollectionsFromHive(defaultResources);
          } else {
            List<String> allCollectionCodes = userPrefsBox.get(
              'allCollectionCodes',
            );
            return loadCollectionsFromHive(allCollectionCodes);
          }
        } catch (e) {
          // fallback to local collections if we can't get hive or local
          return offlineResources.toList();
        }
      }
    }
  }

  /// this globally filters the
  Future<void> initializeResourceData(bool connected) async {
    // get the two main lists of info
    _allCollections = await loadCollections(connected);
    _allLanguages = await loadLanguages(connected);

    // only show languages in the interface that actually have the two main study note collections
    final mainCollections = _allCollections
        .where(
          (collection) =>
              collection.code == 'TyndaleStudyNotes' ||
              collection.code == 'BiblicaStudyNotes',
        )
        .toList();

    // get the languages in those two main collections
    final Set<int> mainCollectionLanguageCodes = {};
    for (final collection in mainCollections) {
      for (final language in collection.availableLanguages) {
        mainCollectionLanguageCodes.add(language.id);
      }
    }
    // finally filter the languages to display to those that have meaningful data
    _allLanguages = _allLanguages
        .where((language) => mainCollectionLanguageCodes.contains(language.id))
        .toList();
  }

  Future<void> reInitializeResourceData(bool connected) async {
    _allCollections.clear();
    _allLanguages.clear();
    await initializeResourceData(connected);
  }

  List<ResourceCollectionInfo> getResourcesForLanguage(int langId) {
    return _allCollections
        .where(
          (collection) => collection.availableLanguages.any(
            (language) => language.id == langId,
          ),
        )
        .toList();
  }

  /// Get the articles for a specific chapter as a stream
  Stream<ResourceItem> streamResourcesForChapter({
    required bool connected,
    required int langId,
    required List<String> resourceCollectionCodes,
    required String? book,
    required String? chapter,
    String? startVerse,
    String? endVerse,
    // bool reverse = false,
  }) async* {
    if (book == null || chapter == null) {
      return;
    }

    // offline only for 1: eng and 4: fra
    Set<String> offlineCapableCodes = {};
    if (langId == 1 || langId == 4) {
      offlineCapableCodes = {
        'TyndaleStudyNotes',
        'TyndaleStudyNotesBookIntros',
      };
    }

    final offlineTargets = resourceCollectionCodes
        .where((code) => offlineCapableCodes.contains(code))
        .toList();
    final onlineTargets = resourceCollectionCodes
        .where((code) => !offlineCapableCodes.contains(code))
        .toList();

    // 1. Parallel Fetching
    final Future<List<_SortableItem>> offlineFuture = Future(() async {
      List<_SortableItem> results = [];
      for (final code in offlineTargets) {
        final items = await _fetchOfflineResources(
          langId: langId,
          resourceCollectionCode: code,
          book: book,
          chapter: chapter,
          startVerse: startVerse,
        );
        results.addAll(
          items.map((item) {
            final chAndVerse = AquiferService.getChAndVerseFromTitle(
              item.localizedName,
            );
            return _SortableItem(
              priority: _getPriority(item.resourceCollectionCode),
              chapter: chAndVerse.first,
              verse: chAndVerse.last,
              name: item.localizedName,
              isOffline: true,
              data: item,
            );
          }),
        );
      }
      return results;
    });

    // TODO if type is image, themes, profiles; get the ref from the associations and put it at the first of those refs for the chapter
    // currently we just put those at the end of the ch
    final Future<List<_SortableItem>> onlineFuture = Future(() async {
      if (!connected || onlineTargets.isEmpty) {
        return [];
      }
      List<Map<String, dynamic>> allMetadata = [];
      await Future.wait(
        onlineTargets.map((code) async {
          try {
            final url =
                '$baseUrl/resources/search?resourceCollectionCode=$code&bookCode=$book&startChapter=$chapter&endChapter=$chapter&languageId=$langId&limit=100';
            final response = await http
                .get(Uri.parse(url), headers: {'X-App-ID': _appId})
                .timeout(const Duration(seconds: 10));
            final decoded = json.decode(response.body);
            if (decoded is Map && decoded.containsKey('items')) {
              final data = decoded['items'] as List;
              allMetadata.addAll(data.map((e) => e as Map<String, dynamic>));
            }
          } catch (e) {
            debugPrint('Error fetching metadata for $code: $e');
          }
        }),
      );
      return allMetadata.map((json) {
        final code = json['grouping']?['collectionCode'] ?? '';
        final name = json['localizedName'] ?? '';
        final chAndVerse = AquiferService.getChAndVerseFromTitle(name);

        return _SortableItem(
          priority: _getPriority(code),
          chapter: chAndVerse.first,
          verse: chAndVerse.last,
          name: name,
          isOffline: false,
          data: json,
        );
      }).toList();
    });

    final List<List<_SortableItem>> results = await Future.wait([
      offlineFuture,
      onlineFuture,
    ]);
    final List<_SortableItem> allItems = results.expand((x) => x).toList();

    // 2. Sorting
    allItems.sort((a, b) {
      if (a.priority != b.priority) {
        return a.priority.compareTo(b.priority);
      }
      if (a.chapter != b.chapter) {
        return a.chapter.compareTo(b.chapter);
      }
      if (a.verse != b.verse) {
        return a.verse.compareTo(b.verse);
      }
      return a.name.compareTo(b.name);
    });

    // if (reverse) {
    //   final reversed = allItems.reversed.toList();
    //   allItems.clear();
    //   allItems.addAll(reversed);
    // }

    // 3. Streaming - Parallelized & Ordered
    // Map to futures to start all requests immediately while preserving order
    final List<Future<ResourceItem?>> orderedFutures = allItems.map((item) {
      if (item.isOffline) {
        return Future.value(item.data as ResourceItem);
      } else {
        return Future<ResourceItem?>(() async {
          try {
            final summary = item.data as Map<String, dynamic>;
            final contentId = summary['id'];
            final url = '$baseUrl/resources/$contentId?contentTextType=html';
            final response = await http
                .get(Uri.parse(url), headers: {'X-App-ID': _appId})
                .timeout(const Duration(seconds: 10));

            if (response.statusCode == 200) {
              final detail = json.decode(response.body) as Map<String, dynamic>;
              return ResourceItem.fromCombinedJson(
                summary,
                detail,
                bookID: book,
                chapter: int.tryParse(chapter) ?? 0,
                verse: item.verse,
              );
            }
          } catch (e) {
            debugPrint('Error fetching specific resource: $e');
          }
          return null;
        });
      }
    }).toList();

    // Yield results in the correct sorted order
    for (final future in orderedFutures) {
      final item = await future;
      if (item != null) {
        yield item;
      }
    }
  }

  int _getPriority(String code) {
    if (code.contains('Intro')) return 1;
    if (code.contains('Themes')) return 3;
    if (code.contains('Profiles')) return 4;
    if (code.contains('Image')) return 5;
    if (code.contains('Notes')) return 2;
    return 99;
  }

  static List<int> getChAndVerseFromTitle(String name) {
    final match = RegExp(r'(\d+)[:\.](\d+)').firstMatch(name);
    if (match != null) {
      return [int.parse(match.group(1)!), int.parse(match.group(2)!)];
    }
    return [0, 0];
  }

  Future<bool> checkConnectivity() async {
    try {
      // ignore: unused_local_variable
      // final url =
      //     '$baseUrl/resources/search?resourceType=StudyNotes&bookCode=GEN&startChapter=1&endChapter=1&languageCode=fra&limit=1';
      final url = baseUrl;
      // ignore: unused_local_variable
      final response = await http
          .get(Uri.parse(url), headers: {'X-App-ID': _appId})
          .timeout(const Duration(seconds: 5));

      // if (kDebugMode) {
      //   debugPrint('checkConnectivity response: ${response.body}');
      // }

      return true;

      // We consider it connected if we get a response, even if it's an error from the server (meaning we reached it).
      // But strictly speaking, we want to know if the API is usable.
      // Let's assume any response is good connectivity.
    } catch (e) {
      return false;
    }
  }

  // Book code to number mapping (standard English codes)
  // Book code to number mapping (standard English codes)
  static const Map<String, String> bookCodeToNumber = {
    'GEN': '01',
    'EXO': '02',
    'LEV': '03',
    'NUM': '04',
    'DEU': '05',
    'JOS': '06',
    'JDG': '07',
    'RUT': '08',
    '1SA': '09',
    '2SA': '10',
    '1KI': '11',
    '2KI': '12',
    '1CH': '13',
    '2CH': '14',
    'EZR': '15',
    'NEH': '16',
    'EST': '17',
    'JOB': '18',
    'PSA': '19',
    'PRO': '20',
    'ECC': '21',
    'SNG': '22',
    'ISA': '23',
    'JER': '24',
    'LAM': '25',
    'EZK': '26',
    'DAN': '27',
    'HOS': '28',
    'JOL': '29',
    'AMO': '30',
    'OBA': '31',
    'JON': '32',
    'MIC': '33',
    'NAM': '34',
    'HAB': '35',
    'ZEP': '36',
    'HAG': '37',
    'ZEC': '38',
    'MAL': '39',
    'MAT': '40',
    'MRK': '41',
    'LUK': '42',
    'JHN': '43',
    'ACT': '44',
    'ROM': '45',
    '1CO': '46',
    '2CO': '47',
    'GAL': '48',
    'EPH': '49',
    'PHP': '50',
    'COL': '51',
    '1TH': '52',
    '2TH': '53',
    '1TI': '54',
    '2TI': '55',
    'TIT': '56',
    'PHM': '57',
    'HEB': '58',
    'JAS': '59',
    '1PE': '60',
    '2PE': '61',
    '1JN': '62',
    '2JN': '63',
    '3JN': '64',
    'JUD': '65',
    'REV': '66',
  };

  Future<List<ResourceItem>> _fetchOfflineResources({
    required int langId,
    required String resourceCollectionCode,
    required String book,
    required String chapter,
    String? startVerse,
  }) async {
    List<ResourceItem> items = [];
    try {
      final langCode = langId == 4 ? 'fra' : 'eng';
      final bookNum = bookCodeToNumber[book];

      if (bookNum == null) {
        debugPrint('Book code $book not found in offline mapping');
        return [];
      }

      final assetPath =
          'assets/aquifer/$langCode/$resourceCollectionCode/$bookNum.content.json';
      try {
        final jsonString = await rootBundle.loadString(assetPath);
        final List<dynamic> jsonList = json.decode(jsonString);

        // Filter and map items
        for (var item in jsonList) {
          final indexRef = item['index_reference'] as String?;
          if (indexRef != null && indexRef.length >= 8) {
            // Parse chapter from index_reference: 01001001 -> 01 (book) 001 (chapter) 001 (verse)
            // Indices: 0-1 book, 2-4 chapter, 5-7 verse
            final itemChapter = int.tryParse(indexRef.substring(2, 5));

            final requestedChapter = int.tryParse(chapter);
            if (itemChapter != null &&
                (itemChapter == requestedChapter ||
                    (requestedChapter == 1 && itemChapter == 0))) {
              // Map to ResourceItem
              final localizedName = item['title'] ?? '';
              final mediaTypeStr = item['media_type'] ?? 'Text';
              final resourceType = mediaTypeStr == 'Image'
                  ? ResourceType.images
                  : ResourceType.studyNotes;

              items.add(
                ResourceItem(
                  id: item['content_id'].toString(),
                  resourceCollectionCode: resourceCollectionCode,
                  localizedName: localizedName,
                  resourceType: resourceType,
                  content: item['content'] ?? '',
                  langID: langId,
                  scriptDirection: langId == 4 ? 'LTR' : 'LTR',
                  bookID: book,
                  chapter: itemChapter,
                  verse: int.tryParse(indexRef.substring(5, 8)) ?? 0,
                ),
              );
            }
          }
        }
      } catch (e) {
        // It's possible the file doesn't exist for this specific collection/book combo
        // e.g. BookIntros might not have every book or the file naming might differ
        // quiet fail is okay for offline assets not found, but logging is good.
        // debugPrint('Error loading offline asset $assetPath: $e');
      }
    } catch (e) {
      debugPrint('Error fetching offline resources: $e');
    }
    return items;
  }
}

void prettyPrintJson(String rawJson) {
  final decoded = json.decode(rawJson);
  const encoder = JsonEncoder.withIndent('  ');
  final prettyJson = encoder.convert(decoded);
  print(prettyJson);
}

final LicenseInfo offlineLicenseInfo = LicenseInfo(
  code: 'TyndaleStudyNotes',
  dates: '2019',
  holderName: 'Tyndale House Publishers',
  holderUrl: 'https://tyndaleopenresources.com',
  licenseName: 'CC BY-SA 4.0 license',
  licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/legalcode.en',
);

final List<ResourceLanguage> offlineLanguages = [
  ResourceLanguage(
    id: 4,
    code: 'fra',
    localizedDisplay: 'Français',
    scriptDirection: 'LTR',
  ),
  ResourceLanguage(
    id: 1,
    code: 'eng',
    localizedDisplay: 'English',
    scriptDirection: 'LTR',
  ),
];

final List<AvailableLanguage> offlineNoteLanguages = [
  AvailableLanguage(
    id: 4,
    code: 'fra',
    displayName: 'Notes d\'étude',
    scriptDirection: 'LTR',
  ),
  AvailableLanguage(
    id: 1,
    code: 'eng',
    displayName: 'Study Notes',
    scriptDirection: 'LTR',
  ),
];

final List<AvailableLanguage> offlineIntroLanguages = [
  AvailableLanguage(
    id: 4,
    code: 'fra',
    displayName: 'Introductions',
    scriptDirection: 'LTR',
  ),
  AvailableLanguage(
    id: 1,
    code: 'eng',
    displayName: 'Introductions',
    scriptDirection: 'LTR',
  ),
];

final List<ResourceCollectionInfo> offlineResources = [
  ResourceCollectionInfo(
    code: 'TyndaleStudyNotes',
    resourceType: ResourceType.studyNotes,
    licenseInfo: offlineLicenseInfo,
    availableLanguages: offlineNoteLanguages,
  ),
  ResourceCollectionInfo(
    code: 'TyndaleStudyNotesBookIntros',
    resourceType: ResourceType.studyNotes,
    licenseInfo: offlineLicenseInfo,
    availableLanguages: offlineIntroLanguages,
  ),
];

final List<String> defaultResources = [
  'TyndaleStudyNotes',
  'TyndaleStudyNotesBookIntros',
  // 'TyndaleStudyNotesThemes',
  'TyndaleStudyNotesProfiles',
  // 'BiblicaStudyNotes',
  // 'BiblicaStudyNotesBookIntros',
  // 'UbsImages',
];

class _SortableItem {
  final int priority;
  final int chapter;
  final int verse;
  final String name;
  final bool isOffline;
  final dynamic data;

  _SortableItem({
    required this.priority,
    required this.chapter,
    required this.verse,
    required this.name,
    required this.isOffline,
    required this.data,
  });
}
