# Audio Highlight Implementation Strategy

**Status:** Planned for future implementation
**Goal:** Highlight the currently playing text span without breaking native `SelectionArea` copy-paste functionality.

## Core Problem
`TextSpan` is a data object, not a Widget, so it cannot independently react to a Provider change using `Consumer` or `context.watch`. Wrapping the span in a `WidgetSpan` containing a `Consumer` breaks Flutter's `SelectionArea` copy-paste functionality.

## Solution Architecture
The standard and robust approach is to rebuild the parent widget (`ParagraphBuilder`) that constructs the `TextSpan`s when the audio position updates.

### Step 1: Update `verseComposer`
Add an `isHighlighted` parameter. If true, apply a background color (e.g., `FluentTheme.of(context!).accentColor.withOpacity(0.3)`) to the existing `computedTextStyle`.

### Step 2: Track Provider State in `ParagraphBuilder`
In `_ParagraphBuilderState.didChangeDependencies()`, watch the future `AudioProvider`.
Maintain a `_currentlyPlayingVerseId` state variable.
If the active verse ID changes, call `_prepareSpans()` to rebuild the cached `TextSpan` tree. This avoids rebuilding on every frame of audio, only when the active verse changes.

### Step 3: Pass State during Span Preparation
Inside `_prepareSpans()`, update the `processLine` helper.
Check if the current `ParsedLine` matches the `_currentlyPlayingVerseId`.
Pass the boolean result to `verseComposer(isHighlighted: ...)`.

## Open Questions
- Exact data structure the AudioPlayer will emit (e.g., `collectionid` + `book` + `chapter` + `verse` string vs timing offsets). The `isHighlighted` match logic in `processLine` will need to be adapted once this is known.
