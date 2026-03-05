import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../providers/user_prefs.dart';
import 'package:xml/xml.dart';
import 'package:flutter/services.dart' show rootBundle;

class Font {
  final String fontFamily;
  final String fontName;
  final String displayName;
  final String filename;
  final String weight;
  final String style;

  Font({
    required this.fontFamily,
    required this.fontName,
    required this.displayName,
    required this.filename,
    required this.weight,
    required this.style,
  });
}

class Book {
  final String id;
  final String name;
  // final String filename;
  // final String source;

  Book({
    required this.id,
    required this.name,
    // required this.filename,
    // required this.source,
  });
}

class Collection {
  final String id;
  final String name;
  final String abbreviation;
  final List<Book> books;
  final List<Font> fonts;
  final String textDirection;
  final String language;

  Collection({
    required this.id,
    required this.name,
    required this.abbreviation,
    required this.fonts,
    required this.books,
    required this.textDirection,
    required this.language,
  });
}

class ParsedLine {
  // late int id;
  late String collectionid;
  late String book;
  late String chapter;
  late String verse;
  late String verseFragment;
  late String audioMarker;
  late String verseText;
  late String verseStyle;
  // late bool newParagraph;

  ParsedLine({
    // required this.id,
    required this.collectionid,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.verseFragment,
    required this.audioMarker,
    required this.verseText,
    required this.verseStyle,
    // required this.newParagraph,
  });

  @override
  String toString() {
    return 'ParsedLine('
        'collectionid: $collectionid, '
        'book: $book, '
        'chapter: $chapter, '
        'verse: $verse, '
        'verseText: $verseText, '
        'verseStyle: $verseStyle, '
        ')';
  }
}

// class AppInfo {
//   List<Collection> collections;
//   // List<ParsedLine> verses;

//   AppInfo({
//     required this.collections,
//     // required this.verses,
//   });
// }

class Translation {
  String langCode;
  String langName;
  String search;
  String addColumn;
  String settingsTheme;
  String systemTheme;
  String lightTheme;
  String darkTheme;
  String about;
  String settings;
  String settingsInterfaceLanguage;
  String copy;
  String share;
  String copyWithNumbers;
  String copyWithoutNumbers;
  String strictSearch;
  String fuzzySearch;
  String openResourceColumn;
  String goOnline;
  String goOffline;
  String copyNote;
  String resourceCollections;
  String viewSuggestedCollections;
  String viewAllCollections;
  String bulkVerseCopy;
  String instructions;
  String bulkVerseCopyInstructions;
  String close;
  String seeAllAbbreviations;
  String chooseBible;
  String includeVerseNumbers;
  String abbreviations;
  String ok;
  String couldNotParse;
  String downloadApp;
  String moreApps;
  String newStudyNotes;
  String newStudyNotesSub;
  String noInternet;
  String timeout;
  String switchingToOfflineMode;
  String resetUserSettings;

  Translation({
    required this.langCode,
    required this.langName,
    required this.search,
    required this.addColumn,
    required this.settingsTheme,
    required this.systemTheme,
    required this.lightTheme,
    required this.darkTheme,
    required this.about,
    required this.settings,
    required this.settingsInterfaceLanguage,
    required this.copy,
    required this.share,
    required this.copyWithNumbers,
    required this.copyWithoutNumbers,
    required this.strictSearch,
    required this.fuzzySearch,
    required this.openResourceColumn,
    required this.goOnline,
    required this.goOffline,
    required this.copyNote,
    required this.resourceCollections,
    required this.viewSuggestedCollections,
    required this.viewAllCollections,
    required this.bulkVerseCopy,
    required this.instructions,
    required this.bulkVerseCopyInstructions,
    required this.close,
    required this.seeAllAbbreviations,
    required this.chooseBible,
    required this.includeVerseNumbers,
    required this.abbreviations,
    required this.ok,
    required this.couldNotParse,
    required this.downloadApp,
    required this.moreApps,
    required this.newStudyNotes,
    required this.newStudyNotesSub,
    required this.noInternet,
    required this.timeout,
    required this.switchingToOfflineMode,
    required this.resetUserSettings,
  });
}

List<Collection> collections = [];
// List<ParsedLine> verses = [];
List<Font> allFonts = [];
List<Translation> translations = [];

Future<void> asyncGetTranslations(BuildContext context) async {
  //Stuff for supplemental translations
  Map<String, String> translationSupplement = {};
  AssetBundle assetBundle = DefaultAssetBundle.of(context);
  UserPrefs userPrefs = Provider.of<UserPrefs>(context, listen: false);
  String translationsJSON = await rootBundle.loadString(
    "assets/translations.json",
  );
  final translationData = json.decode(translationsJSON) as List<dynamic>;

  //get the appDef xml from outside the flutter project
  String appDefLocation = 'assets/json/appDef.appDef';
  String xmlFileString = await assetBundle.loadString(appDefLocation);
  //get the document into a usable iterable
  final document = XmlDocument.parse(xmlFileString);

  String initialLang = document
      .getElement('app-definition')!
      .getElement('translation-mappings')!
      .getAttribute('default-lang')
      .toString(); // e.g. 'en'

  Iterable<XmlElement> xmlLangs = document
      .getElement('app-definition')!
      .getElement('interface-languages')!
      .getElement('writing-systems')!
      .findAllElements('writing-system');
  //Loop through langs gathering info about each
  for (var lang in xmlLangs) {
    String? enabled = lang.getAttribute('enabled')?.toString();

    if (enabled != 'false') {
      String langCode = lang.getAttribute('code').toString();
      late String langName;
      XmlElement? displayNames = lang.getElement('display-names');
      Iterable<XmlElement> langForms = displayNames!.findAllElements('form');

      Map<String, String> langInfo = {};
      for (var langForm in langForms) {
        langInfo.addAll({
          langForm.getAttribute('lang').toString(): langForm.innerText,
        });
      }
      if (langInfo.keys.contains(langCode)) {
        langName = langInfo[langCode].toString();
      } else {
        langName = langInfo['en'].toString();
      }

      Iterable<XmlElement> searchTextXML = document
          .getElement('app-definition')!
          .getElement('translation-mappings')!
          .findAllElements('translation-mapping')
          .where((element) => element.getAttribute('id') == 'Search')
          .first
          .findAllElements('translation')
          .toList()
          .where(
            (element) => element.getAttribute('lang').toString() == langCode,
          );
      String searchText = searchTextXML.first.innerText;

      Iterable<XmlElement> settingsTextXml = document
          .getElement('app-definition')!
          .getElement('translation-mappings')!
          .findAllElements('translation-mapping')
          .where((element) => element.getAttribute('id') == 'Settings_Title')
          .first
          .findAllElements('translation')
          .toList()
          .where(
            (element) => element.getAttribute('lang').toString() == langCode,
          );
      String settingsText = settingsTextXml.first.innerText;

      Iterable<XmlElement> settingsInterfaceLanguageTextXml = document
          .getElement('app-definition')!
          .getElement('translation-mappings')!
          .findAllElements('translation-mapping')
          .where(
            (element) =>
                element.getAttribute('id') == 'Settings_Interface_Language',
          )
          .first
          .findAllElements('translation')
          .toList()
          .where(
            (element) => element.getAttribute('lang').toString() == langCode,
          );
      String settingsInterfaceLanguageText =
          settingsInterfaceLanguageTextXml.first.innerText;

      Iterable<XmlElement> aboutTextXml = document
          .getElement('app-definition')!
          .getElement('translation-mappings')!
          .findAllElements('translation-mapping')
          .where((element) => element.getAttribute('id') == 'Menu_About')
          .first
          .findAllElements('translation')
          .toList()
          .where(
            (element) => element.getAttribute('lang').toString() == langCode,
          );
      String aboutText = aboutTextXml.first.innerText;

      Iterable<XmlElement> copyTextXml = document
          .getElement('app-definition')!
          .getElement('translation-mappings')!
          .findAllElements('translation-mapping')
          .where((element) => element.getAttribute('id') == 'Menu_Item_Copy')
          .first
          .findAllElements('translation')
          .toList()
          .where(
            (element) => element.getAttribute('lang').toString() == langCode,
          );
      String copyText = copyTextXml.first.innerText;

      Iterable<XmlElement> shareTextXml = document
          .getElement('app-definition')!
          .getElement('translation-mappings')!
          .findAllElements('translation-mapping')
          .where((element) => element.getAttribute('id') == 'Menu_Item_Share')
          .first
          .findAllElements('translation')
          .toList()
          .where(
            (element) => element.getAttribute('lang').toString() == langCode,
          );
      String shareText = shareTextXml.first.innerText;

      // ----
      //Now get supplemental translations
      translationSupplement = {};
      for (var translation in translationData) {
        if (translation['langCode'] == langCode) {
          try {
            translationSupplement.addAll({
              'langCode': translation['langCode'],
              "addColumn": translation['addColumn'],
              "settingsTheme": translation['settingsTheme'],
              "systemTheme": translation['systemTheme'],
              "lightTheme": translation['lightTheme'],
              "darkTheme": translation['darkTheme'],
              "copyWithNumbers": translation['copyWithNumbers'],
              "copyWithoutNumbers": translation['copyWithoutNumbers'],
              "strictSearch": translation['strictSearch'],
              "fuzzySearch": translation['fuzzySearch'],
              "openResourceColumn": translation['openResourceColumn'],
              "goOnline": translation['goOnline'],
              "goOffline": translation['goOffline'],
              "copyNote": translation['copyNote'],
              "resourceCollections": translation['resourceCollections'],
              "viewSuggestedCollections":
                  translation['viewSuggestedCollections'],
              "viewAllCollections": translation['viewAllCollections'],
              "bulkVerseCopy": translation['bulkVerseCopy'],
              "instructions": translation['instructions'],
              "bulkVerseCopyInstructions":
                  translation['bulkVerseCopyInstructions'],
              "close": translation['close'],
              "seeAllAbbreviations": translation['seeAllAbbreviations'],
              "chooseBible": translation['chooseBible'],
              "includeVerseNumbers": translation['includeVerseNumbers'],
              "abbreviations": translation['abbreviations'],
              "ok": translation['ok'],
              "couldNotParse": translation['couldNotParse'],
              "downloadApp": translation['downloadApp'],
              "moreApps": translation['moreApps'],
              "newStudyNotes": translation['newStudyNotes'],
              "newStudyNotesSub": translation['newStudyNotesSub'],
              "noInternet": translation['noInternet'],
              "timeout": translation['timeout'],
              "switchingToOfflineMode": translation['switchingToOfflineMode'],
              "resetUserSettings": translation['resetUserSettings'],
            });
          } catch (e) {
            debugPrint('Error adding translation supplement: ${e.toString()}');
          }
        }
      }
      // ----
      try {
        translations.add(
          Translation(
            langCode: langCode,
            langName: langName,
            search: searchText,
            addColumn: translationSupplement['addColumn']!,
            settingsTheme: translationSupplement['settingsTheme']!,
            systemTheme: translationSupplement['systemTheme']!,
            lightTheme: translationSupplement['lightTheme']!,
            darkTheme: translationSupplement['darkTheme']!,
            about: aboutText,
            settings: settingsText,
            settingsInterfaceLanguage: settingsInterfaceLanguageText,
            copy: copyText,
            share: shareText,
            copyWithNumbers: translationSupplement['copyWithNumbers']!,
            copyWithoutNumbers: translationSupplement['copyWithoutNumbers']!,
            strictSearch: translationSupplement['strictSearch']!,
            fuzzySearch: translationSupplement['fuzzySearch']!,
            openResourceColumn: translationSupplement['openResourceColumn']!,
            goOnline: translationSupplement['goOnline']!,
            goOffline: translationSupplement['goOffline']!,
            copyNote: translationSupplement['copyNote']!,
            resourceCollections: translationSupplement['resourceCollections']!,
            viewSuggestedCollections:
                translationSupplement['viewSuggestedCollections']!,
            viewAllCollections: translationSupplement['viewAllCollections']!,
            bulkVerseCopy: translationSupplement['bulkVerseCopy']!,
            instructions: translationSupplement['instructions']!,
            bulkVerseCopyInstructions:
                translationSupplement['bulkVerseCopyInstructions']!,
            close: translationSupplement['close']!,
            seeAllAbbreviations: translationSupplement['seeAllAbbreviations']!,
            chooseBible: translationSupplement['chooseBible']!,
            includeVerseNumbers: translationSupplement['includeVerseNumbers']!,
            abbreviations: translationSupplement['abbreviations']!,
            ok: translationSupplement['ok']!,
            couldNotParse: translationSupplement['couldNotParse']!,
            downloadApp: translationSupplement['downloadApp']!,
            moreApps: translationSupplement['moreApps']!,
            newStudyNotes: translationSupplement['newStudyNotes']!,
            newStudyNotesSub: translationSupplement['newStudyNotesSub']!,
            noInternet: translationSupplement['noInternet']!,
            timeout: translationSupplement['timeout']!,
            switchingToOfflineMode:
                translationSupplement['switchingToOfflineMode']!,
            resetUserSettings: translationSupplement['resetUserSettings']!,
          ),
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint(e.toString());
        }
      }
    }
  }

  String? savedUserLang = userPrefsBox.get('savedUserLang');
  if (savedUserLang == null) {
    userPrefs.setUserLang = initialLang;
    userPrefsBox.put('savedUserLang', initialLang);
  } else {
    userPrefs.setUserLang = savedUserLang;
  }
}

// Future<void> saveToLocalDB(List<ParsedLine> verses) async {
//   //Hopefully without detaining the user save locally the resulting List<ParsedLine>
//   // print('starting to save parsed lines to box');
//   Box<ParsedLineDB> versesBox =
//       await Hive.openBox<ParsedLineDB>('parsedLineDB');

//   for (var i = 0; i < verses.length; i++) {
//     ParsedLineDB parsedLineDB = ParsedLineDB()
//       ..collectionid = verses[i].collectionid
//       ..book = verses[i].book
//       ..chapter = verses[i].chapter
//       ..verse = verses[i].verse
//       ..verseFragment = verses[i].verseFragment
//       ..audioMarker = verses[i].audioMarker
//       ..verseText = verses[i].verseText
//       ..verseStyle = verses[i].verseStyle;

//     versesBox.add(parsedLineDB);
//   }

//   // print('finished saving parsed lines to box');
//   // print(versesBox.length);
//   return;
// }

Future<List<Collection>> collectionsFromXML(
  BuildContext context,
  Function updater,
) async {
  AssetBundle assetBundle = DefaultAssetBundle.of(context);

  String appDefLocation = 'assets/json/appDef.appDef';
  String xmlFileString = await assetBundle.loadString(appDefLocation);
  //get the document into a usable iterable
  final document = XmlDocument.parse(xmlFileString);

  final defaultLang =
      document
          .getElement('app-definition')!
          .getElement('translation-mappings')
          ?.getAttribute('default-lang') ??
      'en';

  //Get the font information
  String fontWeight = "";
  String fontStyle = "";

  XmlElement? xmlFontsSection = document
      .getElement('app-definition')!
      .getElement('fonts');
  if (xmlFontsSection != null) {
    Iterable<XmlElement> xmlFonts = xmlFontsSection.findAllElements('font');
    //Loop through fonts gathering info about each
    for (var xmlFont in xmlFonts) {
      Iterable<XmlElement> xmlFontProperties = xmlFont.findAllElements(
        'style-decl',
      );

      for (var xmlFontProperty in xmlFontProperties) {
        //the font weight and style are a bit different, they are in the same kind of xml tag,
        //so we have to get them both out here and save them for the add to list
        String property = xmlFontProperty.getAttribute('property').toString();
        String value = xmlFontProperty.getAttribute('value').toString();
        if (property == 'font-weight') fontWeight = value;
        if (property == 'font-style') fontStyle = value;
      }

      allFonts.add(
        Font(
          fontFamily: xmlFont.getAttribute('family').toString(),
          fontName: xmlFont.getElement('font-name')!.innerText.toString(),
          displayName: xmlFont.getElement('font-name')!.innerText.toString(),
          filename: xmlFont.getElement('filename')!.innerText.toString(),
          weight: fontWeight,
          style: fontStyle,
        ),
      );
    }
  }

  //Get each collection's information
  final Iterable<XmlElement> xmlCollections = document.findAllElements('books');
  for (var xmlCollection in xmlCollections) {
    //holder for the Book list
    List<Book> books = [];

    //now get the collection's book information
    Iterable<XmlElement> xmlBookList = xmlCollection.findAllElements('book');
    for (var xmlBook in xmlBookList) {
      //Add the book
      books.add(
        Book(
          id: xmlBook.getAttribute('id').toString(),
          name: xmlBook.getElement('name')!.innerText.toString(),
        ),
      );
    }

    //Now put it all together
    collections.add(
      Collection(
        id: xmlCollection.getAttribute('id').toString(),
        name: xmlCollection
            .getElement('book-collection-name')!
            .innerText
            .toString(),
        abbreviation: xmlCollection
            .getElement('book-collection-abbrev')!
            .innerText
            .toString(),
        fonts: allFonts
            .where(
              (element) =>
                  element.fontFamily ==
                  xmlCollection
                      .getElement('styles-info')!
                      .getElement('text-font')!
                      .getAttribute('family'),
            )
            .toList(),
        books: books,
        language:
            xmlCollection.getElement('writing-system')?.getAttribute('code') ??
            defaultLang,
        textDirection: xmlCollection
            .getElement('styles-info')!
            .getElement('text-direction')!
            .getAttribute('value')
            .toString(),
      ),
    );
  }

  // print('now we have the collections info');

  for (double i = 0; i < 100; i++) {
    updater(i);
  }

  return collections;
}
