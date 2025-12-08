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
  TextOverflow textOverflow = TextOverflow.ellipsis;
  Alignment alignment = Alignment.centerLeft;
  TextDirection textDirection = TextDirection.ltr;
  AquiferService aquiferService = AquiferService();
  bool _isOnline = false;
  List<ResourceItem> _resourceItems = [];
  final ItemScrollController itemScrollController = ItemScrollController();
  final ItemPositionsListener itemPositionsListener =
      ItemPositionsListener.create();
  double baseFontSize = 20;
  bool isLinked = true;
  bool _loadingLanguage = false;
  bool _loadingResources = false;
  int userResourceLanguageCode = 4;
  List<ResourceCollectionInfo> collections = [];
  List<ResourceCollectionInfo> selectedCollections = [];
  late Future initialization;
  List<String> userResourceCodes = [];
  late ResourceLanguage language;
  List<ResourceLanguage> languages = [];
  StreamSubscription<ResourceItem>? _resourceSubscription;

  List<ResourceItem> dummyResourceItems = List.generate(
    10,
    (index) => ResourceItem(
      id: index.toString(),
      resourceCollectionCode: 'TyndaleStudyNotes',
      localizedName: 'Dummy Resource Name',
      resourceType: ResourceType.studyNotes,
      content:
          'These verses introduce the Pentateuch (Genesis—Deuteronomy) and teach Israel that the world was created, ordered, and populated by the one true God and not by the gods of surrounding nations. God blessed three specific things: animal life (1:22-25), human life (1:27), and the Sabbath day (2:3). This trilogy of blessings highlights the Creator’s plan: Humankind was made in God’s image to enjoy sovereign dominion over the creatures of the earth and to participate in God’s Sabbath rest.',
      langID: 1,
      scriptDirection: 'LTR',
    ),
  );

  @override
  void dispose() {
    _resourceSubscription?.cancel();
    super.dispose();
  }

  Future<void> init() async {
    await _checkConnectivity();
    setLanguage();
  }

  @override
  void initState() {
    userResourceLanguageCode = widget.incomingUserResourceLanguageCode;
    languages = AquiferService().allLanguages;
    isLinked = widget.bibleReference.partOfScrollGroup;
    initialization = init();
    super.initState();
  }

  Future<void> _checkConnectivity() async {
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
          .where((c) => c.code.startsWith('Tyndale') || c.code == 'UbsImages')
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

  Future<void> _fetchResources() async {
    if (!_isOnline) return;

    await _resourceSubscription?.cancel();
    _resourceItems.clear();

    setState(() {
      _loadingResources = true;
    });

    try {
      _resourceSubscription = AquiferService()
          .streamResourcesForChapter(
            connected: _isOnline,
            langId: userResourceLanguageCode,
            resourceCollectionCodes: userResourceCodes,
            book: 'GEN',
            chapter: '1',
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
            onDone: () {
              if (mounted) {
                setState(() {
                  _loadingResources = false;
                });
              }
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
    userPrefsBox.put(
      'resource_prefs_$userResourceLanguageCode',
      userResourceCodes,
    );

    _fetchResources(); // Fetch resources when content is updated
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: initialization,
      builder: (context, asyncSnapshot) {
        if (asyncSnapshot.connectionState != ConnectionState.done) {
          return Center(child: ProgressBar());
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
                    _loadingLanguage
                        ? IconButton(
                            icon: Icon(FluentIcons.plug_connected),
                            onPressed: null,
                          )
                        : _isOnline
                        ? SizedBox.shrink()
                        : Tooltip(
                            message: 'Check if internet is available',
                            child: IconButton(
                              icon: Icon(FluentIcons.plug_disconnected),
                              onPressed: () async {
                                setState(() {
                                  _loadingLanguage = true;
                                });

                                await _checkConnectivity();

                                await AquiferService().reInitializeResourceData(
                                  _isOnline,
                                );
                                languages = AquiferService().allLanguages;

                                setState(() {
                                  _loadingLanguage = false;
                                });
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
                    if (kDebugMode)
                      Tooltip(
                        message: 'Test getting list of resources',
                        child: IconButton(
                          icon: Icon(
                            FluentIcons.app_icon_default,
                            color: Colors.orange,
                          ),
                          onPressed: () {
                            AquiferService()
                                .streamResourcesForChapter(
                                  connected: _isOnline,
                                  langId: userResourceLanguageCode,
                                  resourceCollectionCodes: [
                                    'TyndaleStudyNotes',
                                  ],
                                  book: 'GEN',
                                  chapter: '1',
                                )
                                .listen((event) => print(event));
                          },
                        ),
                      ),
                  ],
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
                          ? const ProgressRing()
                          : _loadingResources
                          ? Skeletonizer(
                              enabled: true,
                              child: ScrollablePositionedList.builder(
                                itemCount: dummyResourceItems.length,
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Column(
                                      crossAxisAlignment: .start,
                                      children: [
                                        Text(
                                          dummyResourceItems[index]
                                              .localizedName,
                                          style: TextStyle(
                                            fontSize: baseFontSize + 2,
                                          ),
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
                            )
                          : _resourceItems.isEmpty
                          ? const Text('No resources found for this chapter.')
                          : ScrollablePositionedList.builder(
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
