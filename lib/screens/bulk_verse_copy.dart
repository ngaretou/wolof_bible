import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';

import '/main.dart';
import '../logic/bible_abbreviations.dart';
import '../logic/bulk_verse_copy_logic.dart';
import '../logic/search_service.dart';
import '../logic/data_initializer.dart';
import '../logic/touch_media.dart';

class BulkVerseCopy extends StatefulWidget {
  const BulkVerseCopy({super.key});

  @override
  State<BulkVerseCopy> createState() => _BulkVerseCopyState();
}

class _BulkVerseCopyState extends State<BulkVerseCopy> {
  TextEditingController verseRangeTextController = TextEditingController();
  bool showCopyHelper =
      false; // this is whether or not the color overlay with icon is shown
  Widget hoveringIcon =
      SizedBox(width: 20); // initially copy but after copy is a check mark

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

  Widget copyHelperIcon({required IconData icon}) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onPrimaryContainer,
        shape: BoxShape.circle, // makes it a perfect circle
      ),
      child: Center(
          child: Icon(
        icon,
        color: Theme.of(context).colorScheme.primaryContainer,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    int minLines = (userPrefsBox.get('instructions') == null)
        ? 18
        : (userPrefsBox.get('instructions') ? 16 : 23);

    final copyIcon = copyHelperIcon(icon: Icons.copy);
    final successIcon = copyHelperIcon(icon: Icons.check);

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
        hoveringIcon = copyIcon;
        if (isTouch) {
          showCopyHelper = true;
        }
      });

      // give user feedback on ones that didn't work
      if (results.errors.isNotEmpty) {
        showDialog(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: Text('Could not parse:'),
                content: SingleChildScrollView(
                    child: Text(results.errors.join('\n'))),
                actions: [
                  TextButton(
                      onPressed: Navigator.of(context).pop, child: Text('OK')),
                  TextButton(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(
                            text: results.errors.join('\n'),
                          ),
                        );
                        Navigator.of(context).pop();
                      },
                      child: Text('Copy'))
                ],
              );
            });
      }
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.close),
            onPressed: Navigator.of(context).pop,
          ),
          SizedBox(width: 20)
        ],
        title: Text('Bulk Verse Copy'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExpansionTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                collapsedShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                initiallyExpanded: userPrefsBox.get('instructions') ?? true,
                onExpansionChanged: (value) {
                  userPrefsBox.put('instructions', value);
                  setState(() {});
                },
                collapsedBackgroundColor:
                    Theme.of(context).colorScheme.surfaceContainer,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                title: Text('Instructions'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Row(
                      children: [
                        Expanded(child: Text(instructions)),
                        SizedBox(width: 20),
                        ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).push(MaterialPageRoute<
                                      void>(
                                  builder: (BuildContext licenseContext) =>
                                      Theme(
                                          //Here after Flutter 3 the theming wouldn't work right -
                                          //wrap the License Page in its own Material theme,
                                          //getting the imporant components from the saved theme
                                          data: ThemeData(
                                              useMaterial3: true, //important!
                                              colorSchemeSeed: Theme.of(context)
                                                  .primaryColor,
                                              brightness:
                                                  Theme.brightnessOf(context) ==
                                                          Brightness.dark
                                                      ? Brightness.dark
                                                      : Brightness.light),
                                          child: AbbreviationView())));
                            },
                            child: Text('See all abbreviations'))
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 20,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(width: 20),
                  Flexible(child: Text('Choose collection:')),
                  SizedBox(width: 20),
                  Expanded(
                    child: DropdownButton(
                      isExpanded: true,
                      items: collections
                          .map((e) => DropdownMenuItem(
                                value: e.id,
                                child: Text(
                                  e.name,
                                ),
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
                  SizedBox(width: 60),
                  Flexible(child: Text('Include verse numbers?')),
                  SizedBox(width: 20),
                  Switch(
                      value: includeVerseNumbers,
                      onChanged: (val) {
                        setState(() {
                          includeVerseNumbers = val;
                        });
                      })
                ],
              ),
              SizedBox(height: 20),

              Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: verseRangeTextController,

                        minLines: minLines,
                        maxLines: minLines,
                        textCapitalization: TextCapitalization.none,
                        autocorrect: false,
                        decoration:
                            InputDecoration(filled: true, hintText: sampleText),

                        // The validator receives the text that the user has entered.
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter some text';
                          } else {
                            return null;
                          }
                        },
                      ),
                    ),
                    SizedBox(width: 20),
                    IconButton.filledTonal(
                        icon: Icon(Icons.start), onPressed: processUserInput),
                    SizedBox(width: 20),
                    if (verses != null)
                      Expanded(
                        child: FutureBuilder(
                            future: verses,
                            builder: (ctx, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                    child: CircularProgressIndicator());
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
                                        hoveringIcon = successIcon;
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
                                        Positioned.fill(
                                          child: Opacity(
                                              opacity: showCopyHelper ? .2 : 0,
                                              child: Container(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer,
                                              )),
                                        ),
                                        if (showCopyHelper)
                                          Positioned.fill(
                                              child:
                                                  Center(child: hoveringIcon)),
                                        TextFormField(
                                          enabled: false,
                                          // readOnly: true,
                                          minLines: minLines,
                                          maxLines: minLines,
                                          textCapitalization:
                                              TextCapitalization.none,
                                          autocorrect: false,
                                          initialValue: buffer.toString(),
                                          decoration: const InputDecoration(
                                            filled: true,
                                          ),
                                        ),
                                      ]),
                                    ),
                                  );
                                } else {
                                  return Center(
                                      child: Icon(Icons
                                          .sentiment_dissatisfied_outlined));
                                }
                              }
                            }),
                      ),
                    if (verses == null)
                      Expanded(
                        child: TextFormField(
                          enabled: false,
                          // readOnly: true,
                          minLines: minLines,
                          maxLines: minLines,
                          textCapitalization: TextCapitalization.none,
                          autocorrect: false,
                          // initialValue: '...',
                          decoration: const InputDecoration(
                            filled: true,
                          ),
                        ),
                      ),
                    // Expanded(
                    //     child: SizedBox(
                    //   width: 40,
                    //   height: 40,
                    // ))
                  ]),
              // SizedBox(
              //   height: 20,
              // ),
              // Row(
              //   children: [
              //     Expanded(child: Placeholder()),
              //     Expanded(
              //       child: SizedBox(
              //         width: 165,
              //         height: 10,
              //       ),
              //     )
              //   ],
              // )
            ],
          ),
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

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.close),
            onPressed: Navigator.of(context).pop,
          ),
          SizedBox(width: 20)
        ],
        title: Text('Abbreviations'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: GridView.builder(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320, childAspectRatio: 3 / 2),
            itemCount: abb.length,
            itemBuilder: (context, i) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bookKeys[i],
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      SizedBox(width: 20),
                      Expanded(child: Text(abb[bookKeys[i]]!.join(', '))),
                    ],
                  ),
                ),
              );
            }),
      ),
    );
  }
}
