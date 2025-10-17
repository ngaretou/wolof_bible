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

## Phase 2: App-Side Services (Completed)

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

## Phase 3: UI and Navigation Refactor  (Completed)

We have completed a major refactoring of the main Bible view (`lib/widgets/scripture_column.dart`) to improve navigation precision and user experience.

### Verse-Level Precision in a Paragraph Layout  (Completed)

We now have the app able to scroll very precisely to a given verse and also to report to the UI the precise verse that is at the top of the screen. 

### Implemented Solution: The `TextPainter` Approach

We have successfully implemented the "identification" part of this solution.

1.  **`ParagraphBuilder` Refactor:** The `ParagraphBuilder` widget has been heavily modified. It now uses Flutter's `TextPainter` engine to perform a layout calculation in the background. This allows it to determine the exact `(x, y)` pixel offset of every verse within its rendered paragraph. This layout data is then passed up to the `ScriptureColumn` via a callback.

2.  **`ScriptureColumn` Refactor:** The `ScriptureColumn` widget now listens for scroll events using an `ItemPositionsListener`. On each scroll, it:
    *   Receives the layout data from the visible `ParagraphBuilder` children.
    *   Caches this data.
    *   Compares the current scroll offset with the cached verse-offset data to accurately determine which verse is at the very top of the viewport.

### Current Status & Next Steps

