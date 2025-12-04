/// Please note that although ResourceLanguage and AvailableLanguage appear
/// very similar here, they come from different sources so should remain as
/// separate classes for conversion purposes and possible future changes.
///
/// these are languages in which Aquifer has resources
class ResourceLanguage {
  final int id; // e.g. 4
  final String code; // e.g. 'fra'
  final String
  localizedDisplay; // name of language in that language, e.g. 'Français'
  final String scriptDirection; // e.g. 'LTR'

  ResourceLanguage({
    required this.id,
    required this.code,
    required this.localizedDisplay,
    required this.scriptDirection,
  });

  factory ResourceLanguage.fromJson(Map<String, dynamic> json) {
    return ResourceLanguage(
      id: json['id'],
      code: json['code'],
      // sometimes localizedDisplay is empty, so use englishDisplay instead
      localizedDisplay: json['localizedDisplay'] == ''
          ? json['englishDisplay']
          : json['localizedDisplay'],
      scriptDirection: json['scriptDirection'],
    );
  }
}

/// these are languages in which a specific resource is available
class AvailableLanguage {
  final int id; // language id
  final String code; // language code
  final String displayName; // name of resource in that language
  final String scriptDirection; // language script direction

  AvailableLanguage({
    required this.id,
    required this.code,
    required this.displayName,
    this.scriptDirection = 'LTR',
  });

  factory AvailableLanguage.fromJson(Map<String, dynamic> json) {
    return AvailableLanguage(
      id: json['languageId'],
      code: json['languageCode'],
      displayName: json['displayName'],
      scriptDirection: json['scriptDirection'] ?? 'LTR',
    );
  }
}

enum ResourceType { studyNotes, images }

/// These are the study notes collections available with their language info
class ResourceCollectionInfo {
  final String code;
  final ResourceType resourceType;
  final LicenseInfo licenseInfo;
  final List<AvailableLanguage> availableLanguages;

  ResourceCollectionInfo({
    required this.code,
    required this.resourceType,
    required this.licenseInfo,
    required this.availableLanguages,
  });

  factory ResourceCollectionInfo.fromJson(Map<String, dynamic> json) {
    late LicenseInfo licenseInfo;
    late List<AvailableLanguage> availableLanguages;
    late ResourceType resourceType;
    try {
      licenseInfo = LicenseInfo.fromJson(json);
    } catch (e) {
      print('LicenseInfo.fromJson Exception: $e');
    }
    try {
      availableLanguages = (json['availableLanguages'] as List)
          .where((e) => (e['resourceItemCount'] as int) >= 50)
          .map((e) => AvailableLanguage.fromJson(e))
          .toList();
    } catch (e) {
      print('availableLanguagesException: $e');
      availableLanguages = [];
    }
    try {
      if (json['resourceType'] != null) {
        if (json['resourceType'] == 'StudyNotes') {
          resourceType = ResourceType.studyNotes;
        } else if (json['resourceType'] == 'Images') {
          resourceType = ResourceType.images;
        }
      }
    } catch (e) {
      print('resourceTypeException: $e');
      resourceType = ResourceType.studyNotes;
    }

    return ResourceCollectionInfo(
      code: json['code'],
      resourceType: resourceType,
      licenseInfo: licenseInfo,
      availableLanguages: availableLanguages,
    );
  }

  @override
  String toString() {
    return 'ResourceCollectionInfo(code: $code)';
  }
}

class LicenseInfo {
  final String code;
  final String dates;
  final String holderName;
  final String holderUrl;
  final String licenseName;
  final String licenseUrl;

  LicenseInfo({
    required this.code,
    required this.dates,
    required this.holderName,
    required this.holderUrl,
    required this.licenseName,
    required this.licenseUrl,
  });

  factory LicenseInfo.fromJson(Map<String, dynamic> json) {
    final licenseList = json['licenseInfo']['licenses'] as List;
    final firstLicense = licenseList.isNotEmpty ? licenseList[0] : {};
    final engLicense = firstLicense['eng'] ?? {};

    return LicenseInfo(
      code: json['code'],
      dates: json['licenseInfo']['copyright']['dates'] ?? '',
      holderName: json['licenseInfo']['copyright']['holder']['name'] ?? '',
      holderUrl: json['licenseInfo']['copyright']['holder']['url'] ?? '',
      licenseName: engLicense['name'] ?? '',
      licenseUrl: engLicense['url'] ?? '',
    );
  }
}
