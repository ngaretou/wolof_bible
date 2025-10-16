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
  ItemPositionsListener itemPositionsListener = ItemPositionsListener.create();
  late ScrollablePositionedList scrollablePositionedList;

  int? delayedScrollIndex;
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

  // State flags for loading indicators
  bool _isLoading = false;
  bool _isFetchingNext = false;
  bool _isFetchingPrevious = false;

  Future<void> loadTOC() async {
    try {
      final path = 'assets/json/${currentCollection.value}_toc.json';
      final jsonString = await rootBundle.loadString(path);
      toc = json.decode(jsonString);
    } catch (e) {
      debugPrint(e.toString()); // TOC not found or failed to parse
    }
  }

  @override
  void initState() {
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
        isInitState: true);

    super.initState();
  }

  void _updateTopVerse() {
    final positions = itemPositionsListener.itemPositions.value;
    if (positions.isEmpty || !mounted) return;

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
    _updateTopVerse();

    final positions = itemPositionsListener.itemPositions.value;
    if (positions.isEmpty || !mounted) return;

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

  //Function called on first open
  //and also from combobox selectors to go to a Bible reference
  Future<void> scrollToReference(
      {String? collection,
      required String bookID,
      required String chapter,
      required String verse,
      bool isInitState = false}) async {
    // If the collection is changing, update it and load the new TOC first.
    if (collection != null && currentCollection.value != collection) {
      currentCollection.value = collection;
      await loadTOC();
    }

    // Sanitize the target reference based on context.
    var targetBook = bookID;
    var targetChapter = chapter;
    var targetVerse = verse;

    if (currentBook.value != targetBook) {
      // Book is changing, so always navigate to chapter 1, verse 1 of the new book.
      targetChapter = '1';
      targetVerse = '1';
    } else if (currentChapter.value != targetChapter) {
      // Chapter is changing within the same book, so just reset the verse.
      targetVerse = '1';
    }

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
      if (int.parse(vs) < int.parse(chapters[vs])) {
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

    Future<void> refNotInCollection() async {
      void goToBeginning() {
        //our column has a ref but something is wrong - go to first ref in collection
        currentBook.value = currentCollectionBooks[0].id;

        currentChapter.value = '1';
        currentVerse.value = '1';
        scrollToReference(
            bookID: currentBook.value,
            chapter: currentChapter.value,
            verse: currentVerse.value);
      }
      //if our column has a ref, try to stay at it -
      //this is when a NT does not have an OT book but you're trying to scroll to it

      List<BibleReference> userColumns =
          Provider.of<UserPrefs>(context, listen: false).userColumns;

      BibleReference? savedBibleRefForThisColumn = userColumns
          .firstWhere((element) => element.key == widget.bibleReference.key);

      /*We're here b/c we're trying to scroll to a ref not in the collection
          If there is an existing ref for this column, let's try to scroll to it*/
      try {
        //Just to be on the safe side check to make sure that ref does in fact exist.
        bool refIsInCollection = await checkIfRefIsInCollection(
            savedBibleRefForThisColumn.bookID,
            savedBibleRefForThisColumn.chapter,
            savedBibleRefForThisColumn.verse);
        //If it does exist, then go ahead and navigate
        if (refIsInCollection) {
          currentBook.value = savedBibleRefForThisColumn.bookID;
          currentChapter.value = savedBibleRefForThisColumn.chapter;
          currentVerse.value = savedBibleRefForThisColumn.verse;
          scrollToReference(
              bookID: currentBook.value,
              chapter: currentChapter.value,
              verse: currentVerse.value);
        }
      } catch (e) {
        debugPrint(e.toString());
        //This is we've tried to navigate to a ref, it doesn't exist,
        //and we checked for an existing ref, it also doesn't exist:
        goToBeginning();
      }
    }

    bool verseIsInMemory =
        checkIfRefIsInMemory(targetBook, targetChapter, targetVerse);
    if (!verseIsInMemory) {
      // Set loading state and clear old data to show skeletonizer
      setState(() {
        _isLoading = true;
        versesInMemory = [];
        versesByParagraph = [];
        currentParagraph = [];
      });

      FetchResult fetchResult = await ChapterFetchService().getInitialChunk(
          collectionId: currentCollection.value,
          bookId: targetBook,
          chapter: int.parse(targetChapter));
      versesInMemory = fetchResult.lines;

      //Books in current collection
      currentCollectionBooks = widget.collections
          .where((element) => element.id == currentCollection.value)
          .toList()[0]
          .books;

      versesByParagraph = _linesToParagraphs(versesInMemory);

      // Find the paragraph to scroll to *after* loading.
      final targetParagraphIndex = versesByParagraph.indexWhere(
        (p) => p.any((l) =>
            l.book == targetBook &&
            l.chapter == targetChapter &&
            l.verse == targetVerse),
      );

      setState(() {
        _isLoading = false;
      });

      // Scroll to the target paragraph after the list has been built.
      if (targetParagraphIndex != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            itemScrollController.jumpTo(index: targetParagraphIndex);
          }
        });
      }

      //Verses in order;
      //Now figure out where we're going
      if (!mounted) return;
      BibleReference? scrollCollectionRef =
          Provider.of<ScrollGroup>(context, listen: false).getScrollGroupRef;

      //Now we have three different cases -
      //if there is a scroll ref and this column is part of the group, scroll to it;
      //if bk, ch, vs all not null go to that indicated passage;
      //go to first ref in collection if neither of those are true

      if (scrollCollectionRef != null && partOfScrollGroup) {
        //Check to see if the scrollCollectionRef is in the collection
        // checkIfRefIsInCollection sets the currentRef valuenotifiers if found
        bool refIsInCollection = await checkIfRefIsInCollection(
            scrollCollectionRef.bookID,
            scrollCollectionRef.chapter,
            scrollCollectionRef.verse);

        // print(            'navigateToParagraph in collection change is $navigateToParagraph');
        if (refIsInCollection) {
          currentBook.value = scrollCollectionRef.bookID;
          currentChapter.value = scrollCollectionRef.chapter;
          currentVerse.value = scrollCollectionRef.verse;
          scrollToReference(
              bookID: currentBook.value,
              chapter: currentChapter.value,
              verse: currentVerse.value);
        } else {
          refNotInCollection();
        }
      }
    } else {
      // Verse is in memory, so find the paragraph it's in and scroll to that.
      final targetParagraphIndex = versesByParagraph.indexWhere(
        (p) => p.any((l) =>
            l.book == targetBook &&
            l.chapter == targetChapter &&
            l.verse == targetVerse),
      );

      if (targetParagraphIndex != -1) {
        // This brings the correct paragraph into view. A more precise scroll
        // to the exact verse within the paragraph is a complex future enhancement.
        itemScrollController.jumpTo(index: targetParagraphIndex);
      }
    }

    // if (isInitState || navigateToParagraph > versesByParagraph.length) {
    //   //If going from a short NT only collection to full Bible, at this point the scrollablePositionedList
    //   //hasn't rebuilt and so a scroll will fail. Set a ref here to scroll in the post frame callback
    //   delayedScrollIndex = navigateToParagraph;
    // } else {
    //   // // print('set ActiveColumnKey1');
    //   Provider.of<ScrollGroup>(context, listen: false).setActiveColumnKey =
    //       widget.key;
    //   // Navigate to the paragraph. This is the collection change section.
    //   itemScrollController.scrollTo(
    //     index: navigateToParagraph,
    //     duration: const Duration(milliseconds: 200),
    //   );
    // }
    //  if (isInitState || navigateToParagraph > versesByParagraph.length) {
    //If going from a short NT only collection to full Bible, at this point the scrollablePositionedList
    //hasn't rebuilt and so a scroll will fail. Set a ref here to scroll in the post frame callback
    // delayedScrollIndex = navigateToParagraph;

    // } else {
    // // print('set ActiveColumnKey1');
    // Provider.of<ScrollGroup>(context, listen: false).setActiveColumnKey =
    //     widget.key;
    // Navigate to the paragraph. This is the collection change section.
    // itemScrollController.scrollTo(
    //   index: navigateToParagraph,
    //   duration: const Duration(milliseconds: 200),
    // );
    // }

    // Update the ValueNotifiers to reflect the final navigation state.
    currentBook.value = targetBook;
    currentChapter.value = targetChapter;
    currentVerse.value = targetVerse;

    setUpComboBoxesChVs();
    //Above is collection change, which resets the whole column.
  }

  List<List<ParsedLine>> _linesToParagraphs(List<ParsedLine> lines) {
    List<List<ParsedLine>> paragraphs = [];
    List<ParsedLine> currentParagraph = [];

    for (var i = 0; i < lines.length; i++) {
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
        Provider.of<UserPrefs>(context, listen: false).saveScrollGroupState(ref);
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

  @override
  Widget build(BuildContext context) {
    Key? activeColumnKey = context.read<ScrollGroup>().getActiveColumnKey;
    ScrollGroup scrollGroup = Provider.of<ScrollGroup>(context, listen: false);
    // // print(
    //     'scripture column build: columnIndex: ${widget.bibleReference.columnIndex}; collection: ${widget.bibleReference.collectionID}; key: ${widget.key}');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      //if switching from an NT only collection with few paragraphs to a longer full Bible collection
      //it will fail if it tries to scroll before the scrollablePositionedList is rebuilt.
      //Set above, this delayedScrollIndex scrolls after build to the index in such a situation

      if (delayedScrollIndex != null) {
        scrollGroup.setActiveColumnKey = widget.key;
        try {
          itemScrollController.jumpTo(index: delayedScrollIndex!);
        } catch (e) {
          // print('$e at scripcol postframecallback');
        }

        delayedScrollIndex = null;
      }

      //This is what triggers the scrolling in other columns
      if (!mounted) return;
      BibleReference? scrollGroupRef =
          context.read<ScrollGroup>().getScrollGroupRef;

      if (partOfScrollGroup &&
          scrollGroupRef != null &&
          activeColumnKey != widget.key) {
        if (currentBook.value != scrollGroupRef.bookID ||
            currentChapter.value != scrollGroupRef.chapter ||
            currentVerse.value != scrollGroupRef.verse) {
          scrollToReference(
              bookID: scrollGroupRef.bookID,
              chapter: scrollGroupRef.chapter,
              verse: scrollGroupRef.verse);
        }
      }
    });

    // int numberOfColumns =
    //     Provider.of<UserPrefs>(context, listen: false).userColumns.length;

    // double windowWidth = MediaQuery.of(context).size.width;

    // if (windowWidth > 1024 && numberOfColumns == 1) {
    //   wideWindow = true;
    //   wideWindowPadding = windowWidth / 5;
    // } else {
    //   wideWindow = false;
    // }

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

    //value notifier that triggers update when scrollgroup ref changes
    context.watch<ScrollGroup>().getScrollGroupRef;

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
                                        scrollToReference(
                                            collection: value,
                                            bookID: currentBook.value,
                                            chapter: currentChapter.value,
                                            verse: currentVerse.value);
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
                                              verse: currentVerse.value);
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
                                                verse: currentVerse.value);
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
                                                verse: value);
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
            child: NotificationListener(
              onNotification: (ScrollNotification notification) {
                // We now use the ItemPositionsListener for scroll detection,
                // so this listener is less critical, but we can keep it for now.
                return true;
              },
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
                  child: Listener(
                    onPointerDown: (_) {
                      // When the user interacts with this column, make it the active one
                      // for the purpose of leading a scroll group.
                      if (partOfScrollGroup) {
                        Provider.of<ScrollGroup>(context, listen: false)
                            .setActiveColumnKey = widget.key;
                      }
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
                                      ? 10
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
                                              verseText: '...',
                                              verseStyle: 'p')
                                        ],
                                        fontName: 'Saran',
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

                                    return ParagraphBuilder(
                                      paragraph: versesByParagraph[paraIndex],
                                      fontSize: baseFontSize,
                                      fontName: fontName,
                                      textDirection: textDirection,
                                      rangeOfVersesToCopy: rangeOfVersesToCopy,
                                      addVerseToCopyRange: addVerseToCopyRange,
                                      onLayoutCalculated: (offsets) {
                                        _paragraphLayouts[paraIndex] = offsets;
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
          ),
        ],
      ),
    );
  }
}
