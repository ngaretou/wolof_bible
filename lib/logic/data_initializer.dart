import 'dart:convert';
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

  Collection({
    required this.id,
    required this.name,
    required this.abbreviation,
    required this.fonts,
    required this.books,
    required this.textDirection,
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

  Translation(
      {required this.langCode,
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
      required this.share});
}

List<Collection> collections = [];
// List<ParsedLine> verses = [];
List<Font> allFonts = [];
List<Translation> translations = [];

Future<String> asyncGetProjectName(BuildContext context) async {
  AssetBundle assetBundle = DefaultAssetBundle.of(context);

  //get the appDef xml from outside the flutter project
  String appDefLocation = 'assets/json/appDef.appDef';
  String xmlFileString = await assetBundle.loadString(appDefLocation);
  //get the document into a usable iterable
  final document = XmlDocument.parse(xmlFileString);
  //This is the overall app name
  final projectName = document
      .getElement('app-definition')!
      .getElement('app-name')!
      .innerText
      .toString(); // e.g. Kaddug Yalla
  return projectName;
}

Future<void> asyncGetTranslations(BuildContext context) async {
  //Stuff for supplemental translations
  Map<String, String> translationSupplement = {};
  AssetBundle assetBundle = DefaultAssetBundle.of(context);
  UserPrefs userPrefs = Provider.of<UserPrefs>(context, listen: false);
  String translationsJSON =
      await rootBundle.loadString("assets/translations.json");
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
        langInfo.addAll(
            {langForm.getAttribute('lang').toString(): langForm.innerText});
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
              (element) => element.getAttribute('lang').toString() == langCode);
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
              (element) => element.getAttribute('lang').toString() == langCode);
      String settingsText = settingsTextXml.first.innerText;

      Iterable<XmlElement> settingsInterfaceLanguageTextXml = document
          .getElement('app-definition')!
          .getElement('translation-mappings')!
          .findAllElements('translation-mapping')
          .where((element) =>
              element.getAttribute('id') == 'Settings_Interface_Language')
          .first
          .findAllElements('translation')
          .toList()
          .where(
              (element) => element.getAttribute('lang').toString() == langCode);
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
              (element) => element.getAttribute('lang').toString() == langCode);
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
              (element) => element.getAttribute('lang').toString() == langCode);
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
              (element) => element.getAttribute('lang').toString() == langCode);
      String shareText = shareTextXml.first.innerText;

      // ----
      //Now get supplemental translations
      translationSupplement = {};
      for (var translation in translationData) {
        if (translation['langCode'] == langCode) {
          translationSupplement.addAll({
            'langCode': translation['langCode'],
            "addColumn": translation['addColumn'],
            "settingsTheme": translation['settingsTheme'],
            "systemTheme": translation['systemTheme'],
            "lightTheme": translation['lightTheme'],
            "darkTheme": translation['darkTheme'],
          });
        }
      }
      // ----

      translations.add(Translation(
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
          share: shareText));
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
    BuildContext context, Function updater) async {
  AssetBundle assetBundle = DefaultAssetBundle.of(context);

  String appDefLocation = 'assets/json/appDef.appDef';
  String xmlFileString = await assetBundle.loadString(appDefLocation);
  //get the document into a usable iterable
  final document = XmlDocument.parse(xmlFileString);

  //Get the font information
  String fontWeight = "";
  String fontStyle = "";

  XmlElement? xmlFontsSection =
      document.getElement('app-definition')!.getElement('fonts');
  if (xmlFontsSection != null) {
    Iterable<XmlElement> xmlFonts = xmlFontsSection.findAllElements('font');
    //Loop through fonts gathering info about each
    for (var xmlFont in xmlFonts) {
      Iterable<XmlElement> xmlFontProperties =
          xmlFont.findAllElements('style-decl');

      for (var xmlFontProperty in xmlFontProperties) {
        //the font weight and style are a bit different, they are in the same kind of xml tag,
        //so we have to get them both out here and save them for the add to list
        String property = xmlFontProperty.getAttribute('property').toString();
        String value = xmlFontProperty.getAttribute('value').toString();
        if (property == 'font-weight') fontWeight = value;
        if (property == 'font-style') fontStyle = value;
      }

      allFonts.add(Font(
          fontFamily: xmlFont.getAttribute('family').toString(),
          fontName: xmlFont.getElement('font-name')!.innerText.toString(),
          displayName: xmlFont.getElement('font-name')!.innerText.toString(),
          filename: xmlFont.getElement('filename')!.innerText.toString(),
          weight: fontWeight,
          style: fontStyle));
    }
  }

  //Get Changes
  Map<String, String> changes = {};
  Iterable<XmlElement> xmlChanges = document
      .getElement('app-definition')!
      .getElement('changes')!
      .findAllElements('change');

  for (var xmlChange in xmlChanges) {
    changes.addAll({
      xmlChange.getElement('find')!.innerText.toString():
          xmlChange.getElement('replace')!.innerText.toString()
    });
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
      books.add(Book(
        id: xmlBook.getAttribute('id').toString(),
        name: xmlBook.getElement('name')!.innerText.toString(),
      ));
    }

    //Now put it all together
    collections.add(Collection(
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
            .where((element) =>
                element.fontFamily ==
                xmlCollection
                    .getElement('styles-info')!
                    .getElement('text-font')!
                    .getAttribute('family'))
            .toList(),
        books: books,
        textDirection: xmlCollection
            .getElement('styles-info')!
            .getElement('text-direction')!
            .getAttribute('value')
            .toString()));
  }

  // print('now we have the collections info');

  for (double i = 0; i < 100; i++) {
    // TODO come back to this - what does this do?
    updater(i);
  }

  return collections;
}
