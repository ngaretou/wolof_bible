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
