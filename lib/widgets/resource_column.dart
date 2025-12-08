import 'dart:ui' as ui;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
// import 'package:skeletonizer/skeletonizer.dart';
import 'package:wolof_bible/main.dart';
import 'package:wolof_bible/widgets/resource_chooser.dart';
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
  double baseFontSize = 20;
  bool isLinked = true;
  bool _isOnline = false;
  bool _isLoading = true;
  int userResourceLanguageCode = 4;
  List<ResourceCollectionInfo> collections = [];
  List<ResourceCollectionInfo> selectedCollections = [];
  late Future connectivityCheck;
  List<String> userResourceCodes = [];
  late ResourceLanguage language;
  List<ResourceLanguage> languages = [];

  @override
  void initState() {
    userResourceLanguageCode = widget.incomingUserResourceLanguageCode;
    languages = AquiferService().allLanguages;
    isLinked = widget.bibleReference.partOfScrollGroup;
    connectivityCheck = _checkConnectivity();
    setLanguage();
    super.initState();
  }

  Future<void> _checkConnectivity() async {
    final isOnline = await AquiferService().checkConnectivity();
    if (mounted) {
      setState(() {
        _isOnline = isOnline;
        _isLoading = false;
      });
    }
  }

  void setLanguage() {
    collections = AquiferService().getResourcesForLanguage(
      userResourceLanguageCode,
    );
    userResourceCodes.clear();
    userResourceCodes = collections
        .where((c) => c.code.startsWith('Tyndale') || c.code == 'UbsImages')
        .map((c) => c.code)
        .toList();
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
    updateContent();
  }

  void updateContent() {
    print('updateContent');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          ColumnHeader(
            leadingControls: [
              SizedBox(
                width: 160,
                height: 34,
                child: _isLoading
                    ? Center(child: ProgressBar())
                    : ComboBox<int>(
                        isExpanded: true,
                        value: userResourceLanguageCode,
                        onChanged: (v) async {
                          if (v == userResourceLanguageCode) {
                            return;
                          }
                          setState(() {
                            _isLoading = true;
                          });
                          if (v != null) {
                            userResourceLanguageCode = v;
                            collections.clear();
                            collections = AquiferService()
                                .getResourcesForLanguage(
                                  userResourceLanguageCode,
                                );
                            setLanguage();
                          }
                          setState(() {
                            _isLoading = false;
                          });
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
                                    textDirection: c.scriptDirection == 'LTR'
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
            onDelete: () => widget.deleteColumn(widget.bibleReference.key),
            canDelete: true,
            trailingControls: [
              _isLoading
                  ? IconButton(
                      icon: Icon(FluentIcons.plug_connected),
                      onPressed: null,
                    )
                  : IconButton(
                      icon: _isOnline
                          ? Icon(FluentIcons.plug_connected)
                          : Icon(FluentIcons.plug_disconnected),
                      onPressed: () async {
                        setState(() {
                          _isLoading = true;
                        });
                        final currentStatus = _isOnline;
                        await _checkConnectivity();
                        // if (currentStatus != _isOnline) {
                        await AquiferService().reInitializeResourceData(
                          _isOnline,
                        );
                        languages = AquiferService().allLanguages;
                        // }
                        setState(() {
                          _isLoading = false;
                        });
                      },
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
            ],
          ),

          // Content Placeholder
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
                child: _isLoading
                    ? const ProgressRing()
                    : _isOnline
                    ? Text(
                        'Resource Column Placeholder\nFont Size: $baseFontSize\nLinked: $isLinked',
                        textAlign: TextAlign.center,
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(FluentIcons.error, size: 32, color: Colors.red),
                          const SizedBox(height: 8),
                          const Text('Offline Mode'),
                          const SizedBox(height: 16),
                          Button(
                            onPressed: () {
                              setState(() {
                                _isLoading = true;
                              });
                              _checkConnectivity();
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
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
