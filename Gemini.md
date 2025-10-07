# Gemini Project Notes: Wolof Bible App

This document contains my notes and understanding of the Wolof Bible Flutter project.

## Project Overview

The project is a Flutter application for reading the Bible in Wolof. It appears to be a multi-platform app targeting Android, iOS, macOS, Windows, and web.

### Key Files & Directories

-   `pubspec.yaml`: Defines project dependencies, including `provider`, `hive`, `xml`, and `package_info_plus`.
-   `sfm_parser/project/appDef.appDef`: An XML file that acts as the main configuration for the app's content. It defines:
    -   Book collections (e.g., Old Testament, New Testament).
    -   Individual books within each collection, including their ID, name, and the filename of the source data.
    -   Font definitions.
    -   UI translations for different languages.
-   `sfm_parser/project/data/books/`: Contains the scripture data in what appears to be a USFM-like format, organized into subdirectories for each collection.
-   `lib/logic/database_builder.dart`: This is the core of the current data loading and parsing logic.
-   `lib/logic/verse_composer.dart`: This file is responsible for formatting the parsed verse data into rich text for display, handling USFM markers for styling and features like footnotes.
-   `lib/hive/`: Contains the Hive database models for caching parsed data.

## Current Data Flow (To Be Replaced)

1.  **Initialization (`buildDatabaseFromXML`)**: On app startup, the `buildDatabaseFromXML` function in `database_builder.dart` is called.
2.  **XML Parsing**: It reads and parses `assets/project/appDef.appDef` to get the structure of the bible collections and books.
3.  **Caching Check**: It checks if a local Hive database (`parsedLineDB`) exists and is up-to-date by comparing build numbers.
4.  **SFM Parsing (if needed)**: If the cache is stale or absent, it iterates through every book defined in the XML, reads the corresponding SFM file from the `assets` directory, and parses it line by line.
5.  **Object Creation**: Each parsed line (verse, heading, etc.) is converted into a `ParsedLine` object.
6.  **Database Caching**: The entire list of `ParsedLine` objects is saved to the Hive box for future app loads.
7.  **In-Memory Loading**: The `ParsedLine` objects are loaded into a global `verses` list for the app to use.

**Problem**: This process is inefficient. Parsing dozens of text files and populating a database on the first app run can cause a significant startup delay.

## Refactoring Plan

The goal is to move the data parsing to a pre-processing step during development.

1.  **New Pre-processing Project (`sfm_parser`)**: A new Dart project has been created in the `sfm_parser/` directory. This project is responsible for the SFM to JSON conversion.
2.  **SFM to JSON Conversion**: This new project will read the `appDef.appDef` and all the SFM files and convert them into a structured JSON format.
    -   **JSON Structure Idea**: A good approach would be to create one JSON file per chapter (e.g., `data/json/C01/GEN/1.json`). This will allow for small, individual file downloads. The JSON can contain a list of verse objects, with properties for verse number, text, and style markers.
    -   The filenames will be three digits - 001.json, 002.json, etc. 
3.  **Dynamic Lazy Loading in Flutter**: The Flutter app will be modified to:
    -   No longer parse SFM files at runtime.
    -   Read the pre-processed JSON files from its assets.
    -   Load data "lazily" or "in chunks." When the user navigates to a specific chapter, the app will load only the corresponding JSON file for that chapter, instead of loading the entire Bible into memory at once.

This will result in a much faster app startup and more efficient memory usage. The `verse_composer.dart` logic will still be relevant for rendering the text from the loaded JSON data.
