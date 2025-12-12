import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../providers/user_prefs.dart';
// import 'package:hive_flutter/hive_flutter.dart';

// import '../hive/user_columns_db.dart';
import '../logic/data_initializer.dart';
import '../widgets/scripture_column.dart';
import '../providers/column_manager.dart';
import '../widgets/search.dart';
import '../widgets/resource_column.dart';

class BibleView extends StatefulWidget {
  final List<Collection> collections;
  final String? comboBoxFont;

  const BibleView({super.key, required this.collections, this.comboBoxFont});

  @override
  State<BibleView> createState() => _BibleViewState();
}

class _BibleViewState extends State<BibleView> {
  @override
  Widget build(BuildContext context) {
    // Consume the providers
    final userPrefs = Provider.of<UserPrefs>(context, listen: true);
    final columnManager = Provider.of<ColumnManager>(context, listen: true);

    // Generate ScriptureColumns from the source of truth
    List<Widget> scriptureWidgets = userPrefs.userColumns
        .where((ref) => ref.type == ColumnType.scripture)
        .map<Widget>((bibleRef) {
          return ScriptureColumn(
            key: bibleRef.key,
            myColumnIndex: bibleRef.columnIndex,
            collections: widget.collections,
            bibleReference: bibleRef,
            deleteColumn: (key) => userPrefs.deleteColumn(key),
            comboBoxFont: widget.comboBoxFont,
          );
        })
        .toList();

    List<Widget> resourceWidgets = userPrefs.userColumns
        .where((ref) => ref.type == ColumnType.resource)
        .map<Widget>((bibleRef) {
          return ResourceColumn(
            key: bibleRef.key,
            bibleReference: bibleRef,
            deleteColumn: (key) => userPrefs.deleteColumn(key),
            incomingUserResourceLanguageCode:
                int.tryParse(bibleRef.collectionID) ?? 4,
          );
        })
        .toList();

    List<Widget> children = [...scriptureWidgets, ...resourceWidgets];

    void closeSearch() {
      columnManager.toggleSearch();
      children.removeLast();
    }

    // Append SearchWidget if open
    if (columnManager.isSearchOpen) {
      children.add(
        SearchWidget(
          closeSearch: closeSearch,
          comboBoxFont: widget.comboBoxFont,
        ),
      );
    }

    return Container(
      //Bible view pane overall padding - each column has 5 above and then 2.5 l and r,
      //which when beside each other makes 5 between each col.
      //This padding here makes the first and last column have the full 5.
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      color: FluentTheme.of(context).scaffoldBackgroundColor,
      child: Row(children: children),
    );
  }
}
