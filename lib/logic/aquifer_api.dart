import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../secrets.dart';
import '../providers/aquifer_classes.dart';
import 'package:wolof_bible/main.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io'; // for SocketException
import 'dart:async'; // for TimeoutException

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

  /// returns all languages in aquifer, regardless of whether there is content or not
  Future<List<ResourceLanguage>> loadLanguages({
    required bool shouldRefresh,
  }) async {
    // only initialize once per session
    if (_allLanguages.isNotEmpty) return _allLanguages;

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
          // if a language needs to be deactivated for some reason,
          // you can remove it here before saving and loading to the app
          // for example, if you wanted to remove the language with id 12 (Swahili):
          // responseJson.removeWhere((e) => e['id'] == 12);

          // save to offline
          userPrefsBox.put('resourceLanguages', responseJson);

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

    List<ResourceLanguage> loadLanguagesFromHive(
      List<ResourceLanguage> loadedLanguages,
      dynamic resourceLangData,
    ) {
      List<ResourceLanguage> temp = [];
      temp.addAll(loadedLanguages);

      // Use cached data
      List<Map<String, dynamic>> savedResourceLanguages =
          (resourceLangData as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
      for (var json in savedResourceLanguages) {
        var lang = ResourceLanguage.fromJson(json);
        if (!temp.any((l) => l.id == lang.id)) {
          temp.add(lang);
        }
      }
      return temp;
    }

    List<ResourceLanguage> loadedLanguages = [];

    // Always add offline languages
    if (!kIsWeb) {
      loadedLanguages.addAll(offlineLanguages);
    }

    // Try to get online/cached languages
    try {
      final dynamic resourceLangData = userPrefsBox.get('resourceLanguages');
      if (resourceLangData != null) {
        if (shouldRefresh) {
          // If we should refresh, fetch fresh data
          try {
            List<ResourceLanguage> freshLangs =
                await refreshLanguagesFromAquifer();
            if (freshLangs.isNotEmpty) {
              // Replace or merge? For now let's just use fresh ones as source of truth for online
              // But we must deduplicate against offline languages if they share IDs
              for (var lang in freshLangs) {
                if (!loadedLanguages.any((l) => l.id == lang.id)) {
                  loadedLanguages.add(lang);
                }
              }
            }
          } catch (e) {
            debugPrint(
              'Error fetching languages from aquifer, loading cached langs: $e',
            );
            // If fetch fails, fall back to cached

            final temp = loadLanguagesFromHive(
              loadedLanguages,
              resourceLangData,
            );
            loadedLanguages.clear();
            loadedLanguages.addAll(temp);
          }
        } else {
          final temp = loadLanguagesFromHive(loadedLanguages, resourceLangData);
          loadedLanguages.clear();
          loadedLanguages.addAll(temp);
        }
      } else {
        // No cache, try to fetch
        try {
          List<ResourceLanguage> freshLangs =
              await refreshLanguagesFromAquifer();
          for (var lang in freshLangs) {
            if (!loadedLanguages.any((l) => l.id == lang.id)) {
              loadedLanguages.add(lang);
            }
          }
        } catch (e) {
          // ignore, just use offline found so far
        }
      }
    } catch (e) {
      debugPrint("Error loading languages: $e");
    }

    return loadedLanguages;
  }

  // load all collection metadata that we have with no online/offline filtering
  Future<List<ResourceCollectionInfo>> loadCollections({
    required bool shouldRefresh,
  }) async {
    // only initialize when needed
    if (_allCollections.isNotEmpty) return _allCollections;

    List<ResourceCollectionInfo> loadedCollections = [];

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
            // this first request just gets the codes -
            // we need to now get detailed metadata
            for (var collectionInfo in collectionInfoList) {
              if (collectionInfo is Map<String, dynamic> &&
                  collectionInfo.containsKey('code')) {
                collectionCodes.add(collectionInfo['code']);
              }
            }
            // now get the real full metadata
            final collections = await refreshListCollectionInfoFromAquifer(
              collectionCodes,
            );

            userPrefsBox.put('allCollectionCodes', collectionCodes);
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
    // Real beginning here:

    // Always start with offline resources if not on web

    // Start here
    try {
      if (shouldRefresh) {
        // Refresh from network
        try {
          // If we are truly offline, this might fail, which is caught below
          List<ResourceCollectionInfo> aquiferCollections =
              await refreshCollectionListFromAquifer();
          loadedCollections.addAll(aquiferCollections.toList());
        } catch (e) {
          // Fallback to offline only (already loaded)
          debugPrint('Exception from refreshCollectionListFromAquifer: $e');
        }
      } else {
        // Load from Hive
        try {
          dynamic allCollectionCodes = userPrefsBox
              .get('allCollectionCodes')
              .toList();
          List<ResourceCollectionInfo> hiveCollections =
              loadCollectionsFromHive(List<String>.from(allCollectionCodes));

          // Merge
          for (var col in hiveCollections) {
            if (!loadedCollections.any((c) => c.code == col.code)) {
              loadedCollections.add(col);
            }
          }
        } catch (e) {
          // Fallback
          debugPrint('Exception while attempting loadCollectionsFromHive: $e');
        }
      }
    } catch (e) {
      debugPrint("Error loading collections: $e");
    }

    return loadedCollections;
  }

  /// initializes or ensures initializes the base data
  Future<void> initializeResourceData() async {
    // idempotent check
    if (_allCollections.isNotEmpty && _allLanguages.isNotEmpty) {
      return;
    }

    bool shouldRefreshFromAquifer = true;

    try {
      // Should we refresh from online or just get from stored data?

      final DateTime lastUpdated = userPrefsBox.get(
        'aquiferDataLastUpdated',
        defaultValue: DateTime(2000),
      );
      final String lastBuildNumber = userPrefsBox.get(
        'lastBuildNumber',
        defaultValue: '0',
      );
      // windows was having trouble here so added try catch - so we'll know what's happening if it fails.

      late PackageInfo packageInfo;

      packageInfo = await PackageInfo.fromPlatform();

      final String currentBuildNumber = packageInfo.buildNumber;
      userPrefsBox.put('lastBuildNumber', currentBuildNumber);

      shouldRefreshFromAquifer =
          lastUpdated.isBefore(
            DateTime.now().subtract(const Duration(days: 30)),
          ) ||
          currentBuildNumber != lastBuildNumber;
    } catch (e) {
      debugPrint('Error getting package info; refreshing: $e');
    }

    // shouldRefreshFromAquifer = true; // for testing - force refresh every time

    // get the two main lists of info
    _allCollections = await loadCollections(
      shouldRefresh: shouldRefreshFromAquifer,
    );
    _allLanguages = await loadLanguages(
      shouldRefresh: shouldRefreshFromAquifer,
    );

    // to this point it is very general and could be used to get any and all Aquifer data.
    // Here we filter what we need for the app: at this point we only need
    // languages that have Biblica and Tyndale Study Notes.
    // If you just hide the languages that don't have those - you're all set

    // get the main collections we want
    final mainCollections = _allCollections
        .where(
          (collection) =>
              collection.code == 'TyndaleStudyNotes' ||
              collection.code == 'BiblicaStudyNotes',
        )
        .toList();

    // get the languages in those collections
    Set<int> mainCollectionLanguageCodes = {};
    for (final collection in mainCollections) {
      for (final language in collection.availableLanguages) {
        mainCollectionLanguageCodes.add(language.id);
      }
    }

    // remove languages that are not in those collections
    _allLanguages.removeWhere(
      (l) => !mainCollectionLanguageCodes.contains(l.id),
    );

    if (shouldRefreshFromAquifer &&
        _allCollections.isNotEmpty &&
        _allLanguages.isNotEmpty) {
      userPrefsBox.put('aquiferDataLastUpdated', DateTime.now());
    }
  }

  // Future<void> forceRefreshResourceData() async {
  //   _allCollections.clear();
  //   _allLanguages.clear();
  //   await initializeResourceData();
  // }

  /// Get the resources for a specific language
  List<ResourceCollectionInfo> getResourcesForLanguage(int langId) {
    List<ResourceCollectionInfo> loadedCollections = [];
    // three cases:
    // (there is a fourth but it is handled before you get here:
    //  we're offline on win/mac/ios and can only show offline content)
    // 1) kIsWeb; no offline options.
    // Win/macos/ios:
    //    2) offline options integratedin the case of en, fr
    //    3) no online options in the case of other langs
    bool needOfflineOptions = !kIsWeb && (langId == 1 || langId == 4);

    if (needOfflineOptions) {
      loadedCollections.addAll(offlineResources.toList());

      var allCollectionsForThisLang = _allCollections
          .where(
            (collection) => collection.availableLanguages.any(
              (language) => language.id == langId,
            ),
          )
          .toList();

      // Merge
      for (var col in allCollectionsForThisLang) {
        // Deduplicate against offline
        if (!loadedCollections.any((c) => c.code == col.code)) {
          loadedCollections.add(col);
        }
      }
      return loadedCollections;
    } else {
      return _allCollections
          .where(
            (collection) => collection.availableLanguages.any(
              (language) => language.id == langId,
            ),
          )
          .toList();
    }
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

    // this is where, if on web, we want to get from aquifer, not from assets
    if (!kIsWeb) {
      if (langId == 1 || langId == 4) {
        offlineCapableCodes = {
          'TyndaleStudyNotes',
          'TyndaleStudyNotesBookIntros',
        };
      }
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

            if (response.statusCode != 200) {
              throw AquiferConnectivityException(
                'Status ${response.statusCode}',
              );
            }

            final decoded = json.decode(response.body);
            if (decoded is Map && decoded.containsKey('items')) {
              final data = decoded['items'] as List;
              allMetadata.addAll(data.map((e) => e as Map<String, dynamic>));
            }
          } on SocketException catch (_) {
            throw AquiferConnectivityException('No internet connection');
          } on TimeoutException catch (_) {
            throw AquiferConnectivityException('Request timed out');
          } catch (e) {
            if (e is AquiferConnectivityException) rethrow;
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
            } else {
              throw AquiferConnectivityException(
                'Status ${response.statusCode}',
              );
            }
          } on SocketException catch (_) {
            throw AquiferConnectivityException('No internet connection');
          } on TimeoutException catch (_) {
            throw AquiferConnectivityException('Request timed out');
          } catch (e) {
            if (e is AquiferConnectivityException) rethrow;
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
      final url =
          '$baseUrl/resources/search?resourceType=StudyNotes&bookCode=GEN&startChapter=1&endChapter=1&languageCode=fra&limit=1';
      // final url = baseUrl;
      // ignore: unused_local_variable
      final response = await http
          .get(Uri.parse(url), headers: {'X-App-ID': _appId})
          .timeout(const Duration(seconds: 5));

      if (kDebugMode) {
        debugPrint('checkConnectivity response: ${response.body}');
      }

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
    displayName: 'Notes d\'étude Tyndale (hors ligne)',
    scriptDirection: 'LTR',
  ),
  AvailableLanguage(
    id: 1,
    code: 'eng',
    displayName: 'Tyndale Study Notes (offline)',
    scriptDirection: 'LTR',
  ),
];

final List<AvailableLanguage> offlineIntroLanguages = [
  AvailableLanguage(
    id: 4,
    code: 'fra',
    displayName: 'Introductions Tyndale (hors ligne)',
    scriptDirection: 'LTR',
  ),
  AvailableLanguage(
    id: 1,
    code: 'eng',
    displayName: 'Tyndale Introductions (offline)',
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

/// Custom exception for connectivity issues
class AquiferConnectivityException implements Exception {
  final String message;
  AquiferConnectivityException(this.message);
  @override
  String toString() => message;
}
