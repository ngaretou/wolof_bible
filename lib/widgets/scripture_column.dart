import 'dart:ui' as ui;
import 'dart:async';
import 'dart:convert';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../providers/column_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:context_menus/context_menus.dart';
import 'package:collection/collection.dart';

import '../logic/data_initializer.dart';
import '../logic/verse_composer.dart';
import '../widgets/paragraph_builder.dart';

import '../providers/user_prefs.dart';
import '../logic/chapter_fetch_service.dart';

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
  void dummy(ParsedLine ref) {}

  late ItemScrollController itemScrollController;
  late ScrollGroup _scrollGroup;

  @override
  void dispose() {
    _scrollGroup.removeListener(_onScrollGroupChanged);
    super.dispose();
  }

  ItemPositionsListener itemPositionsListener = ItemPositionsListener.create();
  late ScrollablePositionedList scrollablePositionedList;

  bool wideWindow = false;
  late double wideWindowPadding;
  late bool partOfScrollGroup;
  late double baseFontSize;
  List<ParsedLine> rangeOfVersesToCopy = [];

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
  List<ParsedLine> currentParagraph = [];

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
      if (topVerse.chapter == '0') {
        return;
      }

      final refString =
          '${topVerse.book} ${topVerse.chapter}:${topVerse.verse}';
      // When the top verse changes, update the UI and notify other columns.
      if (_topVerseRef != refString) {
        _topVerseRef = refString;

        // Update the ValueNotifiers to reflect the change in the UI.
        // This will cause the ComboBoxes to update their displayed value.
        final bookChanged = currentBook.value != topVerse.book;
        final chapterChanged = currentChapter.value != topVerse.chapter;

        currentBook.value = topVerse.book;
        currentChapter.value = topVerse.chapter;
        currentVerse.value = topVerse.verse;

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
          BibleReference ref = BibleReference(
              key: widget.bibleReference.key,
              partOfScrollGroup: partOfScrollGroup,
              collectionID: currentCollection.value,
              bookID: currentBook.value,
              chapter: currentChapter.value,
              verse: currentVerse.value,
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
    if (!_isFetchingNext && lastVisibleIndex > versesByParagraph.length * 0.8) {
      _fetchNextChapter();
    }

    // Proactively fetch previous chapter when user is near the beginning.
    if (!_isFetchingPrevious && firstVisibleIndex < 10) {
      _fetchPreviousChapter();
    }
  }

  Future<void> _fetchNextChapter() async {
    if (versesInMemory.isEmpty || _isFetchingNext) return;

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
      // The layout data is now in _paragraphLayouts, so calling _scrollWithAdjustment again will work.
      _scrollWithAdjustment(
        targetBook: _pendingScrollRefinement!.book,
        targetChapter: _pendingScrollRefinement!.chapter,
        targetVerse: _pendingScrollRefinement!.verse,
        thisColumnNavigation: false,
        jump: true, // Use jump for refinement to be instant.
      );
      // The pending request is cleared inside the successful path of _scrollWithAdjustment.
    }
  }

  void _scrollWithAdjustment(
      {required String targetBook,
      required String targetChapter,
      required String targetVerse,
      required bool thisColumnNavigation,
      bool jump = false}) {
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
      // Layout data is ready, scroll precisely.
      _pendingScrollRefinement = null; // Clear any pending request for this.
      final VerseOffset? targetVerseOffset = paragraphLayout.firstWhereOrNull(
        (vo) =>
            vo.book == targetBook &&
            vo.chapter == targetChapter &&
            vo.verse == targetVerse,
      );

      if (targetVerseOffset != null) {
        final double alignment = targetVerseOffset.offset.dy / _viewportHeight;
        if (jump) {
          itemScrollController.jumpTo(
              index: targetParagraphIndex, alignment: -alignment);
        } else {
          itemScrollController.scrollTo(
              index: targetParagraphIndex,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: -alignment);
        }
      } else {
        // Verse not found in layout, just jump to paragraph.
        itemScrollController.jumpTo(index: targetParagraphIndex);
      }
    } else {
      // Layout data is NOT ready.
      // 1. Set a pending scroll request.
      _pendingScrollRefinement = (
        book: targetBook,
        chapter: targetChapter,
        verse: targetVerse,
        paragraphIndex: targetParagraphIndex
      );
      // 2. Jump to the paragraph to ensure it gets built and laid out.
      itemScrollController.jumpTo(index: targetParagraphIndex, alignment: 0);
      // debugPrint(
      //     'Layout not ready for $targetBook $targetChapter:$targetVerse. Jumping to paragraph and waiting for layout.');
    }
    if (partOfScrollGroup && thisColumnNavigation) {
      Provider.of<ScrollGroup>(context, listen: false).setActiveColumnKey =
          widget.key;
      final ref = BibleReference(
          key: widget.key!,
          partOfScrollGroup: partOfScrollGroup,
          collectionID: currentCollection.value,
          bookID: targetBook,
          chapter: targetChapter,
          verse: targetVerse,
          columnIndex: widget.myColumnIndex);

      Provider.of<ScrollGroup>(context, listen: false).setScrollGroupRef = ref;
    }
  }

  //Function called on first open
  //and also from combobox selectors to go to a Bible reference
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
      if (int.parse(vs) < int.parse(chapters[ch])) {
        return true;
      } else {
        return false;
      }
    }

    bool checkIfRefIsInMemory(String bk, String ch, String vs) {
      // is the verse already in memory in versesInMemory?
      return versesInMemory.any(
          (line) => line.book == bk && line.chapter == ch && line.verse == vs);
    }

    if (toc.isEmpty) {
      await loadTOC();
    }
    bool refIsInCollection =
        await checkIfRefIsInCollection(targetBook, targetChapter, targetVerse);
    // if it is get the data and navigate to it
    if (refIsInCollection) {
      // Begins here:
      // If the collection is changing, we handle that as the primary case.
      collectionChanged =
          (currentCollection.value != collection || isInitState);
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
        // This handles book changes within the same collection.
        targetChapter = '1';
        targetVerse = '1';
      } else if (currentChapter.value != targetChapter) {
        // This handles chapter changes within the same book.
        targetVerse = '1';
      }

      bool verseIsInMemory =
          checkIfRefIsInMemory(targetBook, targetChapter, targetVerse);
      if (!verseIsInMemory || collectionChanged) {
        // Set loading state and clear old data to show skeletonizer
        setState(() {
          _isLoading = true;
        });

        // check if the reference we're trying to go to is in the collection

        // hit reset
        versesInMemory = [];
        versesByParagraph = [];
        currentParagraph = [];
        // get the initial chunk of data
        final fetchResult = await ChapterFetchService().getInitialChunk(
            collectionId: currentCollection.value,
            bookId: targetBook,
            chapter: int.parse(targetChapter));

        if (!mounted) return;

        final newParagraphs = _linesToParagraphs(fetchResult.lines);

        // finish up and return to the UI
        setState(() {
          versesInMemory = fetchResult.lines;
          versesByParagraph = newParagraphs;
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
        // }
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
      currentVerse.value = targetVerse;
      setUpComboBoxesChVs();
    } else {
      // if not, don't do anything, just stay there
    }
  }

  List<List<ParsedLine>> _linesToParagraphs(List<ParsedLine> lines) {
    List<List<ParsedLine>> paragraphs = [];
    List<ParsedLine> currentParagraph = [];

    for (var i = 0; i < lines.length; i++) {
      // If it's an intro line, create a new paragraph for it.
      if (lines[i].chapter == '0') {
        if (currentParagraph.isNotEmpty) {
          paragraphs.add(currentParagraph);
        }
        paragraphs.add([lines[i]]);
        currentParagraph = [];
        continue;
      }

      //If it is a new paragraph marker, add the existing verses to the big list, and start over with a new paragraph
      if (lines[i].verseStyle.contains(RegExp(
          r'[p,po,pr,cls,pmo,pm,pmc,pmr,pi\d,mi,nb,pc,ph\d,b,mt\d,mte\d,ms\d,mr,s\d*,sr,sp,sd\d,q,q1,q2,qr,qc,qa,qm\d,qd,lh,li\d,lf,lim\d]'))) {
        paragraphs.add(currentParagraph);
        currentParagraph = [lines[i]];
        //If it's a one line paragraph
      } else if ((lines[i].verseStyle.contains(RegExp(r'[m,r,d]')))) {
        paragraphs.add(currentParagraph);
        paragraphs.add([lines[i]]);
        currentParagraph = [];
      } else {
        //otherwise just add the line to the paragraph
        currentParagraph.add(lines[i]);
      }
    }
    //Get that last paragraph added!
    paragraphs.add(currentParagraph);
    return paragraphs;
  }

  // End scroll To Reference

  void setUpComboBoxesChVs() {
    try {
      // print('setUp ComboBoxesChVs');
      final bookData = toc[currentBook.value];
      if (bookData == null || bookData['chapters'] == null) return;

      final Map<String, dynamic> temp = bookData['chapters'];
      currentBookChapters = temp.keys.toList();

      String? numberOfVersesInCurrentChapter = temp[currentChapter.value];
      if (numberOfVersesInCurrentChapter == null) return;

      int verseCount = 0;
      if (numberOfVersesInCurrentChapter.contains('-')) {
        final parts = numberOfVersesInCurrentChapter.split('-');
        verseCount = int.tryParse(parts.last.trim()) ?? 0;
      } else {
        verseCount = int.tryParse(numberOfVersesInCurrentChapter) ?? 0;
      }

      currentChapterVerseNumbers = List.generate(verseCount, (int i) {
        return (i + 1).toString();
      });

      if (mounted) {
        setState(() {});
      }

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

  void addVerseToCopyRange(ParsedLine ref) {
    //This function fills in the gaps where there is poetry over many ParsedLines to get the whole verse despite the separation
    /*
    Xanaa dungeen bàyyee songandoo nit, 
    nar koo sànk, 
    ni kuy màbb tabax bu joy, 
    mbaa ngay bàddi per mu ràpp?  
      Sabóor 62.4-4 (Kàddug Yàlla)
     */
    addLinesBetweenIndexes() {
      int startIndex = 0;
      int endIndex = 0;

      /*add all between the first and last index. 
      Because the user can select up as well as down (select vs 5 then 1 as well as 1 and then 5)
      Check first which way round we're going */
      int oneEnd = versesInMemory.indexWhere((element) =>
          element.book == rangeOfVersesToCopy.first.book &&
          element.chapter == rangeOfVersesToCopy.first.chapter &&
          element.verse == rangeOfVersesToCopy.first.verse);

      int otherEnd = versesInMemory.indexWhere((element) =>
          element.book == rangeOfVersesToCopy.last.book &&
          element.chapter == rangeOfVersesToCopy.last.chapter &&
          element.verse == rangeOfVersesToCopy.last.verse);

      //See which way round the entries are - later verse first or earlier first
      int result = oneEnd.compareTo(otherEnd);
      if (result < 0) {
        startIndex = oneEnd;
        // endIndex = otherEnd;
        endIndex = versesInMemory.lastIndexWhere((element) =>
            element.book == rangeOfVersesToCopy.last.book &&
            element.chapter == rangeOfVersesToCopy.last.chapter &&
            element.verse == rangeOfVersesToCopy.last.verse);
      } else {
        startIndex = otherEnd;
        endIndex = versesInMemory.lastIndexWhere((element) =>
            element.book == rangeOfVersesToCopy.first.book &&
            element.chapter == rangeOfVersesToCopy.first.chapter &&
            element.verse == rangeOfVersesToCopy.first.verse);
      }
      rangeOfVersesToCopy = [];
      for (var i = startIndex; i <= endIndex; i++) {
        rangeOfVersesToCopy.add(versesInMemory[i]);
      }
    }

    //Start of function
    bool verseAlreadyInRange = rangeOfVersesToCopy.any((ParsedLine element) =>
        element.book == ref.book &&
        element.chapter == ref.chapter &&
        element.verse == ref.verse);

    // if there is only one verse, and the incoming verse is the same as the one that's in there, get rid of it.
    if (rangeOfVersesToCopy.length == 1 && verseAlreadyInRange) {
      rangeOfVersesToCopy = [];
    }
    // if vs not in range, add it and arrange the lines
    else if (!verseAlreadyInRange) {
      // // print('third case');
      //add this verse and then
      rangeOfVersesToCopy.add(ref);

      addLinesBetweenIndexes();
    }

    //if only 2 verses, and the one clicked is already in, remove it and any after it
    else if (verseAlreadyInRange) {
      int first = rangeOfVersesToCopy.indexWhere((element) =>
          element.book == ref.book &&
          element.chapter == ref.chapter &&
          element.verse == ref.verse);

      rangeOfVersesToCopy.removeRange(first, rangeOfVersesToCopy.length);
    }
    // if the verses to copy does not contain the ref that the user just sent, add all the refs between the first and last ref
    // This is the 'normal' case, where there is no selection yet

    //if the user has changed their minds and wants to shorten the list of verses to work with
    // else if (rangeOfVersesToCopy.length >= 2 && verseAlreadyInRange) {
    //   // // print('fourth option');
    //   // startIndex = versesInCollection.indexWhere((element) =>
    //   //     element.book == rangeOfVersesToCopy[0].book &&
    //   //     element.chapter == rangeOfVersesToCopy[0].chapter &&
    //   //     element.verse == rangeOfVersesToCopy[0].verse);

    //   // endIndex = versesInCollection.indexWhere((element) =>
    //   //     element.book == ref.book &&
    //   //     element.chapter == ref.chapter &&
    //   //     element.verse == ref.verse);
    //   // addVersesBetweenIndexes(startIndex, endIndex);
    // }
    setState(() {});
  }

  String? textToShareOrCopy() {
    // // print('textToShareOrCopy');
    String textToReturn = '';
    String reference = '';
    String lineBreak = '\n';

    //Get the text of the verses to share or copy
    if (rangeOfVersesToCopy.isEmpty) {
      return null;
    } else {
      for (var i = 0; i < rangeOfVersesToCopy.length; i++) {
        var temp = verseComposer(
                line: rangeOfVersesToCopy[i],
                includeFootnotes: false,
                context: context)
            .versesAsString;
        textToReturn = '$textToReturn$temp ';
      }

      //Now get the reference for the selection
      //Get collection name in regular text
      String currentCollectionName = collections
          .where((element) => element.id == currentCollection.value)
          .first
          .name;

      //Get the books
      if (rangeOfVersesToCopy.first.book == rangeOfVersesToCopy.last.book) {
        String bookName = currentCollectionBooks
            .where((element) => element.id == rangeOfVersesToCopy.first.book)
            .first
            .name;

        //only one verse: Genesis 1.1
        if (rangeOfVersesToCopy.length == 1) {
          reference =
              '$bookName ${rangeOfVersesToCopy.first.chapter}.${rangeOfVersesToCopy.first.verse}';
        }
        //same chapter: Genesis 1.2-10
        else if (rangeOfVersesToCopy.first.chapter ==
            rangeOfVersesToCopy.last.chapter) {
          reference =
              '$bookName ${rangeOfVersesToCopy.first.chapter}.${rangeOfVersesToCopy.first.verse}-${rangeOfVersesToCopy.last.verse}';
        } else {
          //same book different chapter: Genesis 1.20-2.2
          reference =
              '$bookName ${rangeOfVersesToCopy.first.chapter}.${rangeOfVersesToCopy.first.verse}-${rangeOfVersesToCopy.last.chapter}.${rangeOfVersesToCopy.last.verse}';
        }
      } else {
        // range is across books so just take first and last
        String firstBookName = currentCollectionBooks
            .where((element) => element.id == rangeOfVersesToCopy.first.book)
            .first
            .name;
        String lastBookName = currentCollectionBooks
            .where((element) => element.id == rangeOfVersesToCopy.last.book)
            .last
            .name;

        //Genesis 50.30-Exodus 1.20
        reference =
            '$firstBookName ${rangeOfVersesToCopy.first.chapter}.${rangeOfVersesToCopy.first.verse}-$lastBookName ${rangeOfVersesToCopy.last.chapter}.${rangeOfVersesToCopy.last.verse}';
      }

      textToReturn =
          '$textToReturn$lineBreak$reference ($currentCollectionName)';
      rangeOfVersesToCopy = [];
      setState(() {});
      return textToReturn;
    }
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
    // // print(
    //     'scripture column build: columnIndex: ${widget.bibleReference.columnIndex}; collection: ${widget.bibleReference.collectionID}; key: ${widget.key}');

    //Couple of things to get to pass in to the Paragraph Builder

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
                                        value != null
                                            ? scrollToReference(
                                                collection: value,
                                                bookID: currentBook.value,
                                                chapter: currentChapter.value,
                                                verse: currentVerse.value,
                                                thisColumnNavigation: true)
                                            : null;
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
                                        items: currentBookChapters
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
                                        placeholder: const Text('150'),
                                        isExpanded: true,
                                        items: currentChapterVerseNumbers
                                            .toSet()
                                            .toList()
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
                                            scrollToReference(
                                                collection:
                                                    currentCollection.value,
                                                bookID: currentBook.value,
                                                chapter: currentChapter.value,
                                                verse: value,
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
              child: Container(
                decoration: const BoxDecoration(
                  //This is the border between each scripture column and its neighbor to the right
                  border: Border(
                    right: BorderSide(
                      width: 1.0,
                      color: Color.fromARGB(85, 126, 126, 126),
                    ),
                  ),
                ),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    // When a user starts a drag/scroll gesture on this column,
                    // designate it as the leader of the scroll group.
                    if (notification is ScrollStartNotification &&
                        notification.dragDetails != null) {
                      if (partOfScrollGroup) {
                        Provider.of<ScrollGroup>(context, listen: false)
                            .setActiveColumnKey = widget.key;
                      }
                    }
                    return true; // Allow notification to continue bubbling up
                  },
                  child: ContextMenuRegion(
                    contextMenu: GenericContextMenu(
                      buttonConfigs: [
                        ContextMenuButtonConfig(
                          Provider.of<UserPrefs>(context, listen: false)
                              .currentTranslation
                              .copy,
                          icon: const Icon(FluentIcons.copy),
                          onPressed: () {
                            String? text = textToShareOrCopy();

                            if (text != null) {
                              Clipboard.setData(ClipboardData(text: text));
                            }
                          },
                        ),
                        ContextMenuButtonConfig(
                          Provider.of<UserPrefs>(context, listen: false)
                              .currentTranslation
                              .share,
                          icon: const Icon(FluentIcons.share),
                          onPressed: () async {
                            String? text = textToShareOrCopy();

                            if (text != null) {
                              //if it's not the web app, share using the device share function

                              if (!kIsWeb) {
                                SharePlus.instance
                                    .share(ShareParams(text: text));
                              } else {
                                //If it's the web app version best way to share is probably email, so put the text to share in an email
                                final String url =
                                    "mailto:?subject=&body=$text";

                                if (await canLaunchUrl(Uri.parse(url))) {
                                  await launchUrl(Uri.parse(url));
                                } else {
                                  throw 'Could not launch $url';
                                }
                              }
                            }
                          },
                        )
                      ],
                    ),
                    child: Skeletonizer(
                      enabled: _isLoading,
                      child: LayoutBuilder(builder: (context, constraints) {
                        _viewportHeight = constraints.maxHeight;
                        return scrollablePositionedList =
                            ScrollablePositionedList.builder(
                                //this is the space between the right of the column and the text for the scrollbar
                                padding: const EdgeInsets.only(right: 10),
                                initialAlignment: 1,
                                itemScrollController: itemScrollController,
                                itemPositionsListener: itemPositionsListener,
                                itemCount: _isLoading
                                    ? 4
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
                                                '     Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc auctor nec diam sed egestas. Vestibulum volutpat mollis massa at faucibus. Proin eros urna, pellentesque sit amet mattis id, sollicitudin blandit tortor. Mauris vel ipsum id ipsum auctor lacinia sed at neque. Pellentesque ut malesuada dui, eget blandit est. Fusce lacinia sit amet magna eget viverra. Donec eu orci pharetra, molestie augue non, fermentum enim. Suspendisse mollis tempus sem sit amet pretium. Morbi tempor, ante finibus euismod maximus, massa justo tempus magna, eget commodo nulla turpis vel orci. Duis consequat pellentesque magna finibus malesuada. Nunc porttitor iaculis odio, id congue purus scelerisque vitae. Integer at orci et dolor placerat condimentum quis in odio. Donec ornare rhoncus dignissim. Donec nec est sit amet nisl iaculis fringilla id id diam.',
                                            verseStyle: 'p')
                                      ],
                                      addDivider: false,
                                      fontName: 'Charis',
                                      textDirection: ui.TextDirection.ltr,
                                      fontSize: 20,
                                      rangeOfVersesToCopy: const [],
                                      addVerseToCopyRange: dummy,
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

                                  bool addDivider = false;
                                  try {
                                    if (i != 0 &&
                                        versesByParagraph[i].isNotEmpty &&
                                        versesByParagraph[i].first.chapter ==
                                            '0' &&
                                        versesByParagraph[i - 1]
                                                .first
                                                .chapter !=
                                            '0') {
                                      addDivider = true;
                                    }
                                  } catch (e) {
                                    debugPrint(
                                        'Error ascertaining whether it\'s the first of an intro');

                                    debugPrint(e.toString());
                                  }

                                  return ParagraphBuilder(
                                    paragraph: versesByParagraph[paraIndex],
                                    addDivider: addDivider,
                                    fontSize: baseFontSize,
                                    fontName: fontName,
                                    textDirection: textDirection,
                                    rangeOfVersesToCopy: rangeOfVersesToCopy,
                                    addVerseToCopyRange: addVerseToCopyRange,
                                    onLayoutCalculated: (offsets) {
                                      _paragraphLayouts[paraIndex] = offsets;
                                      _attemptScrollRefinement(paraIndex);
                                    },
                                  );
                                });
                      }),
                    ),
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
