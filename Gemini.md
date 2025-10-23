
## Phase 5: Copy-Paste Functionality & Text Selection (In Progress)

We've undertaken a significant refactoring and enhancement of the application's copy-paste and text selection features to improve user experience and leverage native Flutter capabilities.

### Key Accomplishments:

1.  **Stack Overflow Fix in `verse_composer.dart`:**
    *   **Problem:** Identified and resolved a stack overflow error in `lib/logic/verse_composer.dart`. The issue stemmed from an infinite recursion caused by `pairedUsfmFindingAndFormatting` incorrectly using `line.verseText` instead of its `text` parameter, combined with an overly broad backslash check in `addThisString` that triggered recursive calls on non-USFM backslashes (like `\u` sequences).
    *   **Solution:**
        *   Corrected `pairedUsfmFindingAndFormatting` to operate on its `text` parameter.
        *   Modified `addThisString` to prevent recursive calls when no `cleaningFunction` is provided, thus breaking the infinite loop.
        *   Ensured `dealtWithSoFar` was updated correctly in recursive contexts.

2.  **Transition to Native `SelectionArea`:**
    *   **Goal:** Replace the custom, user-unfriendly copy-paste system with Flutter's native `SelectionArea` for a more intuitive user experience.
    *   **Implementation:**
        *   Removed the `TapGestureRecognizer` from `TextSpan`s in `verse_composer.dart`, which was intercepting pointer events and preventing `SelectionArea` from functioning on the main text.
        *   Eliminated obsolete custom copy-paste logic (`rangeOfVersesToCopy` list, `addVerseToCopyRange` function, `textToShareOrCopy` function) from `lib/widgets/scripture_column.dart`.
        *   Removed the custom `ContextMenuRegion` from `lib/widgets/scripture_column.dart`, as `SelectionArea` provides its own native context menu.
        *   Cleaned up `lib/widgets/paragraph_builder.dart` by removing unused properties and logic related to the old selection system.

3.  **Enhanced "Copy Verses" Functionality:**
    *   **Goal:** Provide robust copy options that extract full verse text from the underlying data, even with partial user selections, and include/exclude verse numbers.
    *   **Implementation:**
        *   **Moved Superscript Utilities:** The `_sup` map and `toSuperscript` function were moved from `paragraph_builder.dart` to a new shared utility file: `lib/logic/text_utils.dart`. Both `paragraph_builder.dart` and `scripture_column.dart` were updated to import and use these utilities.
        *   **Refactored Reference Generation:** The `_getVerseReferenceForSelection` function in `scripture_column.dart` was refactored and renamed to `_getFormattedReferenceString`. It now accepts `ParsedLine` objects directly and is solely responsible for formatting the Bible reference string.
        *   **Accurate Verse Range Identification:** A new helper function, `_getVerseRangeFromSelection`, was added to `scripture_column.dart`. This function now intelligently identifies the `firstLine`, `lastLine`, and their corresponding `startFragment`/`endFragment` from the `_lastSelectedText`. It achieves this by splitting the selected text based on both superscripted verse numbers and artificial four-space indents, leading to more accurate matching of text fragments to `ParsedLine` objects.
        *   **Flexible Verse Composition:** A new helper function, `_composeVersesInRange`, was added to `scripture_column.dart`. This function takes the identified `firstLine`, `lastLine`, `startFragment`, `endFragment`, and a boolean `includeVerseNumbers`. It iterates through the `versesInMemory` within the range, composes the text for each verse (adjusting for partial selections using the fragments), and appends the formatted reference.
        *   **Updated Context Menu:** The `contextMenuBuilder` in `scripture_column.dart` was updated to offer two new `ContextMenuButtonItem`s: "Copy Verses (with numbers)" and "Copy Verses (without numbers)". These buttons utilize the new helper functions to provide the enhanced copy functionality.

### Current Status:

The copy-paste solution has been significantly refactored and enhanced. It now leverages Flutter's native `SelectionArea` for intuitive text selection and provides sophisticated options for copying verse ranges directly from the application's data, handling partial selections and formatting requirements.

### Next Steps:

The next crucial step is to thoroughly test the new copy-paste solution. This includes verifying its behavior across various selection scenarios:
*   Single verse selections (full and partial).
*   Multiple verse selections (full and partial).
*   Selections spanning across paragraph breaks.
*   Selections including/excluding artificial indents.
*   Testing both "with numbers" and "without numbers" options.
*   Confirming the accuracy of the generated Bible references.
