# Gemini Project Notes: Wolof Bible App

This document contains my notes and understanding of the Wolof Bible Flutter project.

## Project Overview

The project is a Flutter application for reading the Bible in Wolof. It appears to be a multi-platform app targeting Android, iOS, macOS, Windows, and web.

---

## Phase 1: Pre-processing (Completed)

We created a comprehensive Dart script in the `sfm_parser/` directory to pre-process all Bible data. This script is the new foundation for the app's data handling.

**Key Accomplishments:**

1.  **JSON Chapter Generation:** The script parses the original USFM-like source files and generates a separate, clean JSON file for each chapter of each book (e.g., `assets/json/C01/GEN/1.json`).

2.  **Table of Contents (TOC):** For each Bible collection, a `_toc.json` file is created. This file acts as a map of the collection, detailing the books it contains and the number of chapters in each, which is essential for navigation.

3.  **Search Indexing:** We built a sophisticated, language-aware search index. 
    - It creates an inverted index to allow for fast, client-side text searches.
    - It processes English and French text with advanced stemming and stop-word removal.
    - To keep downloads small, the index for each collection is partitioned into 26 smaller files, one for each letter of the alphabet (e.g., `assets/json/C01/index/a.json`).

4.  **Dynamic Asset Declaration:** To solve issues with Flutter finding the generated assets, the parser script now automatically updates the main `pubspec.yaml` file, explicitly adding a directory entry for every folder it creates. This is the most reliable method for ensuring assets are bundled.

## Phase 2: App-Side Services (In Progress)

With the data pre-processed, we are now building the services within the Flutter app to consume it.

**Services Created:**

1.  **`ChapterFetchService` (`lib/logic/chapter_fetch_service.dart`):**
    -   **Purpose:** To load chapter data on demand, making the app lightweight.
    -   **Functionality:** It can fetch an initial chunk of data (e.g., a chapter plus the ones immediately before and after) and subsequently fetch the next or previous chapters as the user scrolls. It intelligently handles moving across book boundaries and signals to the UI when the beginning or end of the Bible is reached.

2.  **`SearchService` (`lib/logic/search_service.dart`):**
    -   **Purpose:** To perform efficient, client-side searches using the pre-generated index files.
    -   **Functionality:** It takes a search query, processes it using the same language rules as the indexer (stemming, etc.), and downloads only the small, relevant index shards (e.g., `p.json` for a search of "Paul"). It then finds verses where all search terms appear, and efficiently fetches the verse text from the chapter JSON files to display results.

3.  **`TextProcessor` (`lib/logic/text_processor.dart`):**
    -   A utility created to ensure that search queries in the app are processed with the exact same language rules (stemming, stop-words) that were used to create the search index.

## Current Status & Next Steps

-   **Last Action:** We implemented the logic for the `sfm_parser` script to automatically update the `pubspec.yaml` file. This is intended to be the definitive fix for the "Asset does not exist" error.
-   **Immediate Next Step:** The user needs to run the `sfm_parser` script one more time. After it completes, they must perform a **full stop and restart** of the Flutter application to ensure the newly declared assets in `pubspec.yaml` are correctly bundled by the build tools.
-   **Next Major Goal:** Once the asset loading is confirmed to be working, the next step will be to integrate the new `ChapterFetchService` and `SearchService` into the app's UI widgets to replace the old data handling logic.