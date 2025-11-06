import 'dart:convert';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';

import '../logic/bible_abbreviations.dart';
import '../logic/bulk_verse_copy_logic.dart';
import '../logic/search_service.dart';
import '../logic/data_initializer.dart';
import '../logic/touch_media.dart';
import '../main.dart'; // for userPrefsBox

class BulkVerseCopy extends StatefulWidget {
  const BulkVerseCopy({super.key});

  @override
  State<BulkVerseCopy> createState() => _BulkVerseCopyState();
}

class _BulkVerseCopyState extends State<BulkVerseCopy> {
  TextEditingController verseRangeTextController = TextEditingController();
  bool showCopyHelper =
      false; // this is whether or not the color overlay with icon is shown
  Widget hoveringIcon = const SizedBox(
      width: 20); // initially copy but after copy is a check mark

  Future<List<HydratedVerseResult>>? verses;

  String collectionId = collections.first.id;
  bool includeVerseNumbers = false;
  bool isTouch = true;

  final sampleText = '''Actes 22.3
Colossiens 1:26
2 Timothée 3.6-8
2PE 1.21-23
1 Peter 4. 14
1 Pierre 4.19-23''';

  final instructions =
      '''Paste your references in the box below. Press the button, then if there are errors they will be reported, and you can preview and grab your results from the box on the right - click on the box and they're copied.

You can use English, French or Paratext book names (GEN EXO etc) as well as common abbreviations - check the button to the right to see all working names and abbreviations. You can include accents or not on your names and abbreviations, they get removed during the search process.

You can have : or . separators, you can do ranges (MAT 8.9-14) or whole chapters (MAT 8), but not skipped verses (MAT 8.5, 6, 14) or ranges across chapters (Matt 8-9).''';

  @override
  void initState() {
    if (kIsWeb) {
      isTouch = isTouchWebDevice();
    } else if (Platform.isAndroid || Platform.isIOS) {
      isTouch = true;
    } else {
      isTouch = false;
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    int minLines = (userPrefsBox.get('instructions') == null)
        ? 18
        : (userPrefsBox.get('instructions') ? 16 : 23);

    void processUserInput() {
      // parse the contents the user has given us

      String parseMe = verseRangeTextController.text.isEmpty
          ? sampleText
          : verseRangeTextController.text;

      List<String> refs = const LineSplitter().convert(parseMe);

      // trim all entries

      for (var i = 0; i < refs.length; i++) {
        refs[i] = refs[i].trim();
      }

      // Then remove empties
      refs.removeWhere((s) => s.isEmpty);

      final results = parseReferences(refs);

      // if (isTouchWebDevice())
      // get the search service getting the actual verses for the ones we could parse
      setState(() {
        verses = SearchService().getVerseRanges(
            collectionId: collectionId,
            verseRanges: results.ranges,
            collections: collections,
            includeVerseNumbers: includeVerseNumbers);

        FocusManager.instance.primaryFocus?.unfocus();
        hoveringIcon = copyIcon(context);
        if (isTouch) {
          showCopyHelper = true;
        }
      });

      // give user feedback on ones that didn't work
      if (results.errors.isNotEmpty) {
        showDialog(
            context: context,
            builder: (context) {
              return ContentDialog(
                title: const Text('Could not parse:'),
                content: SingleChildScrollView(
                    child: Text(results.errors.join('\n'))),
                actions: [
                  Button(
                      onPressed: Navigator.of(context).pop,
                      child: const Text('OK')),
                  Button(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(
                            text: results.errors.join('\n'),
                          ),
                        );
                        Navigator.of(context).pop();
                      },
                      child: const Text('Copy'))
                ],
              );
            });
      }
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expander(
              initiallyExpanded: userPrefsBox.get('instructions') ?? true,
              onStateChanged: (value) {
                userPrefsBox.put('instructions', value);
                setState(() {});
              },
              header: const Text('Instructions'),
              content: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Row(
                  children: [
                    Expanded(child: Text(instructions)),
                    const SizedBox(width: 20),
                    Button(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => ContentDialog(
                              constraints: BoxConstraints(
                                  maxWidth: double.infinity,
                                  maxHeight: double.infinity),
                              title: const Text('Abbreviations'),
                              content: const AbbreviationView(),
                              actions: [
                                Button(
                                  child: const Text('Close'),
                                  onPressed: () => Navigator.pop(context),
                                )
                              ],
                            ),
                          );
                        },
                        child: const Text('See all abbreviations'))
                  ],
                ),
              ),
            ),
            const SizedBox(
              height: 20,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(width: 20),
                const Flexible(child: Text('Choose collection:')),
                const SizedBox(width: 20),
                Expanded(
                  child: ComboBox<String>(
                    isExpanded: true,
                    items: collections
                        .map((e) => ComboBoxItem(
                              value: e.id,
                              child: Text(e.name),
                            ))
                        .toList(),
                    value: collectionId == ''
                        ? collections.first.id
                        : collectionId,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          collectionId = value;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 60),
                const Text('Include verse numbers?'),
                const SizedBox(width: 20),
                ToggleSwitch(
                    checked: includeVerseNumbers,
                    onChanged: (val) {
                      setState(() {
                        includeVerseNumbers = val;
                      });
                    })
              ],
            ),
            const SizedBox(height: 20),
            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextBox(
                      controller: verseRangeTextController,
                      minLines: minLines,
                      maxLines: minLines,
                      placeholder: sampleText,
                    ),
                  ),
                  const SizedBox(width: 20),
                  SizedBox.square(
                    dimension: 40,
                    child: FilledButton(
                      onPressed: processUserInput,
                      child: Icon(FluentIcons.chevron_right),
                    ),
                  ),
                  const SizedBox(width: 20),
                  if (verses != null)
                    Expanded(
                      child: FutureBuilder(
                          future: verses,
                          builder: (ctx, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(child: ProgressRing());
                            } else {
                              final buffer = StringBuffer();

                              if (snapshot.data != null &&
                                  snapshot.data!.isNotEmpty) {
                                for (var entry in snapshot.data!) {
                                  buffer.writeln(
                                      '${entry.reference} : ${entry.composedText}');
                                }

                                return GestureDetector(
                                  onTap: () {
                                    //copy to clipboard
                                    Clipboard.setData(
                                      ClipboardData(
                                        text: buffer.toString(),
                                      ),
                                    );
                                    setState(() {
                                      hoveringIcon = successIcon(context);
                                    });
                                  },
                                  child: MouseRegion(
                                    onEnter: (_) {
                                      setState(() {
                                        showCopyHelper = true;
                                      });
                                    },
                                    onExit: (_) {
                                      setState(() {
                                        showCopyHelper = false;
                                      });
                                    },
                                    child: Stack(children: [
                                      TextBox(
                                        enabled: false,
                                        readOnly: true,
                                        minLines: minLines,
                                        maxLines: minLines,
                                        controller: TextEditingController(
                                            text: buffer.toString()),
                                      ),
                                      if (showCopyHelper)
                                        Positioned.fill(
                                          child: Opacity(
                                              opacity: .2,
                                              child: Container(
                                                color: FluentTheme.of(context)
                                                    .accentColor,
                                              )),
                                        ),
                                      if (showCopyHelper)
                                        Positioned.fill(
                                            child: Center(child: hoveringIcon)),
                                    ]),
                                  ),
                                );
                              } else {
                                return const Center(
                                    child: Icon(FluentIcons.sad));
                              }
                            }
                          }),
                    ),
                  if (verses == null)
                    Expanded(
                      child: TextBox(
                        readOnly: true,
                        minLines: minLines,
                        maxLines: minLines,
                      ),
                    )
                ])
          ],
        ),
      ),
    );
  }
}

class AbbreviationView extends StatelessWidget {
  const AbbreviationView({super.key});

  @override
  Widget build(BuildContext context) {
    final abb = BibleAbbreviations.abbreviations;
    final List<String> bookKeys =
        BibleAbbreviations.abbreviations.keys.toList();

    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320, childAspectRatio: 3 / 2),
            itemCount: abb.length,
            itemBuilder: (context, i) {
              return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: HoverCard(
                    book: bookKeys[i],
                    abbs: abb[bookKeys[i]]!,
                  ));
            }));
  }
}

class HoverCard extends StatefulWidget {
  final String book;
  final List<String> abbs;
  const HoverCard({required this.book, required this.abbs, super.key});

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hovering = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final cardInfo = '${widget.book}: ${widget.abbs.join(', ')}';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) {
        setState(() {
          _hovering = false;
          _copied = false;
        });
      },
      child: GestureDetector(
        onTap: () {
          Clipboard.setData(
            ClipboardData(
              text: cardInfo,
            ),
          );
          setState(() {
            _copied = true;
          });
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: Card(
                backgroundColor: _hovering
                    ? FluentTheme.of(context).accentColor.lightest
                    : FluentTheme.of(context).cardColor,
                child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.book,
                            style: FluentTheme.of(context).typography.bodyLarge,
                          ),
                          const SizedBox(width: 20),
                          Expanded(child: Text(widget.abbs.join(', ')))
                        ])),
              ),
            ),
            if (_hovering)
              Center(child: _copied ? successIcon(context) : copyIcon(context))
          ],
        ),
      ),
    );
  }
}

Widget copyIcon(BuildContext context) {
  return copyHelperIcon(context, icon: FluentIcons.copy);
}

Widget successIcon(BuildContext context) {
  return copyHelperIcon(context, icon: FluentIcons.check_mark);
}

Widget copyHelperIcon(BuildContext context, {required IconData icon}) {
  return Container(
    width: 50,
    height: 50,
    decoration: BoxDecoration(
      color: FluentTheme.of(context).accentColor.darker.withAlpha(255),
      // color: Colors.red,
      shape: BoxShape.circle, // makes it a perfect circle
    ),
    child: Center(
        child: Icon(
      icon,
      color: FluentTheme.of(context).shadowColor,
    )),
  );
}
