import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_html/flutter_html.dart';
// ignore: depend_on_referenced_packages
import 'package:html/parser.dart' as html_parser;
// ignore: depend_on_referenced_packages
import 'package:html/dom.dart' as dom;
import '../providers/aquifer_classes.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wolof_bible/providers/user_prefs.dart';
import '../logic/aquifer_api.dart';

class ContentTile extends StatefulWidget {
  final ResourceItem item;
  final double baseFontSize;

  const ContentTile({
    super.key,
    required this.item,
    required this.baseFontSize,
  });

  @override
  State<ContentTile> createState() => _ContentTileState();
}

class _ContentTileState extends State<ContentTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final List<ResourceCollectionInfo> collections =
        AquiferService().allCollections;
    final code = widget.item.resourceCollectionCode;
    final collection = collections.firstWhere(
      (c) => c.code == code,
      orElse: () => ResourceCollectionInfo(
        code: code,
        resourceType: ResourceType.studyNotes,
        licenseInfo: LicenseInfo(
          code: code,
          dates: '',
          holderName: 'Unknown',
          holderUrl: '',
          licenseName: '',
          licenseUrl: '',
        ),
        availableLanguages: [],
      ),
    );
    final displayName = collection.availableLanguages
        .firstWhere(
          (l) => l.id == widget.item.langID,
          orElse: () => AvailableLanguage(
            id: 0,
            code: '',
            displayName: collection.code,
            scriptDirection: 'LTR',
          ),
        )
        .displayName;
    final licenseInfo = collection.licenseInfo;
    final copyrightStatement =
        '''
$displayName © ${licenseInfo.dates} ${licenseInfo.holderName}
    ${licenseInfo.holderUrl}
${licenseInfo.licenseName}
    ${licenseInfo.licenseUrl}
''';
    final translation = Provider.of<UserPrefs>(
      context,
      listen: true,
    ).currentTranslation;
    String lastSelectedText = '';
    Color accentColor = FluentTheme.of(context).accentColor;
    Color backgroundColor = FluentTheme.of(
      context,
    ).cardColor.lerpWith(Colors.grey, .1);
    IconData icon = FluentIcons.info;
    bool isNote = false;

    if (code.contains('Intro')) {
      icon = FluentIcons.book_answers;
      isNote = false;
    } else if (code.contains('Themes')) {
      icon = FluentIcons.favorite_star_fill;
      // accentColor = FluentTheme.of(
      //   context,
      // ).cardColor.lerpWith(Colors.orange, 1);

      isNote = false;
    } else if (code.contains('Profiles')) {
      icon = FluentIcons.profile_search;

      isNote = false;
    } else if (code.contains('Notes')) {
      icon = FluentIcons.reading_mode_solid;
      // accentColor = FluentTheme.of(context).cardColor.lerpWith(Colors.blue, .1);

      isNote = true;
    } else if (code.contains('Image')) {
      icon = FluentIcons.picture_fill;
      // accentColor = FluentTheme.of(
      //   context,
      // ).cardColor.lerpWith(Colors.green, .1);
      isNote = false;
    }
    final Map<String, Style> htmlStyles = {
      "body": Style(
        margin: Margins.zero,
        padding: HtmlPaddings.zero,
        fontSize: FontSize(widget.baseFontSize - 6),
        color: FluentTheme.of(context).typography.body!.color,

        // fontFamily: 'Gentium', // Assuming a good font defaults
      ),
      // we're not quite ready to handle hyperlinks so make them invisible
      "a": Style(
        color: FluentTheme.of(context).typography.body!.color,
        textDecoration: TextDecoration.none,
      ),

      "p": Style(margin: Margins.only(bottom: 8)),
      "h1": Style(
        margin: Margins.zero,
        padding: HtmlPaddings.zero,
        fontSize: FontSize(widget.baseFontSize - 2),
        fontWeight: FontWeight.w600,
        // color: accentColor,
      ),
      "h2": Style(
        margin: Margins.zero,
        padding: HtmlPaddings.zero,
        fontSize: FontSize(widget.baseFontSize - 2),
        fontWeight: FontWeight.normal,
      ),
      "h3": Style(
        margin: Margins.zero,
        padding: HtmlPaddings.zero,
        fontSize: FontSize(widget.baseFontSize - 4),
      ),
    };
    // Determine visuals based on collection code

    // Determine directionality
    final TextDirection textDirection = widget.item.scriptDirection == 'RTL'
        ? TextDirection.rtl
        : TextDirection.ltr;

    Widget buildImageContent() {
      if (widget.item.content.isEmpty) return const SizedBox.shrink();
      return Center(
        child: Image.network(
          widget.item.content,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const ProgressBar();
          },
          errorBuilder: (context, error, stackTrace) {
            return const Icon(
              FluentIcons.error_badge,
              color: Colors.errorPrimaryColor,
            );
          },
        ),
      );
    }

    Widget noteBody() {
      Widget noteSource() {
        return Tooltip(
          message: '$copyrightStatement\n(Click to copy)',
          child: GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: copyrightStatement));
              showDialog(
                barrierDismissible: true,
                context: context,
                builder: (dialogContext) {
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop();
                  });

                  return ContentDialog(
                    content: Container(
                      height: 50,
                      width: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green,
                      ),
                      child: Icon(FluentIcons.check_mark, color: Colors.white),
                    ),
                  );
                },
              );
            },
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                displayName,
                style: TextStyle(
                  fontSize: widget.baseFontSize - 8,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        );
      }

      // Logic for expandable content
      Widget contentWidget;
      if (widget.item.resourceType == ResourceType.images) {
        contentWidget = buildImageContent();
      } else if (!isNote && widget.item.content.length > 600) {
        if (_isExpanded) {
          // Expanded view: Scrollable SizedBox
          contentWidget = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 300,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Html(data: widget.item.content, style: htmlStyles),
                      noteSource(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: IconButton(
                  icon: const Icon(FluentIcons.remove),
                  onPressed: () {
                    setState(() {
                      _isExpanded = false;
                    });
                  },
                ),
              ),
            ],
          );
        } else {
          // Collapsed view: Truncated text + Button
          contentWidget = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Html(
                data: '${widget.item.content.substring(0, 600)}...',
                style: htmlStyles,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: IconButton(
                  icon: const Icon(FluentIcons.add),
                  onPressed: () {
                    setState(() {
                      _isExpanded = true;
                    });
                  },
                ),
              ),
            ],
          );
        }
      } else {
        // Short content, standard display
        contentWidget = Column(
          children: [
            Html(data: widget.item.content, style: htmlStyles),
            noteSource(),
          ],
        );
      }

      return SelectionArea(
        contextMenuBuilder:
            (BuildContext context, SelectableRegionState regionState) {
              void resetSelection() {
                ContextMenuController.removeAny();
                regionState.clearSelection();
              }

              // just grab the selection
              Future<void> simpleCopy() async {
                final selected = lastSelectedText;
                await Clipboard.setData(ClipboardData(text: selected));
                resetSelection();
              }

              Future<void> selectAll() async {
                regionState.selectAll();
              }

              Future<void> copyWholeNote() async {
                final fullNote =
                    '''
${widget.item.localizedName} 
${htmlToPlainText(widget.item.content)} 

$copyrightStatement
''';

                await Clipboard.setData(ClipboardData(text: fullNote));

                if (!context.mounted) return;

                showDialog(
                  barrierDismissible: true,
                  context: context,
                  builder: (dialogContext) {
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (!dialogContext.mounted) return;
                      Navigator.of(dialogContext).pop();
                    });

                    return ContentDialog(
                      content: Container(
                        height: 50,
                        width: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.green,
                        ),
                        child: Icon(
                          FluentIcons.check_mark,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                );
              }

              // the defaults
              // final buttonItems = regionState.contextMenuButtonItems;

              return AdaptiveTextSelectionToolbar.buttonItems(
                anchors: regionState.contextMenuAnchors,

                buttonItems: [
                  ContextMenuButtonItem(
                    label: translation.copy,
                    onPressed: simpleCopy,
                  ),
                  ContextMenuButtonItem(
                    label: "Select All",
                    // label: translation.copyWithNumbers,
                    onPressed: selectAll,
                  ),
                  ContextMenuButtonItem(
                    label: "Copy Note",
                    // label: translation.copyWithoutNumbers,
                    onPressed: copyWholeNote,
                  ),
                ],
              );
            },
        onSelectionChanged: (selection) {
          lastSelectedText = selection?.plainText ?? '';
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(icon, color: accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.item.localizedName,
                    style: TextStyle(
                      // color: FluentTheme.of(context).accentColor,
                      // fontFamily: 'font1,
                      fontSize: widget.baseFontSize - 2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            // Content
            contentWidget,
          ],
        ),
      );
    }

    return Directionality(
      textDirection: textDirection,
      child: isNote
          ? Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 8.0,
                horizontal: 12.0,
              ),
              child: noteBody(),
            )
          : Card(
              margin: const EdgeInsets.symmetric(
                vertical: 8.0,
                horizontal: 4.0,
              ),
              padding: const EdgeInsets.all(12.0),
              // borderColor: accentColor.withAlpha(128),
              backgroundColor: backgroundColor,
              child: noteBody(),
            ),
    );
  }
}

/// Converts HTML into plain text, preserving newlines and lists.
String htmlToPlainText(String htmlString) {
  if (htmlString.isEmpty) return '';

  final document = html_parser.parse(htmlString);
  final buffer = StringBuffer();

  void walk(dom.Node node) {
    if (node is dom.Text) {
      buffer.write(node.text);
    } else if (node is dom.Element) {
      switch (node.localName) {
        case 'br':
          buffer.write('\n');
          break;
        case 'p':
        case 'div':
        case 'section':
        case 'header':
        case 'footer':
          buffer.write('\n');
          node.nodes.forEach(walk);
          buffer.write('\n');
          break;
        case 'li':
          buffer.write('• ');
          node.nodes.forEach(walk);
          buffer.write('\n');
          break;
        case 'ul':
        case 'ol':
          buffer.write('\n');
          node.nodes.forEach(walk);
          buffer.write('\n');
          break;
        default:
          node.nodes.forEach(walk);
      }
    }
  }

  document.body?.nodes.forEach(walk);

  // Normalize multiple newlines
  return buffer.toString().replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n').trim();
}
