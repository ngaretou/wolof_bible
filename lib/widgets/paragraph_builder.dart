import 'package:fluent_ui/fluent_ui.dart';
import 'dart:ui' as ui;
import 'dart:core';
import '../logic/data_initializer.dart';
import '../logic/verse_composer.dart';

// Data class to hold the calculated layout information for a verse.
class VerseOffset {
  final String book;
  final String chapter;
  final String verse;
  final Offset offset; // Offset within the ParagraphBuilder widget.

  VerseOffset({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.offset,
  });
}

class ParagraphBuilder extends StatefulWidget {
  final List<ParsedLine> paragraph;
  final bool addDivider;
  final String fontName;
  final ui.TextDirection textDirection;
  final double fontSize;
  final List<ParsedLine> rangeOfVersesToCopy;
  final Function addVerseToCopyRange;
  final Function(List<VerseOffset>)? onLayoutCalculated;

  const ParagraphBuilder(
      {super.key,
      required this.paragraph,
      required this.addDivider,
      required this.fontName,
      required this.textDirection,
      required this.fontSize,
      required this.rangeOfVersesToCopy,
      required this.addVerseToCopyRange,
      this.onLayoutCalculated});

  @override
  State<ParagraphBuilder> createState() => _ParagraphBuilderState();
}

class _ParagraphBuilderState extends State<ParagraphBuilder> {
  TextSpan? _cachedTextSpanWithWidgets;
  TextSpan? _cachedTextSpanForLayout;
  Map<int, ParsedLine> _characterIndexToVerseMap = {};
  bool isIntro = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // This is the correct lifecycle method to access inherited widgets like Theme.

    isIntro =
        widget.paragraph.isNotEmpty && widget.paragraph.first.chapter == '0';

    _prepareSpans();
  }

  @override
  void didUpdateWidget(ParagraphBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-prepare spans if the paragraph data or styling props change.
    if (widget.paragraph != oldWidget.paragraph ||
        widget.fontSize != oldWidget.fontSize ||
        widget.rangeOfVersesToCopy != oldWidget.rangeOfVersesToCopy) {
      _prepareSpans();
    }
  }

  void _prepareSpans() {
    bool ltrText = widget.textDirection == ui.TextDirection.ltr;
    Color accentTextColor = FluentTheme.of(context).accentColor;
    double fontSize = ltrText ? widget.fontSize : widget.fontSize + 7;

    TextStyle mainTextStyle = TextStyle(
      fontFamily: widget.fontName,
      fontSize: fontSize,
      color: DefaultTextStyle.of(context).style.color,
    );
    TextStyle underlineStyle =
        mainTextStyle.copyWith(decoration: TextDecoration.underline);
    TextStyle italicStyle = mainTextStyle.copyWith(fontStyle: FontStyle.italic);

    TextStyle introStyle = mainTextStyle.copyWith(
        fontStyle: FontStyle.italic,
        color: FluentTheme.of(context).accentColor);

    List<InlineSpan> styledParagraphFragments = [];
    StringBuffer plainTextBuffer = StringBuffer();
    Map<int, ParsedLine> characterIndexToVerseMap = {};

    TextSpan verseNumberRTL(String verseNumber) {
      final text = ' $verseNumber ';
      plainTextBuffer.write(text);
      return TextSpan(
        text: text,
        style: mainTextStyle.copyWith(
          textBaseline: TextBaseline.ideographic,
          fontSize: fontSize / 2,
          color: accentTextColor,
          decoration: TextDecoration.none,
        ),
      );
    }

    TextSpan verseNumberLTR(String verseNumber) {
      final text = ' $verseNumber ';
      plainTextBuffer.write(text);
      return TextSpan(
          text: text,
          style: TextStyle(
            fontFeatures: const [ui.FontFeature.superscripts()],
            // fontFamily: widget.fontName, // the incoming font doesn't support superscript it seems
            fontSize: fontSize,
            color: accentTextColor,
          )

          // style: mainTextStyle.copyWith(
          //   fontFeatures: const [ui.FontFeature.superscripts()],
          //   fontSize: fontSize / 2,
          //   color: accentTextColor,
          // ),
          );
    }

    List<InlineSpan> processLine(ParsedLine line, {TextStyle? paraStyle}) {
      bool textSpanUnderline = widget.rangeOfVersesToCopy.any(
          (ParsedLine element) =>
              element.book == line.book &&
              element.chapter == line.chapter &&
              element.verse == line.verse);

      TextStyle computedTextStyle =
          textSpanUnderline ? underlineStyle : (paraStyle ?? mainTextStyle);

      void tileOnTap() {
        widget.addVerseToCopyRange(line);
      }

      if (line.verse.isNotEmpty && line.verse != "0") {
        characterIndexToVerseMap[plainTextBuffer.length] = line;
      }

      final composed = verseComposer(
          line: line,
          computedTextStyle: computedTextStyle,
          includeFootnotes: true,
          context: context,
          tileOnTap: tileOnTap);

      plainTextBuffer.write(composed.versesAsString);
      return composed.versesAsSpans;
    }

    TextSpan s(String paragraphFragment, {num? fontScaling, bool? italics}) {
      plainTextBuffer.write(paragraphFragment);
      return TextSpan(
        text: paragraphFragment,
        style: mainTextStyle.copyWith(
            fontSize: fontScaling == null ? fontSize : fontSize * fontScaling,
            fontStyle: italics == null ? FontStyle.normal : FontStyle.italic,
            color: DefaultTextStyle.of(context).style.color),
      );
    }

    bool poetry = false;
    bool header = false;

    if (isIntro) {
      try {
        final line = widget.paragraph.first;
        // Per requirement, leave a switch for future styling.
        // For now, all intro lines are treated the same.
        switch (line.verseStyle) {
          //

          default:
            // The user wants each intro line to be an indented paragraph.
            // The indentation is added automatically for non-poetry paragraphs later.

            styledParagraphFragments
                .addAll(processLine(line, paraStyle: introStyle));
        }
      } catch (e) {
        debugPrint('Error adding intro');
        debugPrint(e.toString());
      }
    } else {
      for (var line in widget.paragraph) {
        switch (line.verseStyle) {
          case 'v':
            if (widget.textDirection == ui.TextDirection.ltr) {
              styledParagraphFragments.add(verseNumberLTR(line.verse));
            } else {
              styledParagraphFragments.add(verseNumberRTL(line.verse));
            }
            styledParagraphFragments.addAll(processLine(line));

            break;
          case 'm':
            styledParagraphFragments.addAll(processLine(line));

            break;
          case 's':
          case 's1':
          case 's2':
            styledParagraphFragments.add(s(line.verseText, fontScaling: 1.2));
            header = true;
            break;
          case 'mt1':
            styledParagraphFragments.add(s(line.verseText, fontScaling: 1.5));
            header = true;
            break;
          case 'mr':
            styledParagraphFragments
                .add(s(line.verseText, fontScaling: .9, italics: true));
            header = true;
            break;
          case 'ms':
          case 'ms1':
          case 'ms2':
            styledParagraphFragments.add(s(line.verseText, fontScaling: 1));
            header = true;
            break;
          case 'q':
          case 'q1':
          case 'q2':
            styledParagraphFragments.addAll(processLine(line));
            poetry = true;
            break;
          case 'd':
          case 'r':
            styledParagraphFragments
                .addAll(processLine(line, paraStyle: italicStyle));
            break;
          default:
            styledParagraphFragments.addAll(processLine(line));
        }
      }
    }

    bool indentAdded = false;
    if (styledParagraphFragments.length > 1 && !poetry && !header) {
      const indent = '    ';
      styledParagraphFragments.insert(
          0, TextSpan(text: indent, style: mainTextStyle));
      indentAdded = true;
    }

    // If indentation was added, we need to shift all character indices
    // to match the new positions in the final TextSpan.
    Map<int, ParsedLine> finalCharacterIndexToVerseMap = {};
    if (indentAdded) {
      characterIndexToVerseMap.forEach((key, value) {
        finalCharacterIndexToVerseMap[key + 4] = value; // 4 is indent length
      });
    } else {
      finalCharacterIndexToVerseMap = characterIndexToVerseMap;
    }

    List<InlineSpan> layoutSpans = [];
    for (final span in styledParagraphFragments) {
      if (span is WidgetSpan) {
        // The WidgetSpan is the footnote. Replace it with a simple TextSpan for layout.
        // The footnote is just a '*'
        layoutSpans.add(TextSpan(
            text: '*',
            style: mainTextStyle.copyWith(
              color: accentTextColor,
            )));
      } else {
        layoutSpans.add(span);
      }
    }

    setState(() {
      _cachedTextSpanWithWidgets = TextSpan(children: styledParagraphFragments);
      _cachedTextSpanForLayout = TextSpan(children: layoutSpans);
      _characterIndexToVerseMap = finalCharacterIndexToVerseMap;
    });
  }

  void _calculateAndReportLayout(BoxConstraints constraints) {
    if (_cachedTextSpanForLayout == null) return;

    final textPainter = TextPainter(
      text: _cachedTextSpanForLayout,
      textDirection: widget.textDirection,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(minWidth: 0, maxWidth: constraints.maxWidth);

    final List<VerseOffset> offsets = [];
    _characterIndexToVerseMap.forEach((charIndex, line) {
      // Make sure the character index is valid.
      if (charIndex < textPainter.text!.toPlainText().length) {
        final offset = textPainter.getOffsetForCaret(
            TextPosition(offset: charIndex), Rect.zero);
        offsets.add(VerseOffset(
          book: line.book,
          chapter: line.chapter,
          verse: line.verse,
          offset: offset,
        ));
      }
    });

    widget.onLayoutCalculated?.call(offsets);
  }

  @override
  Widget build(BuildContext context) {
    if (_cachedTextSpanWithWidgets == null || widget.paragraph.isEmpty) {
      return const SizedBox.shrink();
    }

    bool ltrText = widget.textDirection == ui.TextDirection.ltr;
    TextAlign paraAlignment = ltrText ? TextAlign.left : TextAlign.right;
    bool header = widget.paragraph.first.verseStyle.contains(RegExp(r'(s|mt)'));
    final ParsedLine currentFirstVerse = widget.paragraph.first;
    bool isPoetry = currentFirstVerse.verseStyle.contains(RegExp(r'q'));

    var padding = EdgeInsets.only(top: 8.0, left: 12, right: 12);
    if (isPoetry) {
      padding = const EdgeInsets.only(left: 32, bottom: 0.0);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Use a post-frame callback to ensure layout is complete before calculating.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _calculateAndReportLayout(constraints);
          }
        });

        Widget para = Padding(
          padding: padding,
          child: RichText(
            text: _cachedTextSpanWithWidgets!,
            textAlign: header ? TextAlign.center : paraAlignment,
            textDirection: widget.textDirection,
          ),
        );

        if (widget.addDivider) {
          return Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Container(
                padding: const EdgeInsets.only(top: 36),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: FluentTheme.of(context)
                          .accentColor, // Change to your desired color
                      width: 2.0, // Thickness of the border
                    ),
                  ),
                ),

                // padding: EdgeInsets.all(20),
                // height: 1,
                // color: FluentTheme.of(context).cardColor,
                child: para),
          );
        } else {
          return para;
        }
      },
    );
  }
}
