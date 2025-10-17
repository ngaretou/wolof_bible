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

## Phase 3: UI and Navigation Refactor (Completed)

We have completed a major refactoring of the main Bible view (`lib/widgets/scripture_column.dart`) to improve navigation precision and user experience.

### Verse-Level Precision in a Paragraph Layout (Completed)

The app can now scroll very precisely to a given verse and also report to the UI the precise verse that is at the top of the screen. This was achieved using Flutter's `TextPainter` engine to calculate the exact pixel offset of every verse within its rendered paragraph.

### Final Fix (Scrolling)
Resolved a race condition that occurred when scrolling to a verse immediately after changing Bible collections. The fix implements a two-step scroll: an initial coarse jump to the target paragraph to get it into view, followed by a fine-grained adjustment to the precise verse offset once the `ParagraphBuilder`'s layout data becomes available. This ensures scrolling is reliable across the entire app.

## Phase 4: Search Implementation (Completed)

We have integrated the powerful, index-based `SearchService` into the main application UI.

### Key Accomplishments:

1.  **`SearchService` Refactor:** The service was updated to return a `Stream<SearchResult>` instead of a `Future`, allowing the UI to display results incrementally as they are found and processed. This makes the search feel much more responsive.

2.  **Data Model Correction:** Identified and fixed a bug in the data loading logic where the `Collection` class was missing a `language` property. This property is critical for the `SearchService` to apply the correct text processing rules (e.g., stemming). The data model and XML parsing logic in `data_initializer.dart` have been updated to include this.

3.  **UI (`SearchWidget`) Overhaul:**
    - The widget was completely refactored to use a modern, reactive `StreamBuilder` pattern.
    - Added the `rxdart` package to transform the stream of individual results into a stream of lists (`Stream<List<SearchResult>>`), which is the idiomatic way to feed a `StreamBuilder` that builds a list.
    - The `verseComposer` utility is now used to clean and format the raw search result text before it's displayed, removing any leftover USFM markers.

4.  **Bug Fix (Stale State):** Fixed a subtle but critical bug where old search results would persist if a new search yielded no results. This was traced to `StreamBuilder`'s default behavior of retaining old data. The fix was to assign a `UniqueKey` to the `StreamBuilder` on each new search, forcing it to completely reset its state and correctly display the "No results found" message.

### Current Status
The search functionality is now complete and robust. The user is restarting the app to verify the latest fix.