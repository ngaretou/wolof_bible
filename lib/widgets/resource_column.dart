import 'dart:async';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:wolof_bible/main.dart';
import 'package:wolof_bible/widgets/resource_chooser.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:provider/provider.dart';
import 'package:wolof_bible/widgets/content_tile.dart';
import '../providers/user_prefs.dart';
import '../widgets/column_header.dart';
import '../logic/aquifer_api.dart';
import '../providers/aquifer_classes.dart';
import '../providers/column_manager.dart';
import '../logic/chapter_fetch_service.dart';

class ResourceColumn extends StatefulWidget {
  final BibleReference bibleReference;
  final int incomingUserResourceLanguageCode;
  final Function(Key) deleteColumn;

  const ResourceColumn({
    super.key,
    required this.bibleReference,
    required this.deleteColumn,
    this.incomingUserResourceLanguageCode = 4,
  });

  @override
  State<ResourceColumn> createState() => _ResourceColumnState();
}

class _ResourceColumnState extends State<ResourceColumn> {
  // data
  AquiferService aquiferService = AquiferService();
  final List<ResourceItem> _resourceItems = [];
  ScrollGroup? _scrollGroup;
  late Future initialization;
  List<ResourceCollectionInfo> collections = [];
  List<ResourceCollectionInfo> selectedCollections = [];
  List<String> userResourceCodes = [];
  late ResourceLanguage language;
  List<ResourceLanguage> languages = [];
  StreamSubscription<ResourceItem>? _resourceSubscription;
  String currentBookID = 'GEN';
  String currentChapter = '1';
  int userResourceLanguageCode = 4;
  Map<String, dynamic> toc = {}; // Store the Table of Contents
  // UI
  final ItemScrollController itemScrollController = ItemScrollController();
  final ItemPositionsListener itemPositionsListener =
      ItemPositionsListener.create();
  // Track the range of loaded content for infinite scroll
  ChapterInfo? _firstLoaded;
  ChapterInfo? _lastLoaded;
  // Text
  TextOverflow textOverflow = TextOverflow.ellipsis;
  Alignment alignment = Alignment.centerLeft;
  TextDirection textDirection = TextDirection.ltr;
  double baseFontSize = 20;
  // flags
  bool _isProgrammaticScroll = false;
  bool _isOnline = true;
  bool _shouldCheckConnectivity = true;
  bool isLinked = true;
  bool _loadingLanguage = true;
  bool _isScrollGroupListenerInitialized = false;
  // initial load or jumping references load - has effect on UI - only used momentarily
  bool _loadingResources = true;
  // fetching resources on the fly - has no effect on UI
  bool _isFetching = true;
  bool _isFetchingPrevious = false;

  String dummyContent =
      'These verses introduce the Pentateuch (Genesis—Deuteronomy) and teach Israel that the world was created, ordered, and populated by the one true God and not by the gods of surrounding nations. God blessed three specific things: animal life (1:22-25), human life (1:27), and the Sabbath day (2:3). This trilogy of blessings highlights the Creator’s plan: Humankind was made in God’s image to enjoy sovereign dominion over the creatures of the earth and to participate in God’s Sabbath rest.';

  @override
  void dispose() {
    _resourceSubscription?.cancel();
    if (_isScrollGroupListenerInitialized) {
      _scrollGroup?.removeListener(_onScrollGroupChanged);
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isScrollGroupListenerInitialized) {
      _scrollGroup = Provider.of<ScrollGroup>(context, listen: false);
      _scrollGroup!.addListener(_onScrollGroupChanged);
      _isScrollGroupListenerInitialized = true;
    }
  }

  void _onScrollGroupChanged() {
    if (!isLinked) return;

    final groupRef = _scrollGroup!.getScrollGroupRef;
    if (groupRef == null) return;

    // Check if we are the active column driving the change
    final activeKey = _scrollGroup!.getActiveColumnKey;
    if (activeKey == widget.key) return;

    // 1. Check for Book/Chapter Change
    if (groupRef.bookID != currentBookID ||
        groupRef.chapter != currentChapter) {
      setState(() {
        currentBookID = groupRef.bookID;
        currentChapter = groupRef.chapter;
        // Reset loaded tracking on manual/sync navigation
        _firstLoaded = ChapterInfo(currentBookID, int.parse(currentChapter));
        _lastLoaded = ChapterInfo(currentBookID, int.parse(currentChapter));
      });
      _fetchResources().then((_) {
        // After fetching, scroll to the specific verse
        _scrollToVerse(groupRef.bookID, groupRef.chapter, groupRef.verse);
      });
    } else {
      // 2. Same Chapter, just scroll to verse
      _scrollToVerse(groupRef.bookID, groupRef.chapter, groupRef.verse);
    }
  }

  void _scrollToVerse(String bookID, String chapter, String verse) {
    if (_resourceItems.isEmpty) return;

    final int targetBookNum = _bookCodeToNumber(bookID);
    final int targetChapter = int.tryParse(chapter) ?? 0;
    final int targetVerse = int.tryParse(verse) ?? 0;

    // Find index of first resource with verse >= targetVerse
    // AND matching book/chapter if we strictly enforce it
    // (though list should mostly differ by verse)
    int index = _resourceItems.indexWhere((item) {
      // Logic:
      // 1. Check book matching (approx via code)
      // 2. Check chapter
      // 3. Check verse >= target

      final itemBookNum = _bookCodeToNumber(item.bookID);

      return itemBookNum == targetBookNum &&
          item.chapter == targetChapter &&
          item.verse == targetVerse;

      // below original Antigravity version

      // if (itemBookNum < targetBookNum) return false;
      // if (itemBookNum > targetBookNum) return true; // Passed it?

      // if (item.chapter < targetChapter) return false;
      // if (item.chapter > targetChapter) return true; // Passed it?

      // return item.verse == targetVerse;
      // return item.verse <= targetVerse;
    });

    // so that we'll only scroll when we get to or past the target
    // otherwise if notes on vv 14 and then 16, it will scroll to 16 when you get to 15
    // 2 Corinthians 13.7 (8-9) 10
    // it's ok not to scroll.
    if (index != -1) {
      _isProgrammaticScroll = true;
      // itemScrollController.jumpTo(index: index);
      print('scrolling _scrollToVerse');
      itemScrollController.scrollTo(
        duration: Duration(milliseconds: 200),
        index: index,
      );
      Future.delayed(const Duration(milliseconds: 1000), () {
        _isProgrammaticScroll = false;
      });
    }
  }

  int _bookCodeToNumber(String code) {
    final numStr = AquiferService.bookCodeToNumber[code];
    return int.tryParse(numStr ?? '') ?? 0;
  }

  Future<void> init() async {
    await _loadTOC();
    setLanguage();
  }

  Future<void> _loadTOC() async {
    // Use C01 as default structure for navigation
    toc = await ChapterFetchService().getCollectionToc('C01');
  }

  @override
  void initState() {
    currentBookID = widget.bibleReference.bookID;
    currentChapter = widget.bibleReference.chapter;

    // Initialize loaded range
    final chInt = int.tryParse(currentChapter) ?? 1;
    _firstLoaded = ChapterInfo(currentBookID, chInt);
    _lastLoaded = ChapterInfo(currentBookID, chInt);

    userResourceLanguageCode = widget.incomingUserResourceLanguageCode;
    languages = AquiferService().allLanguages.toList();
    isLinked = widget.bibleReference.partOfScrollGroup;
    initialization = init();

    itemPositionsListener.itemPositions.addListener(_handleScroll);

    if (userPrefsBox.get('userConnectivityChoice') == null) {
      _shouldCheckConnectivity = true;
      _checkConnectivity(); // to set _is Online
    } else {
      _isOnline = userPrefsBox.get('userConnectivityChoice');
      _shouldCheckConnectivity = _isOnline;
      _checkConnectivity(); // will check to see if shouldcheck
    }
    super.initState();
  }

  void _handleScroll() {
    if (_isProgrammaticScroll || _isFetching) {
      return;
    }
    print('_handleScroll');

    final positions = itemPositionsListener.itemPositions.value;
    if (positions.isEmpty || !mounted) return;

    // Find top item
    final topItem = positions.reduce(
      (min, pos) => pos.itemLeadingEdge < min.itemLeadingEdge ? pos : min,
    );

    final index = topItem.index;

    // Infinite Scroll Logic
    final lastVisibleIndex = positions
        .map((p) => p.index)
        .reduce((max, p) => p > max ? p : max);
    // REMOVED: firstVisibleIndex calculation - unused now that previous chapter trigger is moved.

    // Fetch Next
    if (!_isFetching && _resourceItems.length - lastVisibleIndex < 5) {
      _fetchNextChapter();
    }

    // Fetch Previous
    // Moved to NotificationListener (Overscroll) to prevent auto-loading
    // if (!_isFetching && firstVisibleIndex < 5) {
    //   _fetchPreviousChapter();
    // }

    if (index >= 0 && index < _resourceItems.length) {
      final item = _resourceItems[index];

      if (isLinked) {
        final currentRef = _scrollGroup!.getScrollGroupRef;
        // Only update if significantly different (e.g. verse changed)
        if (currentRef != null &&
            (currentRef.verse != item.verse.toString() ||
                currentRef.bookID != item.bookID ||
                currentRef.chapter != item.chapter.toString())) {
          // User requested to disable resource column leading to debug overactive scrolling.
          // _scrollGroup!.setActiveColumnKey = widget.key;

          // final ref = BibleReference(
          //  key: widget.bibleReference.key,
          //  partOfScrollGroup: true,
          //  collectionID: widget.bibleReference.collectionID,
          //  bookID: item.bookID,
          //  chapter: item.chapter.toString(),
          //  verse: item.verse.toString(),
          //  columnIndex: widget.bibleReference.columnIndex,
          // );
          // _scrollGroup!.setScrollGroupRef = ref;
        }
      }
    }
  }

  Future<void> _fetchNextChapter() async {
    if (_isFetching || toc.isEmpty || _lastLoaded == null) {
      return;
    }

    // Calculate next chapter
    final nextInfo = ChapterFetchService().getNextChapterInfo(
      toc,
      toc.keys.toList(),
      _lastLoaded!,
    );

    if (nextInfo == null) return;

    _isFetching = true;

    try {
      // Create a temporary subscription to get the list
      List<ResourceItem> newItems = [];
      await AquiferService()
          .streamResourcesForChapter(
            connected: _isOnline,
            langId: userResourceLanguageCode,
            resourceCollectionCodes: userResourceCodes,
            book: nextInfo.bookId,
            chapter: nextInfo.chapter.toString(),
          )
          .forEach((item) {
            // Deduplicate: Don't add if already in the list
            if (!_resourceItems.any((existing) => existing.id == item.id)) {
              newItems.add(item);
            }
          });

      if (mounted) {
        setState(() {
          _lastLoaded = nextInfo; // Update tracker
          if (newItems.isNotEmpty) {
            _resourceItems.addAll(newItems);
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching next chapter resources: $e');
    } finally {
      _isFetching = false;
    }
  }

  Future<void> _fetchPreviousChapter() async {
    // return;
    if ((_isFetching || toc.isEmpty || _firstLoaded == null)) {
      return;
    }
    print('fetching previous chapter');

    final prevInfo = ChapterFetchService().getPreviousChapterInfo(
      toc,
      toc.keys.toList(),
      _firstLoaded!,
    );

    if (prevInfo == null) return;

    _isFetching = true;
    if (mounted) {
      setState(() {
        _isFetchingPrevious = true;
      });
    }

    try {
      List<ResourceItem> newItems = [];
      await AquiferService()
          .streamResourcesForChapter(
            connected: _isOnline,
            langId: userResourceLanguageCode,
            resourceCollectionCodes: userResourceCodes,
            book: prevInfo.bookId,
            chapter: prevInfo.chapter.toString(),
          )
          .forEach((item) {
            // Deduplicate: Don't add if already in the list
            if (!_resourceItems.any((existing) => existing.id == item.id)) {
              newItems.add(item);
            }
          });

      if (mounted) {
        // Logic: Insert items, then jump to (index + addedCount)
        // We do this even if newItems is empty? No, only if newItems.

        // Update tracker regardless?
        // Yes, to prevent re-fetching.

        _firstLoaded = prevInfo;

        if (newItems.isNotEmpty) {
          final addedCount = newItems.length;

          // Get current top item to restore position
          final positions = itemPositionsListener.itemPositions.value;
          if (positions.isNotEmpty) {
            final topItem = positions.reduce(
              (min, pos) =>
                  pos.itemLeadingEdge < min.itemLeadingEdge ? pos : min,
            );
            final oldIndex = topItem.index;
            final oldOffset = topItem.itemLeadingEdge;

            setState(() {
              _resourceItems.insertAll(0, newItems);
              _isFetchingPrevious = false;
            });

            // Restore position
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _isProgrammaticScroll = true;
                print('Restoring position');

                itemScrollController.jumpTo(
                  index: oldIndex + addedCount,
                  alignment: oldOffset,
                );
                _isProgrammaticScroll = false;
              }
            });
          } else {
            setState(() {
              _resourceItems.insertAll(0, newItems);
              _isFetchingPrevious = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching previous chapter resources: $e');
    } finally {
      _isFetching = false;
    }
  }

  Future<void> _checkConnectivity() async {
    // don't check on web
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _isOnline = true;
        });
      }
      return;
    }

    if (!_shouldCheckConnectivity) {
      if (mounted && _isOnline == true) {
        setState(() {
          _isOnline = false;
        });
      }
      return;
    }
    final isOnline = await AquiferService().checkConnectivity();
    if (mounted) {
      setState(() {
        _isOnline = isOnline;
      });
    }
  }

  Future<void> setLanguage() async {
    setState(() {
      _loadingLanguage = true;
    });
    collections.clear();
    collections = AquiferService().getResourcesForLanguage(
      userResourceLanguageCode,
    );
    userResourceCodes.clear();
    final savedCodes = userPrefsBox.get(
      'resource_prefs_$userResourceLanguageCode',
    );
    if (savedCodes != null) {
      userResourceCodes = List<String>.from(savedCodes);
    }

    // Fallback: If no codes selected (empty saved list or no save), try defaults
    if (userResourceCodes.isEmpty) {
      userResourceCodes = collections
          .where((c) => c.code.startsWith('Tyndale'))
          .map((c) => c.code)
          .toList();
    }

    // Safety net: If still empty but we have collections, select the first one
    if (userResourceCodes.isEmpty && collections.isNotEmpty) {
      userResourceCodes.add(collections.first.code);
    }
    language = AquiferService().allLanguages.firstWhere(
      (l) => l.id == userResourceLanguageCode,
      orElse: () => AquiferService().allLanguages.first,
    );
    if (language.scriptDirection == 'LTR') {
      textDirection = TextDirection.ltr;
      alignment = Alignment.centerLeft;
    } else {
      textDirection = TextDirection.rtl;
      alignment = Alignment.centerRight;
    }
    // update the content after lang is changed
    setState(() {
      _loadingLanguage = false;
    });
    updateContent();
  }

  // Initial fetch of resources.
  Future<void> _fetchResources() async {
    await _resourceSubscription?.cancel();
    _resourceItems.clear();

    if (userResourceCodes.isEmpty) {
      setState(() {
        _loadingResources = false;
        _isFetching = false;
      });
      return;
    }

    setState(() {
      print('fetching resources');
      _loadingResources = true;
      _isFetching = true;
    });

    try {
      _resourceSubscription = AquiferService()
          .streamResourcesForChapter(
            connected: _isOnline,
            langId: userResourceLanguageCode,
            resourceCollectionCodes: userResourceCodes,
            book: currentBookID,
            chapter: currentChapter,
          )
          .listen(
            (item) {
              if (mounted) {
                setState(() {
                  if (_loadingResources) {
                    _loadingResources = false;
                  }
                  _resourceItems.add(item);
                });
              }
            },
            onError: (e) {
              debugPrint('Error fetching resources: $e');
              if (mounted) {
                setState(() {
                  _loadingResources = false;
                });
              }
            },
            onDone: () async {
              debugPrint('End of fetching initial chapter');
              // Previous chapter will now only load via _handleScroll when viewing top.
              _loadingResources = false;
              _isFetching = false;
            },
          );
    } catch (e) {
      debugPrint('Error starting resource stream: $e');
      if (mounted) {
        setState(() {
          _loadingResources = false;
        });
      }
    }
  }

  void updateContent() {
    if (_isOnline) {
      userPrefsBox.put(
        'resource_prefs_$userResourceLanguageCode',
        userResourceCodes,
      );
    }

    _fetchResources(); // Fetch resources when content is updated
  }

  Widget _buildLoadingResources() {
    List<ResourceItem> dummyResourceItems = List.generate(
      5,
      (index) => ResourceItem(
        id: index.toString(),
        resourceCollectionCode: 'TyndaleStudyNotes',
        localizedName: 'Dummy Resource Name',
        resourceType: ResourceType.studyNotes,
        content: dummyContent,
        langID: 1,
        scriptDirection: 'LTR',
      ),
    );
    return Skeletonizer(
      enabled: true,
      child: ScrollablePositionedList.builder(
        shrinkWrap: true,
        itemCount: dummyResourceItems.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text(
                  dummyResourceItems[index].localizedName,
                  style: TextStyle(fontSize: baseFontSize + 2),
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                Text(dummyResourceItems[index].content),
              ],
            ),
          );
        },
        itemScrollController: itemScrollController,
        itemPositionsListener: itemPositionsListener,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: initialization,
      builder: (context, asyncSnapshot) {
        //
        if (asyncSnapshot.connectionState != ConnectionState.done) {
          return Expanded(
            child: Column(
              children: [
                ColumnHeader(
                  leadingControls: [
                    SizedBox(
                      width: 160,
                      height: 34,
                      child: Center(child: ProgressBar()),
                    ),
                  ],
                  onFontIncrease: () {},
                  onFontDecrease: () {},
                  isLinked: false,
                  onLinkChanged: (_) {},
                  onDelete: () {},
                ),
                Expanded(child: _buildLoadingResources()),
              ],
            ),
          );
        } else {
          return Expanded(
            child: Column(
              children: [
                ColumnHeader(
                  leadingControls: [
                    SizedBox(
                      width: 160,
                      height: 34,
                      // language chooser
                      child: _loadingLanguage
                          ? Center(child: ProgressBar())
                          // resource language chooser
                          : ComboBox<int>(
                              isExpanded: true,
                              value: userResourceLanguageCode,
                              onChanged: (v) async {
                                // if the value is the same, do nothing
                                if (v == userResourceLanguageCode) {
                                  return;
                                } else {
                                  // change the language: show loading indicator

                                  if (v != null) {
                                    // get the new collections available
                                    userResourceLanguageCode = v;
                                    // Save preferences
                                    widget.bibleReference.collectionID = v
                                        .toString();
                                    Provider.of<UserPrefs>(
                                      context,
                                      listen: false,
                                    ).saveScrollGroupState(
                                      widget.bibleReference,
                                    );

                                    setLanguage();
                                  }
                                }
                              },
                              selectedItemBuilder: (context) {
                                return languages.map((c) {
                                  return Align(
                                    alignment: c.scriptDirection == 'LTR'
                                        ? Alignment.centerLeft
                                        : Alignment.centerRight,
                                    child: Text(
                                      c.localizedDisplay,
                                      overflow: textOverflow,
                                      textDirection: c.scriptDirection == 'LTR'
                                          ? TextDirection.ltr
                                          : TextDirection.rtl,
                                    ),
                                  );
                                }).toList();
                              },
                              items: languages
                                  .map(
                                    (c) => ComboBoxItem<int>(
                                      value: c.id,
                                      child: Align(
                                        alignment: c.scriptDirection == 'LTR'
                                            ? Alignment.centerLeft
                                            : Alignment.centerRight,
                                        child: Text(
                                          c.localizedDisplay,
                                          overflow: textOverflow,
                                          textDirection:
                                              c.scriptDirection == 'LTR'
                                              ? TextDirection.ltr
                                              : TextDirection.rtl,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                    ),
                    // small gear icon setting for choosing resources for the selected lang
                    ResourceChooser(
                      resourceCodes: userResourceCodes,
                      langId: userResourceLanguageCode,
                      textDirection: textDirection,
                      onChanged: (code) {
                        if (userResourceCodes.contains(code)) {
                          userResourceCodes.remove(code);
                        } else {
                          userResourceCodes.add(code);
                        }
                      },
                      // update the content after user changes resources
                      onShouldUpdateContent: updateContent,
                    ),
                  ],
                  onFontIncrease: () {
                    if (baseFontSize < 50) {
                      setState(() {
                        baseFontSize = baseFontSize + 1;
                      });
                    }
                  },
                  onFontDecrease: () {
                    if (baseFontSize > 10) {
                      setState(() {
                        baseFontSize = baseFontSize - 1;
                      });
                    }
                  },
                  isLinked: isLinked,
                  onLinkChanged: (_) {
                    setState(() {
                      isLinked = !isLinked;
                    });
                  },
                  onDelete: () =>
                      widget.deleteColumn(widget.bibleReference.key),
                  canDelete: true,
                  trailingControls: [
                    if (!kIsWeb)
                      Tooltip(
                        message: _isOnline
                            ? 'Disconnect (Go Offline)'
                            : 'Connect (Check Internet)',
                        child: IconButton(
                          icon: Icon(
                            _isOnline
                                ? WindowsIcons.wifi
                                : WindowsIcons.wifi_error4,
                          ),
                          onPressed: () async {
                            setState(() {
                              _loadingLanguage = true;
                            });

                            // Toggle intended state
                            if (_isOnline) {
                              // user is online and choosing offline - set to offline
                              _shouldCheckConnectivity = false;
                              _isOnline = false;
                              //save for later
                              userPrefsBox.put('userConnectivityChoice', false);
                            } else {
                              _shouldCheckConnectivity = true;
                              userPrefsBox.put('userConnectivityChoice', true);
                              await _checkConnectivity();
                            }

                            await AquiferService().reInitializeResourceData(
                              _isOnline,
                            );
                            languages.clear();
                            languages = AquiferService().allLanguages.toList();

                            setState(() {
                              _loadingLanguage = false;
                            });

                            _fetchResources();
                          },
                        ),
                      ),

                    if (kDebugMode)
                      Tooltip(
                        message: 'Clear User Preferences',
                        child: IconButton(
                          icon: Icon(
                            FluentIcons.triangle_shape,
                            color: Colors.orange,
                          ),
                          onPressed: () {
                            userPrefsBox.clear();
                          },
                        ),
                      ),
                    // if (kDebugMode)
                    //   Tooltip(
                    //     message: 'Test getting list of resources',
                    //     child: IconButton(
                    //       icon: Icon(
                    //         FluentIcons.app_icon_default,
                    //         color: Colors.orange,
                    //       ),
                    //       onPressed: () {
                    //         AquiferService()
                    //             .streamResourcesForChapter(
                    //               connected: _isOnline,
                    //               langId: userResourceLanguageCode,
                    //               resourceCollectionCodes: [
                    //                 'TyndaleStudyNotes',
                    //               ],
                    //               book: 'GEN',
                    //               chapter: '1',
                    //             )
                    //             .listen((event) => print(event));
                    //       },
                    //     ),
                    //   ),
                  ],
                ),
                if (_isFetchingPrevious)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ProgressBar(),
                    ),
                  ),

                // main column
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    decoration: BoxDecoration(
                      // color: FluentTheme.of(context).cardColor,
                      border: Border(
                        right: BorderSide(
                          width: 1.0,
                          color: Color.fromARGB(85, 126, 126, 126),
                        ),
                      ),
                    ),
                    child: Center(
                      child: _loadingLanguage
                          ? _buildLoadingResources()
                          : _loadingResources
                          ? _buildLoadingResources()
                          : _resourceItems.isEmpty
                          ? const Icon(FluentIcons.library, size: 64)
                          : NotificationListener(
                              onNotification: (notification) {
                                if (notification is ScrollUpdateNotification) {
                                  final metrics = notification.metrics;
                                  if (metrics.pixels <=
                                          metrics.minScrollExtent &&
                                      notification.dragDetails != null) {
                                    // User is dragging at the top edge
                                    print(
                                      'Top edge drag (simulate overscroll)',
                                    );
                                    _fetchPreviousChapter();
                                  }
                                }
                                return false;
                              },
                              child: ScrollablePositionedList.builder(
                                physics: BouncingScrollPhysics(),
                                itemCount: _resourceItems.length,
                                itemBuilder: (context, index) {
                                  return ContentTile(
                                    item: _resourceItems[index],
                                    baseFontSize: baseFontSize,
                                  );
                                },
                                itemScrollController: itemScrollController,
                                itemPositionsListener: itemPositionsListener,
                              ),
                            ),
                      // : Column(
                      //     mainAxisAlignment: MainAxisAlignment.center,
                      //     children: [
                      //       Icon(
                      //         FluentIcons.error,
                      //         size: 32,
                      //         color: Colors.red,
                      //       ),
                      //       const SizedBox(height: 8),
                      //       const Text('Offline Mode'),
                      //       const SizedBox(height: 16),
                      //       Button(
                      //         onPressed: () {
                      //           setState(() {
                      //             _loadingLanguage = true;
                      //           });
                      //           _checkConnectivity();
                      //         },
                      //         child: const Text('Retry'),
                      //       ),
                      //     ],
                      //   ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
      },
    );
  }
}

IconData contentIcon(String code) {
  if (code.contains('Intro')) {
    return FluentIcons.book_answers;
  } else if (code.contains('Themes')) {
    return FluentIcons.favorite_star_fill;
  } else if (code.contains('Profiles')) {
    return FluentIcons.profile_search;
  } else if (code.contains('Notes')) {
    return FluentIcons.reading_mode_solid;
  } else if (code.contains('Image')) {
    return FluentIcons.picture_fill;
  } else {
    return FluentIcons.info;
  }
}
