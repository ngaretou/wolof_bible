import 'package:flutter/material.dart';
import 'dart:core';
import 'package:flutter/services.dart';

import '../logic/search_service.dart';

class BulkVerseCopy extends StatefulWidget {
  const BulkVerseCopy({super.key});

  @override
  State<BulkVerseCopy> createState() => _BulkVerseCopyState();
}

class _BulkVerseCopyState extends State<BulkVerseCopy> {
  TextEditingController transliterationsController = TextEditingController();
  bool showCopyHelper =
      false; // this is whether or not the color overlay with icon is shown
  Icon hoveringIcon =
      const Icon(Icons.copy); // initially copy but after copy is a check mark
  late Future init;
  int minLines = 50;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios),
          onPressed: Navigator.of(context).pop,
        ),
        title: Text('Bulk Verse Copy'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Expanded(
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      //copy to clipboard
                      Clipboard.setData(
                        ClipboardData(
                          text: '',
                        ),
                      );
                      setState(() {
                        hoveringIcon = const Icon(Icons.check);
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
                          hoveringIcon = const Icon(Icons.copy);
                        });
                      },
                      child: Stack(children: [
                        Opacity(
                            opacity: showCopyHelper ? .5 : 0,
                            child: Container(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                child: Center(child: hoveringIcon))),
                        FutureBuilder(
                          future: init,
                          builder: (ctx, snapshot) => snapshot
                                      .connectionState ==
                                  ConnectionState.waiting
                              ? const Center(child: CircularProgressIndicator())
                              : TextFormField(
                                  enabled: false,
                                  // readOnly: true,
                                  minLines: minLines,
                                  maxLines: minLines,
                                  textCapitalization: TextCapitalization.none,
                                  autocorrect: false,
                                  // initialValue: ,
                                  decoration: const InputDecoration(
                                    filled: true,
                                  ),
                                ),
                        ),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(
                  width: 20,
                ),
                Expanded(
                  child: TextFormField(
                    controller: transliterationsController,
                    onChanged: (value) {
                      print('have change in value');
                    },

                    minLines: minLines,
                    maxLines: minLines,
                    textCapitalization: TextCapitalization.none,
                    autocorrect: false,
                    decoration: const InputDecoration(
                        filled: true,
                        hintText:
                            'Copy the menu translations at left and paste the transliterated menus here'),

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
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
