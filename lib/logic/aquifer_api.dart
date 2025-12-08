import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../secrets.dart';
import '../providers/aquifer_classes.dart';
import '../main.dart';

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

  Future<ResourceCollectionInfo?> getResourceCollectionInfoFromAquifer(
    String resourceCode,
  ) async {
    final uri = Uri.parse('$baseUrl/resources/collections/$resourceCode');
    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-App-ID': _appId, // CRITICAL: Must match the secret on Cloudflare
        },
      );

      if (response.statusCode == 200) {
        // get it usable
        final jsonData = json.decode(response.body);
        // save it for later
        userPrefsBox.put(resourceCode, jsonData);
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

  // single collection metadata retrieval
  ResourceCollectionInfo? getResourceCollectionInfoFromHive(
    String resourceCode,
  ) {
    final resourceCollectionInfo = userPrefsBox.get(resourceCode);
    if (resourceCollectionInfo != null) {
      return ResourceCollectionInfo.fromJson(resourceCollectionInfo);
    }
    return null;
  }

  // multiple collection metadata retrieval
  Future<List<ResourceCollectionInfo>> getAvailableCollections(
    bool connected,
  ) async {
    // only initialize when needed
    if (_allCollections.isNotEmpty) return _allCollections;
    //helper for offline retreival and Listifying of online resources
    List<ResourceCollectionInfo> getCollectionsFromHive() {
      List<ResourceCollectionInfo> collections = [];
      try {
        for (var resourceCode in targetedResources) {
          final collectionInfo = getResourceCollectionInfoFromHive(
            resourceCode,
          );
          if (collectionInfo != null) {
            collections.add(collectionInfo);
          }
        }
        return collections;
      } catch (e) {
        return [];
      }
    }

    //helper for online retreival and Listifying
    Future<List<ResourceCollectionInfo>> getCollectionsFromAquifer() async {
      List<ResourceCollectionInfo> collections = [];
      for (var resourceCode in targetedResources) {
        final collectionInfo = await getResourceCollectionInfoFromAquifer(
          resourceCode,
        );
        if (collectionInfo != null) {
          collections.add(collectionInfo);
        }
      }
      if (collections.isNotEmpty) {
        userPrefsBox.put('collectionsLastUpdated', DateTime.now());
      }
      return collections;
    }

    if (!connected) {
      return offlineResources.toList();
    } else {
      // we're online
      final DateTime? lastUpdated = userPrefsBox.get('collectionsLastUpdated');

      // let's only update collection info every 30 days

      if (lastUpdated == null ||
          lastUpdated.isBefore(
            // DateTime.now().subtract(const Duration(days: 0)), // testing
            DateTime.now().subtract(const Duration(days: 30)), // production
          )) {
        try {
          return await getCollectionsFromAquifer();
        } catch (e) {
          // fallback to local collections if we can't get online
          return offlineResources.toList();
        }
      } else {
        try {
          final result = getCollectionsFromHive();
          if (result.isNotEmpty) {
            return result;
          } else {
            return await getCollectionsFromAquifer();
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
    _allCollections = await getAvailableCollections(connected);
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

  // if (collectionInfo.availableLanguages.any(
  //           (language) => language.id == langId,
  //         )) {
  //           collections.add(collectionInfo);
  //         }

  /// set up to get all collections by type or default to StudyNotes
  /// This works but is unused
  // Future<List<ResourceCollectionInfo>> getResourceCollections({
  //   String resourceType = 'StudyNotes',
  // }) async {
  //   List<ResourceCollectionInfo> collections = [];

  //   final uri = Uri.parse(
  //     '$baseUrl/resources/collections?resourceType=$resourceType',
  //   );
  //   try {
  //     final response = await http.get(
  //       uri,
  //       headers: {
  //         'X-App-ID': _appId, // CRITICAL: Must match the secret on Cloudflare
  //       },
  //     );

  //     if (response.statusCode == 200) {
  //       List<dynamic> collectionInfoList = json.decode(response.body);
  //       for (var collectionInfo in collectionInfoList) {
  //         if (collectionInfo is Map<String, dynamic> &&
  //             collectionInfo.containsKey('code')) {
  //           // get the collection info as our class, ResourceCollectionInfo
  //           final collection = await getResourceCollectionInfoFromAquifer(
  //             collectionInfo['code'],
  //           );
  //           if (collection != null) {
  //             collections.add(collection);
  //           }
  //         }
  //       }
  //     } else {
  //       debugPrint('Error: ${response.statusCode} - ${response.body}');
  //     }
  //   } catch (e) {
  //     debugPrint('Exception: $e');
  //   }
  //   return collections;
  // }

  Future<bool> checkConnectivity() async {
    try {
      // ignore: unused_local_variable
      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/resources/search?resourceType=StudyNotes&bookCode=GEN&startChapter=1&endChapter=1&languageCode=fra&limit=1',
            ),
            headers: {'X-App-ID': _appId},
          )
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

final List<AvailableLanguage> offlineAvailableLanguages = [
  AvailableLanguage(
    id: 4,
    code: 'fra',
    displayName: 'Français',
    scriptDirection: 'LTR',
  ),
  AvailableLanguage(
    id: 1,
    code: 'eng',
    displayName: 'English',
    scriptDirection: 'LTR',
  ),
];

final List<ResourceCollectionInfo> offlineResources = [
  ResourceCollectionInfo(
    code: 'TyndaleStudyNotes',
    resourceType: ResourceType.studyNotes,
    licenseInfo: offlineLicenseInfo,
    availableLanguages: offlineAvailableLanguages.toList(),
  ),
];

final List<String> targetedResources = [
  'TyndaleStudyNotes',
  'TyndaleStudyNotesBookIntros',
  'TyndaleStudyNotesThemes',
  'TyndaleStudyNotesProfiles',
  'BiblicaStudyNotes',
  'BiblicaStudyNotesBookIntros',
  'UbsImages',
];



  // Future<void> searchResources(String query) async {
  //   final uri = Uri.parse('$baseUrl/resources/search').replace(
  //     queryParameters: {
  //       'query': query,
  //       // Add other parameters as needed
  //     },
  //   );

  //   try {
  //     final response = await http.get(
  //       uri,
  //       headers: {
  //         'Content-Type': 'application/json',
  //         'X-App-ID': _appId, // CRITICAL: Must match the secret on Cloudflare
  //       },
  //     );

  //     if (response.statusCode == 200) {
  //       print('Data: ${response.body}');
  //     } else {
  //       print('Error: ${response.statusCode} - ${response.body}');
  //     }
  //   } catch (e) {
  //     print('Exception: $e');
  //   }
  // }