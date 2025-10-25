import 'dart:ui' as ui;
import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:collection/collection.dart';

import '../logic/data_initializer.dart';
import '../logic/chapter_fetch_service.dart';
import '../logic/verse_composer.dart';
import '../logic/text_utils.dart';
import '../logic/touch_media.dart';

import '../providers/column_manager.dart';
import '../providers/user_prefs.dart';

import '../widgets/paragraph_builder.dart';
import '../widgets/user_interaction.dart';

class ScriptureColumn extends StatefulWidget {
  final int myColumnIndex;
  final List<Collection> collections;
  final BibleReference bibleReference;
  final Function deleteColumn;
  final String? comboBoxFont;

  const ScriptureColumn({
    required super.key,
    required this.myColumnIndex,
    required this.collections,
    required this.bibleReference,
    required this.deleteColumn,
    this.comboBoxFont,
  });

  @override
  State<ScriptureColumn> createState() => _ScriptureColumnState();
}

class _ScriptureColumnState extends State<ScriptureColumn> {
  String _lastSelectedText = '';
  bool _isScrolling = false;

  // for copy/paste
  Offset? dragStartOffset;
  Offset? dragEndOffset;
  ParsedLine? copyStartLine;
  ParsedLine? copyEndLine;
  int? buttonPressed;
  late bool isTouch;

  late ItemScrollController itemScrollController;
  late ScrollGroup _scrollGroup;

  @override
  void dispose() {
    _scrollGroup.removeListener(_onScrollGroupChanged);
    super.dispose();
  }

  ItemPositionsListener itemPositionsListener = ItemPositionsListener.create();
  // late ScrollablePositionedList scrollablePositionedList;

  bool wideWindow = false;
  late double wideWindowPadding;
  late bool partOfScrollGroup;
  late double baseFontSize;

  //All verses in memory
  List<ParsedLine> versesInMemory = [];

  List<String> collectionNames = [];
  List<Book> currentCollectionBooks = [];

  //Just initial default values, will get set below
  ValueNotifier<String> currentCollection = ValueNotifier("C01");
  ValueNotifier<String> currentBook = ValueNotifier("GEN");
  ValueNotifier<String> currentChapter = ValueNotifier("1");
  ValueNotifier<String> currentVerse = ValueNotifier("1");

  List<String> currentBookChapters = [];
  List<String> currentChapterVerseNumbers = [];

  List<List<ParsedLine>> versesByParagraph = [];

  String? collectionComboBoxValue;
  String? bookComboBoxValue;
  String? chapterComboBoxValue;
  String? verseComboBoxValue;

  late int previousParaPosition;
  // Load TOC
  Map<String, dynamic> toc = {};

  // New state for layout caching and tracking top verse
  final Map<int, List<VerseOffset>> _paragraphLayouts = {};
  String _topVerseRef = '';
  double _viewportHeight = 0.0;
  ({
    String book,
    String chapter,
    String verse,
    int paragraphIndex
  })? _pendingScrollRefinement;

  // State flags for loading indicators
  bool _isLoading = false;
  bool _isFetchingNext = false;
  bool _isFetchingPrevious = false;
  final GlobalKey _listKey = GlobalKey();
  bool _isScrollGroupListenerInitialized = false;

  Future<void> loadTOC() async {
    try {
      final path = 'assets/json/${currentCollection.value}_toc.json';
      final jsonString = await rootBundle.loadString(path);
      toc = json.decode(jsonString);
    } catch (e) {
      debugPrint('TOC not found or failed to parse');
      debugPrint(e.toString()); // TOC not found or failed to parse
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // We use didChangeDependencies because it is called after initState and
    // it's the correct place to access inherited widgets like Provider.
    // We only want to do this once, so we use a flag.
    if (!_isScrollGroupListenerInitialized) {
      _scrollGroup = Provider.of<ScrollGroup>(context, listen: false);
      _scrollGroup.addListener(_onScrollGroupChanged);
      _isScrollGroupListenerInitialized = true;
    }
  }

  @override
  void initState() {
    // Set the initial collection and populate the book list for the UI.
    currentCollection.value = widget.bibleReference.collectionID;
    currentCollectionBooks = widget.collections
        .firstWhere((c) => c.id == currentCollection.value,
            orElse: () => widget.collections.first)
        .books;

    loadTOC();
    partOfScrollGroup = widget.bibleReference.partOfScrollGroup;
    baseFontSize = 20;
    previousParaPosition = 0;
    itemScrollController = ItemScrollController();

    // New listener registration for identifying top verse
    itemPositionsListener.itemPositions.addListener(_handleScroll);

    scrollToReference(
        collection: widget.bibleReference.collectionID,
        bookID: widget.bibleReference.bookID,
        chapter: widget.bibleReference.chapter,
        verse: widget.bibleReference.verse,
        thisColumnNavigation: false,
        isInitState: true);

    super.initState();
  }

  void _updateTopVerse(Iterable<ItemPosition> positions) {
    // final positions = itemPositionsListener.itemPositions.value;
    // if (positions.isEmpty || !mounted) return;

    // Find the paragraph at the top of the viewport.
    final topParagraphPosition = positions.reduce(
        (min, pos) => pos.itemLeadingEdge < min.itemLeadingEdge ? pos : min);

    final paragraphIndex = topParagraphPosition.index;
    final layout = _paragraphLayouts[paragraphIndex];

    // If we don't have layout data for this paragraph yet, we can't do anything.
    if (layout == null || layout.isEmpty) return;

    // Convert the relative leading edge to an absolute pixel offset.
    final scrollOffsetInParagraph =
        -topParagraphPosition.itemLeadingEdge * _viewportHeight;

    // Find the last verse that starts *before* or exactly at the scroll offset.
    VerseOffset? topVerse;
    for (final verseOffset in layout) {
      if (verseOffset.offset.dy <= scrollOffsetInParagraph) {
        topVerse = verseOffset;
      } else {
        // The list of offsets is sorted by position, so we can break early.
        break;
      }
    }

    if (topVerse != null) {
      // If the top verse is part of an introduction, do not update the UI.
      // This keeps the reference at Chapter 1, Verse 1.
      if (topVerse.line.chapter == '0') {
        return;
      }

      final refString =
          '${topVerse.line.book} ${topVerse.line.chapter}:${topVerse.line.verse}';
      // When the top verse changes, update the UI and notify other columns.
      if (_topVerseRef != refString) {
        _topVerseRef = refString;

        // Update the ValueNotifiers to reflect the change in the UI.
        // This will cause the ComboBoxes to update their displayed value.
        final bookChanged = currentBook.value != topVerse.line.book;
        final chapterChanged = currentChapter.value != topVerse.line.chapter;

        currentBook.value = topVerse.line.book;
        currentChapter.value = topVerse.line.chapter;
        currentVerse.value = topVerse.line
            .verse; // this will work with whatever the real verse number is, even dashed

        // If the book or chapter changes, we need to update the list of
        // available chapters/verses for the dropdowns.
        if (bookChanged || chapterChanged) {
          setUpComboBoxesChVs();
        }

        // If this column is part of a scroll group and is the active one,
        // notify the other columns of the new scroll position.
        Key? activeColumnKey = context.read<ScrollGroup>().getActiveColumnKey;
        if (partOfScrollGroup && activeColumnKey == widget.key) {
          // debugPrint(
          //     '[ScriptureColumn ${widget.key}] I am the leader. Setting group ref.');

          // account for dashed verses - just send the first of any set to the scrollgroup
          final verseno = getFirstOfDashedVerses(currentVerse.value);

          BibleReference ref = BibleReference(
              key: widget.bibleReference.key,
              partOfScrollGroup: partOfScrollGroup,
              collectionID: currentCollection.value,
              bookID: currentBook.value,
              chapter: currentChapter.value,
              verse: verseno,
              columnIndex: widget.myColumnIndex);

          Provider.of<ScrollGroup>(context, listen: false).setScrollGroupRef =
              ref;
        }
      }
    }
  }

  void _handleScroll() {
    final positions = itemPositionsListener.itemPositions.value;
    if (positions.isEmpty || !mounted) return;
    _updateTopVerse(positions);

    final lastVisibleIndex =
        positions.map((p) => p.index).reduce((max, p) => p > max ? p : max);
    final firstVisibleIndex =
        positions.map((p) => p.index).reduce((min, p) => p < min ? p : min);

    // Proactively fetch next chapter when user is, say, 80% of the way through the loaded content.
    if (!_isFetchingNext && versesByParagraph.length - lastVisibleIndex < 5) {
      _fetchNextChapter();
    }

    // Proactively fetch previous chapter when user is near the beginning.
    if (!_isFetchingPrevious && firstVisibleIndex < 5) {
      _fetchPreviousChapter();
    }
  }

  Future<void> _fetchNextChapter() async {
    if (versesInMemory.isEmpty || _isFetchingNext) return;
    // print('fetching next chapter');

    setState(() {
      _isFetchingNext = true;
    });

    final lastVerse = versesInMemory.last;
    final result = await ChapterFetchService().getNextChunk(
      collectionId: currentCollection.value,
      bookId: lastVerse.book,
      lastChapter: int.parse(lastVerse.chapter),
    );

    if (result.lines.isNotEmpty && mounted) {
      versesInMemory.addAll(result.lines);
      final newParagraphs = _linesToParagraphs(result.lines);
      versesByParagraph.addAll(newParagraphs);
    }

    if (mounted) {
      setState(() {
        _isFetchingNext = false;
      });
    }
  }

  Future<void> _fetchPreviousChapter() async {
    if (versesInMemory.isEmpty || _isFetchingPrevious) return;
    // print('fetching prev chapter');
    final positions = itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    setState(() {
      _isFetchingPrevious = true;
    });

    // Record current scroll position
    final topItem = positions.reduce(
        (min, pos) => pos.itemLeadingEdge < min.itemLeadingEdge ? pos : min);
    final topItemIndex = topItem.index;
    final topItemAlignment = topItem.itemLeadingEdge;

    final firstVerse = versesInMemory.first;
    final result = await ChapterFetchService().getPreviousChunk(
      collectionId: currentCollection.value,
      bookId: firstVerse.book,
      firstChapter: int.parse(firstVerse.chapter),
    );

    if (result.lines.isNotEmpty && mounted) {
      versesInMemory.insertAll(0, result.lines);
      final newParagraphs = _linesToParagraphs(result.lines);
      versesByParagraph.insertAll(0, newParagraphs);

      // After the build, jump to the new position of the old top item
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          itemScrollController.jumpTo(
            index: topItemIndex + newParagraphs.length,
            alignment: topItemAlignment,
          );
        }
      });
    }

    if (mounted) {
      setState(() {
        _isFetchingPrevious = false;
      });
    }
  }

  void _attemptScrollRefinement(int readyParagraphIndex) {
    // Check if the paragraph that just finished layout is the one we're waiting for.
    if (_pendingScrollRefinement != null &&
        _pendingScrollRefinement!.paragraphIndex == readyParagraphIndex) {
      // debugPrint(
      //     "Layout is now ready for pending scroll. Refining position...");
      // The layout data is now in _paragraph Layouts, so calling _scroll WithAdjustment again will work.
      _scrollWithAdjustment(
        targetBook: _pendingScrollRefinement!.book,
        targetChapter: _pendingScrollRefinement!.chapter,
        targetVerse: _pendingScrollRefinement!.verse,
        thisColumnNavigation: false,
        jump: true, // Use jump for refinement to be instant.
      );
      // The pending request is cleared inside the successful path of _scroll With Adjustment.
    }
  }

  void setActiveColumnKey() {
    Provider.of<ScrollGroup>(context, listen: false).setActiveColumnKey =
        widget.key;
  }

  void _scrollWithAdjustment(
      {required String targetBook,
      required String targetChapter,
      required String targetVerse,
      required bool thisColumnNavigation,
      bool jump = false}) async {
    if (_isScrolling) return; // Don't start a new scroll if one is in progress

    setState(() {
      _isScrolling = true;
    });

    try {
      bool navMethod = jump;

      final targetParagraphIndex = versesByParagraph.indexWhere(
        (p) => p.any((l) =>
            l.book == targetBook &&
            l.chapter == targetChapter &&
            l.verse == targetVerse),
      );

      if (targetParagraphIndex == -1) return;

      final List<VerseOffset>? paragraphLayout =
          _paragraphLayouts[targetParagraphIndex];

      if (paragraphLayout != null && paragraphLayout.isNotEmpty) {
        _pendingScrollRefinement = null; // Clear any pending request
        final VerseOffset? targetVerseOffset = paragraphLayout.firstWhereOrNull(
          (vo) =>
              vo.line.book == targetBook &&
              vo.line.chapter == targetChapter &&
              vo.line.verse == targetVerse,
        );

        if (targetVerseOffset != null) {
          final double alignment =
              targetVerseOffset.offset.dy / _viewportHeight;
          // print('alignment = $alignment');
          if (navMethod) {
            itemScrollController.jumpTo(
                index: targetParagraphIndex, alignment: -alignment);
          } else {
            await itemScrollController.scrollTo(
                index: targetParagraphIndex,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                alignment: -alignment);
          }
        } else {
          itemScrollController.jumpTo(index: targetParagraphIndex);
        }
      } else {
        _pendingScrollRefinement = (
          book: targetBook,
          chapter: targetChapter,
          verse: targetVerse,
          paragraphIndex: targetParagraphIndex
        );
        itemScrollController.jumpTo(index: targetParagraphIndex, alignment: 0);
      }

      if (partOfScrollGroup && thisColumnNavigation) {
        setActiveColumnKey();
        final ref = BibleReference(
            key: widget.key!,
            partOfScrollGroup: partOfScrollGroup,
            collectionID: currentCollection.value,
            bookID: targetBook,
            chapter: targetChapter,
            verse: targetVerse,
            columnIndex: widget.myColumnIndex);
        if (!mounted) return;
        Provider.of<ScrollGroup>(context, listen: false).setScrollGroupRef =
            ref;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScrolling = false;
        });
      }
    }
  }

  //Function called on first open
  //and also from combobox selectors to go to a Bible reference

  // Not easy to keep track of the cases!
  // Scrolling: leading and following
  // Collection/Book/Chapter/Verse Selectors: leading and following
  // Search: following
  Future<void> scrollToReference(
      {required String collection,
      required String bookID,
      required String chapter,
      required String verse,
      required bool thisColumnNavigation,
      bool isInitState = false}) async {
    // print('scrollToReference ${currentCollection.value}');

    bool collectionChanged = false;
    var targetBook = bookID;
    var targetChapter = chapter;
    var targetVerse = verse;
    // print(
    //     '$targetBook $targetChapter:$targetVerse    thisColumnNavigation ? $thisColumnNavigation');
    // Function to check if a reference is in the collection
    Future<bool> checkIfRefIsInCollection(
        String bk, String ch, String vs) async {
      // This function validates a reference against the collection's table of contents.

      // Check book
      final bookData = toc[bk];
      if (bookData == null) return false;

      // Check chapter
      final chapters = bookData['chapters'] as Map<String, dynamic>?;
      if (chapters == null || !chapters.containsKey(ch)) return false;

      // check verse
      // verse could be dashed - 13-15 etc - just get the last number
      final verseno = getLastOfDashedVerses(vs);
      if (int.parse(verseno) < int.parse(chapters[ch])) {
        return true;
      } else {
        return false;
      }
    }

    bool checkIfRefIsInMemory(String bk, String ch, String vs) {
      // is the verse already in memory?
      return versesInMemory.any(
          (line) => line.book == bk && line.chapter == ch && line.verse == vs);
    }

    // Begins here: sanitize the target destination
    collectionChanged = (currentCollection.value != collection || isInitState);
    if (collectionChanged) {
      currentCollection.value = collection;
      await loadTOC();

      // Immediately update the list of books available for the new collection.
      currentCollectionBooks = widget.collections
          .firstWhere((element) => element.id == currentCollection.value)
          .books;

      // Now that we have the new TOC, check if the old book is valid.
      if (!toc.containsKey(bookID)) {
        // If not, reset the target to the first book of the new collection.
        if (toc.keys.isNotEmpty) {
          targetBook = toc.keys.first;
          targetChapter = '1';
          targetVerse = '1';
        }
      }
      // If the old book *is* valid in the new collection, we let it pass through,
      // respecting the original chapter/verse.
    } else if (currentBook.value != targetBook) {
      // We can have user directly navigating using the controls in this column
      // - treat that separately from searching, opening for first time.
      // If user is going from Ruth to Genesis, open to 1.1.
      // If you're searching on the other hand and trying to navigate to Genesis 38.1, go to Gen 38.1.
      // thisColumnNavigation tells us that.
      if (thisColumnNavigation) {
        // This handles book changes within the same collection.
        targetChapter = '1';
        targetVerse = '1';
      }
    } else if (currentChapter.value != targetChapter) {
      // This handles chapter changes within the same book.
      if (thisColumnNavigation) {
        targetVerse = '1';
      }
    }

    // We've already checked the book - this is in the case of other discontinuities in versification systems
    bool refIsInCollection =
        await checkIfRefIsInCollection(targetBook, targetChapter, targetVerse);

    // if it is there, get the data and navigate to it
    if (refIsInCollection) {
      bool verseIsInMemory =
          checkIfRefIsInMemory(targetBook, targetChapter, targetVerse);
      if (!verseIsInMemory || collectionChanged) {
        // Set loading state and clear old data to show skeletonizer
        setState(() {
          _isLoading = true;
        });

        // check if the reference we're trying to go to is in the collection

        // hit reset
        versesInMemory.clear();
        versesByParagraph.clear();
        _paragraphLayouts.clear();

        // get the initial chunk of data
        final fetchResult = await ChapterFetchService().getInitialChunk(
            collectionId: currentCollection.value,
            bookId: targetBook,
            chapter: int.parse(targetChapter));

        if (!mounted) return;

        final newParagraphs = _linesToParagraphs(fetchResult.lines);

        // finish up and return to the UI
        setState(() {
          versesInMemory.addAll(fetchResult.lines);
          versesByParagraph.addAll(newParagraphs);
          _isLoading = false;
        });
        // Scroll to the target paragraph after the list has been built.

        // if (targetParagraphIndex != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scrollWithAdjustment(
                targetBook: targetBook,
                targetChapter: targetChapter,
                targetVerse: targetVerse,
                thisColumnNavigation: thisColumnNavigation,
                jump: true);
          }
        });
      } else {
        _scrollWithAdjustment(
            targetBook: targetBook,
            targetChapter: targetChapter,
            targetVerse: targetVerse,
            thisColumnNavigation: thisColumnNavigation);
      }
      // Update the ValueNotifiers to reflect the final navigation state.
      currentBook.value = targetBook;
      currentChapter.value = targetChapter;
      currentVerse.value =
          targetVerse; // this will just lazily fail with dashed verse number
      setUpComboBoxesChVs();
    } else {
      // if not, don't do anything, just stay there
    }
    // end scroll to Referenc
  }

  List<List<ParsedLine>> _linesToParagraphs(List<ParsedLine> lines) {
    List<List<ParsedLine>> paragraphs = [];
    List<ParsedLine> currentParagraph = [];

    for (var i = 0; i < lines.length; i++) {
      //If it is a new paragraph marker, add the existing verses to the big list, and start over with a new paragraph
      if (isParagraph(lines[i])) {
        if (currentParagraph.isNotEmpty) paragraphs.add(currentParagraph);
        currentParagraph = [lines[i]];
        //If it's a one line paragraph
      } else if ((lines[i].verseStyle.contains(RegExp(r'[m,r,d]')))) {
        if (currentParagraph.isNotEmpty) paragraphs.add(currentParagraph);
        paragraphs.add([lines[i]]);
        currentParagraph = [];
      } else {
        //otherwise just add the line to the paragraph
        currentParagraph.add(lines[i]);
      }
    }
    //Get that last paragraph added!
    if (currentParagraph.isNotEmpty) paragraphs.add(currentParagraph);
    return paragraphs;
  }

  // End scroll To Reference

  void setUpComboBoxesChVs() {
    try {
      // print('setUp ComboBoxesChVs');
      final bookData = toc[currentBook.value];
      if (bookData == null || bookData['chapters'] == null) return;

      final Map<String, dynamic> temp = bookData['chapters'];
      currentBookChapters.clear();
      currentBookChapters.addAll(temp.keys.toList());

      // synthetic verse numbers
      // String? numberOfVersesInCurrentChapter = temp[currentChapter.value];
      // if (numberOfVersesInCurrentChapter == null) return;

      // int verseCount = 0;
      // if (numberOfVersesInCurrentChapter.contains('-')) {
      //   final parts = numberOfVersesInCurrentChapter.split('-');
      //   verseCount = int.tryParse(parts.last.trim()) ?? 0;
      // } else {
      //   verseCount = int.tryParse(numberOfVersesInCurrentChapter) ?? 0;
      // }

      // currentChapterVerseNumbers = List.generate(verseCount, (int i) {
      //   return (i + 1).toString();
      // });

      // get the real verse numbers from the chapter
      currentChapterVerseNumbers.clear();

      final tempverseslist = versesInMemory
          .where((line) =>
              line.collectionid == currentCollection.value &&
              line.book == currentBook.value &&
              line.chapter == currentChapter.value)
          .map((line) => line.verse)
          .where((verse) => verse != '')
          .toSet()
          .toList();

      currentChapterVerseNumbers.addAll(tempverseslist);

      // if (mounted) {
      //   setState(() {});
      // }

      BibleReference ref = BibleReference(
          key: widget.bibleReference.key,
          partOfScrollGroup: partOfScrollGroup,
          collectionID: currentCollection.value,
          bookID: currentBook.value,
          chapter: currentChapter.value,
          verse: currentVerse.value,
          columnIndex: widget.myColumnIndex);

      if (mounted) {
        Provider.of<UserPrefs>(context, listen: false)
            .saveScrollGroupState(ref);
        // print(ref.toString());
      }
    } catch (e, s) {
      debugPrint('Error in setUpComboBoxesChVs: $e');
      debugPrint(s.toString());
    }
  }

  String _composeVersesInRange(ParsedLine firstLine, ParsedLine lastLine,
      {required bool includeVerseNumbers}) {
    final StringBuffer buffer = StringBuffer();

    final startIndex = versesInMemory.indexOf(firstLine);

    final endIndex = versesInMemory.indexOf(lastLine);

    if (startIndex == -1 || endIndex == -1) {
      return '';
    }

    for (int i = startIndex; i <= endIndex; i++) {
      final line = versesInMemory[i];

      if (isHeader(line)) continue;

      if (isParagraph(line)) {
        buffer.write('\n    ');
      }
      String composedText = verseComposer(
        line: line,
        includeFootnotes: false,
        context: context,
      ).versesAsString.trim();

      if (includeVerseNumbers && line.verse.isNotEmpty && line.verse != '0') {
        buffer.write('${toSuperscript(line.verse)}\u202f');
      }

      buffer.write('$composedText ');
    }

    final reference = _getFormattedReferenceString(firstLine, lastLine);

    if (reference.isNotEmpty) {
      buffer.write('\n\n$reference');
    }

    return buffer.toString().trim();
  }

  String _getFormattedReferenceString(
      ParsedLine firstSelectedLine, ParsedLine lastSelectedLine) {
    String reference = '';
    String currentCollectionName = widget.collections
        .where((element) => element.id == currentCollection.value)
        .first
        .name;

    if (firstSelectedLine.book == lastSelectedLine.book) {
      String bookName = currentCollectionBooks
          .where((element) => element.id == firstSelectedLine.book)
          .first
          .name;

      if (firstSelectedLine.chapter == lastSelectedLine.chapter) {
        if (firstSelectedLine.verse == lastSelectedLine.verse) {
          reference =
              '$bookName ${firstSelectedLine.chapter}:${firstSelectedLine.verse}';
        } else {
          reference =
              '$bookName ${firstSelectedLine.chapter}:${firstSelectedLine.verse}-${lastSelectedLine.verse}';
        }
      } else {
        reference =
            '$bookName ${firstSelectedLine.chapter}:${firstSelectedLine.verse}-${lastSelectedLine.chapter}:${lastSelectedLine.verse}';
      }
    } else {
      // Selection spans across books
      String firstBookName = currentCollectionBooks
          .where((element) => element.id == firstSelectedLine.book)
          .first
          .name;
      String lastBookName = currentCollectionBooks
          .where((element) => element.id == lastSelectedLine.book)
          .first
          .name;
      reference =
          '$firstBookName ${firstSelectedLine.chapter}:${firstSelectedLine.verse}-$lastBookName ${lastSelectedLine.chapter}:${lastSelectedLine.verse}';
    }

    return '$reference ($currentCollectionName)';
  }

  ParsedLine? _getLineAtOffset(Offset globalOffset) {
    final RenderBox? listRenderBox =
        _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listRenderBox == null || !listRenderBox.hasSize) return null;
    final Offset localOffset = listRenderBox.globalToLocal(globalOffset);

    final positions = itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return null;

    ItemPosition? targetParagraphPosition;
    for (final pos in positions) {
      final itemTop = pos.itemLeadingEdge * _viewportHeight;
      final itemBottom = pos.itemTrailingEdge * _viewportHeight;
      if (localOffset.dy >= itemTop && localOffset.dy <= itemBottom) {
        targetParagraphPosition = pos;
        break;
      }
    }

    if (targetParagraphPosition == null) {
      // If not found (e.g., tap is in padding), find the closest one.
      if (positions.isNotEmpty) {
        targetParagraphPosition = positions.reduce((a, b) =>
            (a.itemLeadingEdge * _viewportHeight - localOffset.dy).abs() <
                    (b.itemLeadingEdge * _viewportHeight - localOffset.dy).abs()
                ? a
                : b);
      } else {
        return null;
      }
    }

    final paragraphIndex = targetParagraphPosition.index;
    final paragraphTopOffsetInViewport =
        targetParagraphPosition.itemLeadingEdge * _viewportHeight;
    final offsetInParagraph = Offset(
      localOffset.dx,
      localOffset.dy - paragraphTopOffsetInViewport,
    );

    final layout = _paragraphLayouts[paragraphIndex];
    if (layout == null || layout.isEmpty) return null;

    VerseOffset? closestVerse;
    for (final verseOffset in layout) {
      if (verseOffset.offset.dy <= offsetInParagraph.dy) {
        closestVerse = verseOffset;
      } else {
        break;
      }
    }

    return closestVerse?.line;
  }

  void _onDragStart(Offset position) {
    // Global position of the pointer when drag starts
    copyEndLine = null;
    copyStartLine = _getLineAtOffset(position);
  }

  void _onDragEnd(Offset position) {
    copyEndLine = _getLineAtOffset(position);
  }

  void _onScrollGroupChanged() {
    final scrollGroupRef = _scrollGroup.getScrollGroupRef;
    final activeColumnKey = _scrollGroup.getActiveColumnKey;

    if (partOfScrollGroup &&
        scrollGroupRef != null &&
        activeColumnKey != widget.key) {
      if (currentBook.value != scrollGroupRef.bookID ||
          currentChapter.value != scrollGroupRef.chapter ||
          currentVerse.value != scrollGroupRef.verse) {
        scrollToReference(
            collection: currentCollection.value,
            bookID: scrollGroupRef.bookID,
            chapter: scrollGroupRef.chapter,
            verse: scrollGroupRef.verse,
            thisColumnNavigation: false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final translation =
        Provider.of<UserPrefs>(context, listen: true).currentTranslation;
    // // print(
    //     'scripture column build: columnIndex: ${widget.bibleReference.columnIndex}; collection: ${widget.bibleReference.collectionID}; key: ${widget.key}');

    //Couple of things to get to pass in to the Paragraph Builder

    if (kIsWeb) {
      isTouch = isTouchWebDevice();
    } else if (Platform.isAndroid || Platform.isIOS) {
      isTouch = true;
    } else {
      isTouch = false;
    }

    Collection thisCollection = collections
        .firstWhere((element) => element.id == currentCollection.value);

    String fontName = thisCollection.fonts.first.fontFamily;

    late ui.TextDirection textDirection;
    late AlignmentGeometry alignment;
    double? comboBoxFontSize = 16;

    if (thisCollection.textDirection == 'LTR') {
      textDirection = ui.TextDirection.ltr;
      alignment = Alignment.centerLeft;
      // comboBoxFontSize = DefaultTextStyle.of(context).style.fontSize;
    } else {
      textDirection = ui.TextDirection.rtl;
      alignment = Alignment.centerRight;
      // comboBoxFontSize = 18;
    }

    TextOverflow textOverflow = TextOverflow.ellipsis;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        //header toolbar/s
        children: [
          //Scripture column ref selection card
          Padding(
            //Each column has 5 above and then 2.5 l and r,
            //which when beside each other makes 5 between each col.
            //Padding in bible view makes the first and last column have the full 5.
            padding: const EdgeInsets.only(top: 5.0, right: 2.5, left: 2.5),
            child: Card(
              //The default card color is good for dark but for white it's basically just white, so to differentiate soften a bit with grey
              backgroundColor: FluentTheme.of(context).brightness ==
                      Brightness.dark
                  ? null
                  : FluentTheme.of(context).cardColor.lerpWith(Colors.grey, .1),
              padding:
                  const EdgeInsets.only(top: 12, bottom: 12, left: 6, right: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Wrap(
                          //space betwen items
                          spacing: 5,
                          //space between rows when stacked
                          runSpacing: 8,
                          direction: Axis.horizontal,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          alignment: WrapAlignment.start,
                          children: [
                            //Collections/translations
                            SizedBox(
                              width: 150,
                              child: ValueListenableBuilder<String>(
                                  valueListenable: currentCollection,
                                  builder: (context, val, child) {
                                    return ComboBox<String>(
                                      style: DefaultTextStyle.of(context)
                                          .style
                                          .copyWith(
                                              fontFamily: widget.comboBoxFont,
                                              fontSize: comboBoxFontSize),
                                      isExpanded: true,
                                      items: widget.collections
                                          .map((e) => ComboBoxItem<String>(
                                                value: e.id,
                                                child: Align(
                                                  alignment: alignment,
                                                  child: Text(
                                                    e.name,
                                                    overflow: textOverflow,
                                                    textDirection:
                                                        textDirection,
                                                  ),
                                                ),
                                              ))
                                          .toList(),
                                      value: val,
                                      onChanged: (value) {
                                        if (value != null) {
                                          setActiveColumnKey();
                                          scrollToReference(
                                              collection: value,
                                              bookID: currentBook.value,
                                              chapter: currentChapter.value,
                                              verse: currentVerse.value,
                                              thisColumnNavigation: true);
                                        }
                                      },
                                    );
                                  }),
                            ),

                            // Book
                            SizedBox(
                              width: 175,
                              child: ValueListenableBuilder<String>(
                                  valueListenable: currentBook,
                                  builder: (context, val, child) {
                                    return ComboBox<String>(
                                      style: DefaultTextStyle.of(context)
                                          .style
                                          .copyWith(
                                              fontFamily: widget.comboBoxFont,
                                              fontSize: comboBoxFontSize),
                                      isExpanded: true,
                                      items: currentCollectionBooks.map((e) {
                                        late String name;
                                        if (e.name.contains('Προσ')) {
                                          name = e.name.substring(5);
                                        } else {
                                          name = e.name;
                                        }

                                        return ComboBoxItem<String>(
                                          value: e.id,
                                          child: Align(
                                            alignment: alignment,
                                            child: Text(
                                              name,
                                              overflow: textOverflow,
                                              textDirection: textDirection,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                      value: val,
                                      onChanged: (value) {
                                        if (value != null) {
                                          setActiveColumnKey();
                                          scrollToReference(
                                              collection:
                                                  currentCollection.value,
                                              bookID: value,
                                              chapter: currentChapter.value,
                                              verse: currentVerse.value,
                                              thisColumnNavigation: true);
                                        }
                                      },
                                    );
                                  }),
                            ),
                            //This Row keeps chapter and verse together!
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              // //chapter
                              SizedBox(
                                width: 80,
                                child: ValueListenableBuilder<String>(
                                    valueListenable: currentChapter,
                                    builder: (context, val, child) {
                                      return ComboBox<String>(
                                        style: DefaultTextStyle.of(context)
                                            .style
                                            .copyWith(
                                                fontFamily: widget.comboBoxFont,
                                                fontSize: comboBoxFontSize),
                                        isExpanded: true,
                                        items: currentBookChapters.map((e) {
                                          // account for chapter 0 as intro
                                          String displayText =
                                              e == '0' ? 'Intro' : e;

                                          return ComboBoxItem<String>(
                                            value: e,
                                            child: Text(
                                              displayText,
                                              overflow: textOverflow,
                                            ),
                                          );
                                        }).toList(),
                                        value: val,
                                        onChanged: (value) {
                                          if (value != null) {
                                            setActiveColumnKey();

                                            scrollToReference(
                                                collection:
                                                    currentCollection.value,
                                                bookID: currentBook.value,
                                                chapter: value,
                                                verse: currentVerse.value,
                                                thisColumnNavigation: true);
                                          }
                                        },
                                      );
                                    }),
                              ),
                              const SizedBox(
                                width: 5,
                              ),

                              // //verse
                              SizedBox(
                                width: 80,
                                child: ValueListenableBuilder<String>(
                                    valueListenable: currentVerse,
                                    builder: (context, val, child) {
                                      return ComboBox<String>(
                                        style: DefaultTextStyle.of(context)
                                            .style
                                            .copyWith(
                                                fontFamily: widget.comboBoxFont,
                                                fontSize: comboBoxFontSize),
                                        placeholder: const Text('--'),
                                        isExpanded: true,
                                        items: currentChapterVerseNumbers
                                            // .toSet()
                                            // .toList()
                                            .map((e) => ComboBoxItem<String>(
                                                  value: e,
                                                  child: Text(
                                                    e,
                                                    overflow: textOverflow,
                                                  ),
                                                ))
                                            .toList(),
                                        value: val,
                                        onChanged: (value) {
                                          if (value != null) {
                                            setActiveColumnKey();

                                            final verseno =
                                                getFirstOfDashedVerses(value);
                                            scrollToReference(
                                                collection:
                                                    currentCollection.value,
                                                bookID: currentBook.value,
                                                chapter: currentChapter.value,
                                                verse: verseno,
                                                thisColumnNavigation: true);
                                          }
                                        },
                                      );
                                    }),
                              ),
                            ]),

                            //Grouping for the buttons
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                //Font increase/decrease
                                Button(
                                  onPressed: () {
                                    if (baseFontSize < 50) {
                                      setState(() {
                                        baseFontSize = baseFontSize + 1;
                                      });
                                    }
                                  },
                                  child: const Icon(FluentIcons.font_increase),
                                ),
                                const SizedBox(width: 5),
                                Button(
                                  onPressed: () {
                                    if (baseFontSize > 10) {
                                      setState(() {
                                        baseFontSize = baseFontSize - 1;
                                      });
                                    }
                                  },
                                  child: const Icon(FluentIcons.font_decrease),
                                ),
                                const SizedBox(
                                  width: 10,
                                ),

                                ToggleButton(
                                  checked: partOfScrollGroup,
                                  onChanged: (_) {
                                    setState(() {
                                      partOfScrollGroup = !partOfScrollGroup;
                                    });
                                  },
                                  child: const Icon(FluentIcons.link),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  //If this is column 1, don't let the user delete the column
                  if (widget.myColumnIndex != 0)
                    IconButton(
                      onPressed: () {
                        widget.deleteColumn(widget.key);
                      },
                      icon: const Icon(FluentIcons.calculator_multiply),
                    ),
                  if (widget.myColumnIndex == 0)
                    const SizedBox(
                      width: 30,
                    )
                ],
              ),
            ),
          ),
          // End of scripture column toolbar

          // The scripture container
          Expanded(
            child: Padding(
              padding: wideWindow
                  ? EdgeInsets.only(
                      left: wideWindowPadding,
                      right: wideWindowPadding,
                      top: 0,
                      bottom: 0)
                  : const EdgeInsets.only(
                      left: 2.5, right: 2.5, top: 0, bottom: 0),
              // ignore: avoid_unnecessary_containers
              child: Container(
                key: _listKey,
                decoration: const BoxDecoration(
                  //This is the border between each scripture column and its neighbor to the right
                  border: Border(
                    right: BorderSide(
                      width: 1.0,
                      color: Color.fromARGB(85, 126, 126, 126),
                    ),
                  ),
                ),
                child: UserInterAction(
                  partOfScrollGroup: partOfScrollGroup,
                  setActiveColumnKey: setActiveColumnKey,
                  child: Skeletonizer(
                    enabled: _isLoading,
                    child: LayoutBuilder(builder: (context, constraints) {
                      _viewportHeight = constraints.maxHeight;

                      return Listener(
                        onPointerDown: (event) {
                          buttonPressed = event.buttons;
                          // Primary mouse button
                          if (event.buttons == 1 && _lastSelectedText == '') {
                            _onDragStart(event.position);
                          }
                        },
                        onPointerUp: (event) {
                          if (buttonPressed == 1) {
                            // This is the way to grab the end of the selection on pointer device
                            _onDragEnd(event.position);
                          }
                          buttonPressed = null;
                        },
                        child: SelectionArea(
                          contextMenuBuilder: (BuildContext context,
                              SelectableRegionState regionState) {
                            // This is the way to grab the end of the selection on touchscreen
                            if (isTouch) {
                              final pos = regionState
                                  .contextMenuAnchors.secondaryAnchor;
                              if (pos != null) {
                                _onDragEnd(regionState
                                    .contextMenuAnchors.secondaryAnchor!);
                              }
                            }

                            // just grab the selection
                            Future<void> simpleCopy() async {
                              final selected = _lastSelectedText;
                              await Clipboard.setData(
                                ClipboardData(text: selected),
                              );
                              ContextMenuController.removeAny();
                            }

                            // compose the verses nicely
                            void complexCopy(bool withVerses) async {
                              try {
                                if (copyStartLine != null &&
                                    copyEndLine != null) {
                                  // Ensure correct order
                                  final startIndex =
                                      versesInMemory.indexOf(copyStartLine!);
                                  final endIndex =
                                      versesInMemory.indexOf(copyEndLine!);
                                  final ParsedLine startLine =
                                      (startIndex <= endIndex)
                                          ? copyStartLine!
                                          : copyEndLine!;
                                  final ParsedLine endLine =
                                      (startIndex <= endIndex)
                                          ? copyEndLine!
                                          : copyStartLine!;

                                  final textToCopy = _composeVersesInRange(
                                      startLine, endLine,
                                      includeVerseNumbers: withVerses);
                                  Clipboard.setData(
                                      ClipboardData(text: textToCopy));
                                } else {
                                  // Fallback to copying the raw selected text if geometry fails
                                  simpleCopy();
                                }
                              } catch (e) {
                                debugPrint(e.toString());
                                simpleCopy();
                              }

                              ContextMenuController.removeAny();
                            }
                            // the defaults
                            // final buttonItems =
                            //     regionState.contextMenuButtonItems;

                            // Add your own "Copy with Ref" button
                            return AdaptiveTextSelectionToolbar.buttonItems(
                              anchors: regionState.contextMenuAnchors,
                              buttonItems: [
                                ContextMenuButtonItem(
                                  label: translation.copy,
                                  onPressed: simpleCopy,
                                ),
                                ContextMenuButtonItem(
                                  label: translation.copyWithNumbers,
                                  onPressed: () => complexCopy(true),
                                ),
                                ContextMenuButtonItem(
                                  label: translation.copyWithoutNumbers,
                                  onPressed: () => complexCopy(false),
                                ),
                              ],
                            );
                          },
                          onSelectionChanged: (selection) {
                            _lastSelectedText = selection?.plainText ?? '';
                          },
                          child: ScrollablePositionedList.builder(
                              //this is the space between the right of the column and the text for the scrollbar
                              padding: const EdgeInsets.only(right: 10),
                              initialAlignment: 1,
                              itemScrollController: itemScrollController,
                              itemPositionsListener: itemPositionsListener,
                              itemCount: _isLoading
                                  ? 6
                                  : versesByParagraph.length +
                                      (_isFetchingPrevious ? 1 : 0) +
                                      (_isFetchingNext ? 1 : 0),
                              shrinkWrap: false,
                              physics: const ClampingScrollPhysics(),
                              itemBuilder: (ctx, i) {
                                if (_isLoading) {
                                  return ParagraphBuilder(
                                    paragraph: [
                                      ParsedLine(
                                          collectionid: '',
                                          book: '',
                                          chapter: '',
                                          verse: '',
                                          verseFragment: '',
                                          audioMarker: '',
                                          verseText:
                                              'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc auctor nec diam sed egestas. Vestibulum volutpat mollis massa at faucibus. Proin eros urna, pellentesque sit amet mattis id, sollicitudin blandit tortor. Mauris vel ipsum id ipsum auctor lacinia sed at neque. Pellentesque ut malesuada dui, eget blandit est. Fusce lacinia sit amet magna eget viverra. Donec eu orci pharetra, molestie augue non, fermentum enim. Suspendisse mollis tempus sem sit amet pretium. Morbi tempor, ante finibus euismod maximus, massa justo tempus magna, eget commodo nulla turpis vel orci.',
                                          verseStyle: 'p')
                                    ],
                                    addDivider: false,
                                    fontName: 'Charis',
                                    textDirection: ui.TextDirection.ltr,
                                    fontSize: 20,
                                  );
                                }
                                if (_isFetchingPrevious && i == 0) {
                                  return const Skeletonizer(
                                    child: Card(
                                      child: SizedBox(
                                        height: 100,
                                        child: Center(
                                          child: Text('Loading...'),
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                final paraIndex =
                                    _isFetchingPrevious ? i - 1 : i;

                                if (_isFetchingNext &&
                                    paraIndex == versesByParagraph.length) {
                                  return const Skeletonizer(
                                    child: Card(
                                      child: SizedBox(
                                        height: 100,
                                        child: Center(
                                          child: Text('Loading...'),
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                // this complicated thing is just to add a big divider after books endign and before next book intro
                                bool addDivider = false;
                                final me = versesByParagraph[paraIndex];
                                if (me.isNotEmpty && me.first.chapter == '0') {
                                  final firstParaOfCurrentBookIntro =
                                      versesByParagraph
                                          .where((element) =>
                                              element.isNotEmpty &&
                                              element.first.book ==
                                                  me.first.book)
                                          .first;
                                  if (me == firstParaOfCurrentBookIntro) {
                                    addDivider = true;
                                  }
                                }

                                return ParagraphBuilder(
                                  paragraph: versesByParagraph[paraIndex],
                                  addDivider: addDivider,
                                  fontSize: baseFontSize,
                                  fontName: fontName,
                                  textDirection: textDirection,
                                  onLayoutCalculated: (offsets) {
                                    _paragraphLayouts[paraIndex] = offsets;
                                    _attemptScrollRefinement(paraIndex);
                                  },
                                );
                              }),
                        ),
                      );

                      // if (kIsWeb) {
                      //   // On web choose between pointer and touch behavior using media query.
                      //   return isTouchWebDevice()
                      //       ? touchVersion(selectionArea())
                      //       : pointerVersion(selectionArea());
                      // } else if (Platform.isAndroid || Platform.isIOS) {
                      // return touchVersion(selectionArea());
                      // // } else {

                      // }
                    }),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String getFirstOfDashedVerses(String vs) {
// account for dashed verses - just send the first of any set to the scrollgroup
  RegExpMatch? match = RegExp(r'(\d+)(-*\d*)').firstMatch(vs);
// send the cleaned verse number or as fallback send the current Verse
  final verseno = match?.group(1) ?? vs;
  return verseno;
}

String getLastOfDashedVerses(String vs) {
// account for dashed verses - just send the last of any set
  RegExpMatch? match = RegExp(r'(\d*-*)(\d+)').firstMatch(vs);
// send the cleaned verse number or as fallback send the current Verse
  final verseno = match?.group(2) ?? vs;
  return verseno;
}

bool isParagraph(ParsedLine line) {
  // based on verseStyle, is this a new paragraph?
  return line.verseStyle.contains(RegExp(
      r'[p,po,pr,cls,pmo,pm,pmc,pmr,pi\d,mi,nb,pc,ph\d,b,mt\d,mte\d,ms\d,mr,s\d*,sr,sp,sd\d,q,q1,q2,qr,qc,qa,qm\d,qd,lh,li\d,lf,lim\d,ip,im,ie,ili]'));
}

bool isHeader(ParsedLine line) {
  // based on verseStyle, is this a new paragraph?
  return line.verseStyle.contains(RegExp(r'[s\d*,mt\d*,mr,ms\d*,]'));
}
