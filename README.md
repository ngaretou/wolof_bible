# wolof_bible

An extension of [Scripture App Builder](https://software.sil.org/scriptureappbuilder/) primarily for web apps that also can be used to produce offline Windows and macOS.

Demo of current version at http://app.kaddugyalla.com

<p align="center">
  <img src="https://github.com/ngaretou/wolof_bible/blob/main/screenshot.png">
  <br>
  <i>Screenshot of wolof_bible on a web browser</i>
</p>

### Running
use dart script @ `sfm_parser % dart run`
to pre-process SAB data into assets

### Updating offline resources: 
TyndaleStudyNotes
https://github.com/BibleAquifer/AquiferOpenStudyNotes/releases/
TyndaleStudyNotesBookIntros
https://github.com/BibleAquifer/AquiferOpenStudyNotesBookIntros/releases/

## To do:
### Minimal
- Audio tracking
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
* 2.1.0+22
   * Pre-processing: Removed identification markers in introductions
   * Included manual assets section in pubspec.yaml different from auto generated
   * Aquifer resources
* 2.1.0+23
   * Removed Swahili as it's experiencing problems on the Aquifer side
* 2.1.0+24
   * lots of logic refactoring to get the service and UI separated
* 2.1.0+25
   * many fluent_ui 4.14 breaking changes fixed
   * navigation problems especially dashed verses fixed
   * new book intro inline styles 
* 2.1.0+26
   * fixed an error where the online/offline resources were not integrating correctly on mac/ios/win apps
   * redid the teaching tip for the resource column button to appear on tap rather than automatic and to be a notification dot drawing the user
 * 2.1.0+27
   * Refreshed content and interface translations
   * Todo: fix windows simulscrolling
 * 2.1.1+28
   * Added S21
   * experimental book chooser
   * corrected some colors on the bulk verse copy copy helper icons
   * Refreshed offline aquifer content to 16 April 2026 versions
 * 2.1.2+29
   * Windows initialization problem fix 
   * Re-added Swahili language - although it seems like many books are missing notes 




## Todo
* Add Swahili back in

### Testing




## cache busting web release
(increment build number in pubspec.yaml)

```
rm -rf build/web
flutter build web
cd build/web
HASH=$(sha256sum main.dart.js | cut -c1-8)
mv main.dart.js main.dart.$HASH.js
sed -i .bak "s/main.dart.js/main.dart.$HASH.js/g" flutter_bootstrap.js 
rm flutter_bootstrap.js.bak 
```

<a title="Made with Windows Design" href="https://github.com/bdlukaa/fluent_ui">
  <img
    src="https://img.shields.io/badge/fluent-design-blue?style=flat-square&color=gray&labelColor=0078D7"
  />
</a>

sfm_parser/project/usfm_bible_data/books/C01,*.sfm