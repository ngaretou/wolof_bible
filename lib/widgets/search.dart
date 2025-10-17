import 'dart:async';
import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';

import '../logic/data_initializer.dart';
import '../logic/search_service.dart';
import '../logic/verse_composer.dart';
import '../providers/column_manager.dart';
import '../providers/user_prefs.dart';

class SearchWidget extends StatefulWidget {
  final Function closeSearch;
  final String? comboBoxFont;

  const SearchWidget(
      {super.key, required this.closeSearch, required this.comboBoxFont});

  @override
  State<SearchWidget> createState() => _SearchWidgetState();
}

class _SearchWidgetState extends State<SearchWidget> {
  final _searchController = TextEditingController();
  final _expanderKey = GlobalKey<ExpanderState>();
  final _searchService = SearchService();

  List<String> _collectionsToSearch = [];
  Stream<List<SearchResult>>? _resultsStream;
  Key _streamBuilderKey = UniqueKey();

  @override
  void initState() {
    _collectionsToSearch = [collections.first.id]; // just collection 1
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void searchFunction(String searchRequest) {
    if (searchRequest.trim().isEmpty) {
      setState(() {
        _resultsStream = null;
      });
      return;
    }

    // Create the map of collection IDs to language codes
    final collectionLanguages = {
      for (var id in _collectionsToSearch)
        id: collections.firstWhere((c) => c.id == id).language,
    };

    setState(() {
      _streamBuilderKey = UniqueKey();
      _resultsStream = _searchService
          .search(
        collectionIds: _collectionsToSearch,
        query: searchRequest,
        collectionLanguages: collectionLanguages,
      )
          .scan<List<SearchResult>>((acc, value, _) => acc..add(value), []);
    });
  }

  @override
  Widget build(BuildContext context) {
    TextStyle searchControlsStyle = DefaultTextStyle.of(context).style.copyWith(
          fontFamily: widget.comboBoxFont,
          fontSize: 16,
        );

    final checkBoxes = List.generate(collections.length, (i) {
      return Checkbox(
        checked: _collectionsToSearch.contains(collections[i].id),
        onChanged: (bool? value) {
          setState(() {
            if (_collectionsToSearch.contains(collections[i].id)) {
              _collectionsToSearch
                  .removeWhere((element) => element == collections[i].id);
            } else {
              _collectionsToSearch.add(collections[i].id);
            }
          });
        },
        content: Text(collections[i].name, style: searchControlsStyle),
      );
    });

    return SizedBox(
        width: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            //Search tool card
            Padding(
              padding:
                  const EdgeInsets.only(top: 5.0, right: 5, left: 5, bottom: 5),
              child: Card(
                backgroundColor:
                    FluentTheme.of(context).brightness == Brightness.dark
                        ? null
                        : FluentTheme.of(context)
                            .cardColor
                            .lerpWith(Colors.grey, .1),
                padding: const EdgeInsets.only(
                    top: 12, bottom: 12, left: 12, right: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormBox(
                                  style: searchControlsStyle,
                                  onEditingComplete: () =>
                                      searchFunction(_searchController.value.text),
                                  maxLines: 1,
                                  controller: _searchController,
                                  suffixMode: OverlayVisibilityMode.always,
                                  expands: false,
                                  suffix: _searchController.text.isEmpty
                                      ? null
                                      : IconButton(
                                          icon: const Icon(
                                              material.Icons.backspace),
                                          onPressed: () {
                                            _searchController.clear();
                                          },
                                        ),
                                  placeholder: Provider.of<UserPrefs>(context,
                                          listen: false)
                                      .currentTranslation
                                      .search,
                                  placeholderStyle:
                                      searchControlsStyle.copyWith(
                                          color: DefaultTextStyle.of(context)
                                              .style
                                              .color!
                                              .withAlpha(100)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Expander(
                            key: _expanderKey,
                            leading: Button(
                              child: Text(
                                  Provider.of<UserPrefs>(context, listen: false)
                                      .currentTranslation
                                      .search,
                                  style: searchControlsStyle),
                              onPressed: () =>
                                  searchFunction(_searchController.value.text),
                            ),
                            header: const Text(''),
                            content: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: checkBoxes,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        widget.closeSearch();
                      },
                      icon: const Icon(FluentIcons.calculator_multiply),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: () {
                if (_resultsStream == null) {
                  return const Center(
                      child: Icon(FluentIcons.search, size: 40));
                }

                return StreamBuilder<List<SearchResult>>(
                  key: _streamBuilderKey,
                  stream: _resultsStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                          child: Text('Error: ${snapshot.error}'));
                    }

                    switch (snapshot.connectionState) {
                      case ConnectionState.none:
                      case ConnectionState.waiting:
                        return const Center(child: ProgressRing());
                      case ConnectionState.active:
                      case ConnectionState.done:
                        final results = snapshot.data ?? [];
                        if (results.isEmpty) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(FluentIcons.sad, size: 40),
                                SizedBox(height: 10),
                                Text('No results found.'),
                              ],
                            ),
                          );
                        }
                        return ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (ctx, i) => SearchResultTile(
                            result: results[i],
                          ),
                        );
                    }
                  },
                );
              }(),
            ),
          ],
        ));
  }
}

class SearchResultTile extends StatefulWidget {
  final SearchResult result;

  const SearchResultTile({super.key, required this.result});

  @override
  State<SearchResultTile> createState() => _SearchResultTileState();
}

class _SearchResultTileState extends State<SearchResultTile> {
  Color? cardColor;

  @override
  Widget build(BuildContext context) {
    final Collection thisCollection =
        collections.firstWhere((c) => c.id == widget.result.collection);
    final Book thisBook =
        thisCollection.books.firstWhere((b) => b.id == widget.result.book);

    final String resultsFont = thisCollection.fonts.first.fontFamily;
    final ui.TextDirection textDirection = thisCollection.textDirection == 'LTR'
        ? ui.TextDirection.ltr
        : ui.TextDirection.rtl;
    final TextAlign textAlign =
        thisCollection.textDirection == 'LTR' ? TextAlign.left : TextAlign.right;

    final TextStyle textStyle = TextStyle(
      fontFamily: resultsFont,
      fontSize: 20,
      color: DefaultTextStyle.of(context).style.color,
    );
    final TextStyle refStyle = DefaultTextStyle.of(context)
        .style
        .copyWith(fontFamily: resultsFont, fontStyle: FontStyle.italic);

    final String chVsSeparator =
        textDirection == ui.TextDirection.rtl ? '\u{200F}.' : '.';

    // Create a dummy ParsedLine to use the existing verseComposer
    final dummyLine = ParsedLine(
      collectionid: widget.result.collection,
      book: widget.result.book,
      chapter: widget.result.chapter,
      verse: widget.result.verse,
      verseText: widget.result.text,
      verseFragment: '',
      audioMarker: '',
      verseStyle: 'v',
    );

    final composedVerse = verseComposer(
      line: dummyLine,
      includeFootnotes: false,
      context: context,
    );

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: MouseRegion(
        onEnter: (event) {
          setState(() {
            cardColor = FluentTheme.of(context)
                .cardColor
                .lerpWith(FluentTheme.of(context).accentColor, .3);
          });
        },
        onExit: (event) {
          setState(() {
            cardColor = null;
          });
        },
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            BibleReference ref = BibleReference(
                key: UniqueKey(),
                partOfScrollGroup: true,
                collectionID: widget.result.collection,
                bookID: widget.result.book,
                chapter: widget.result.chapter,
                verse: widget.result.verse,
                columnIndex:
                    1); //This is dummy data as we dont care about the columnIndex here, just the ref

            Provider.of<ScrollGroup>(context, listen: false).setScrollGroupRef =
                ref;
          },
          child: Card(
            backgroundColor: cardColor,
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: textAlign == TextAlign.left
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                Text(
                  composedVerse.versesAsString, // Use the cleaned text
                  style: textStyle,
                  textAlign: textAlign,
                ),
                const SizedBox(height: 10),
                const Divider(),
                Wrap(
                    alignment: WrapAlignment.end,
                    textDirection: textDirection,
                    children: [
                      Text(
                        '${thisBook.name} ${widget.result.chapter}$chVsSeparator${widget.result.verse}  |  ',
                        style: refStyle,
                        textDirection: textDirection,
                        textAlign: textAlign,
                      ),
                      Text(
                        thisCollection.name,
                        style: refStyle,
                        textDirection: textDirection,
                        textAlign: textAlign,
                      ),
                    ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
