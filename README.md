# wolof_bible

An extension of [Scripture App Builder](https://software.sil.org/scriptureappbuilder/) primarily for web apps that also can be used to produce offline Windows and macOS.

Demo of current version at http://kaddugyalla.com/app

<p align="center">
  <img src="https://github.com/ngaretou/wolof_bible/blob/main/screenshot.png">
  <br>
  <i>Screenshot of wolof_bible on a web browser</i>
</p>


### Features
- Incorporates Changes from SAB project
  - (Not individual collection changes)
- Incorporates translations from SAB project
- Pulls in About pages - main About and the Copyright entry on each book section. 
  - To include book Copyright text in About page, use the %copyright-all:C01%, %copyright-all:C02% variables in the main project About section
- RTL text ready 
- Copy and Share context menu on right click
- Search by collection or all collections
- Dark/Light mode with quick switching
- Remembers user columns on subsequent opens
- For Wolof version has unique Wolof links on web
- For non web apps (Win/macOS/Android/iOS)
  - Remembers window position (Win/macOS)
  - Caches verses in a local db
- Example app with: 
  - Wolof full Bible
  - Wolof NT 2012
  <!-- - Wolof Ajami (Arabic script) full Bible -->
  - Louis Segond
  - Lexham English Bible
  - Society of Biblical Literature Greek NT

### Running
use dart script @ `sfm_parser % dart run`
to pre-process SAB data into assets

## To do:
### Minimal
- SBL/GNT word parsing under mouse-over

### Maximal
- Higher priority
  - NavPane buttons: Contact Us from appDef
- Other
  - Programmatically change permissions on files in project data folder to 744 when needed
  - Programmatically change font names
  - reader mode/no verses
  - read in styles from appdef
  - audio
  - Pass in ref via URL to go straight there? https://docs.flutter.dev/development/ui/navigation 

### Versions
* 2.0.0
  * new data pre-processing
  * new data structure
  * new indexed search
  * new copy and paste

* 2.0.1
  * Corrected translations
  * Corrected copy without numbers to work 
  * new icons for macos and ios
    * ios - transparent single size @ 1024 with the core image @ 63% for ios 18 - to test with 26
    * macos - made with iconcomposer for macos 15 - to test with 26
* 2.0.2
  * Added bulk verse copy
* 2.0.3
  * Correction of footnote problems
  * more new icons for ios
*  2.0.4
   * 'unfocus after input' after search and after bulk verse copy input
   * adapting bulk verse copy "ready to copy" user feedback to touch screen
   * pre-processing fixes for ~ as thousands separator
   * UI for bulk verse copy changes
* 2.0.5
   * fixed bug where poetry (i.e. multiline verses) wasn't handled correctly: refined selection logic & bulk verse copy logic & search logic along with pre-processing
   * refined selection logic - explictly clearing start/end points of selection on context menu tap to avoid unwanted anchoring of selection
   * fixed dashed verses not showing correctly in UI
   * added a new strict and fuzzy search capability
   * reporting how many results are found in search box 
   * for macOS, double clicking title bar goes 
   * consistent theming for license and bulk verse copy
 * 2.0.6
   * Pre-processing: Removed identification markers in introductions
   * Included manual assets section in pubspec.yaml different from auto generated
   * 



## Todo
translations for 
- context menu right click on contentTile
- Disconnect button on resource column
- Settings screen resource collections, suggested/default radio button
  - Also move that setting
- No resources found for this chapter to No resources to display and translations

## Web release
>>increment build number in pubspec.yaml
rm -rf build/web
flutter build web 
cd build/web
HASH=$(sha256sum main.dart.js | cut -c1-8)
mv main.dart.js main.dart.$HASH.js
sed -i .bak "s/main.dart.js/main.dart.$HASH.js/g" flutter_bootstrap.js 
rm flutter_bootstrap.js.bak 