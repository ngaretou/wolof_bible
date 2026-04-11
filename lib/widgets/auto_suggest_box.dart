import 'package:fluent_ui/fluent_ui.dart';

class FluentAutoSuggestBox<K> extends StatefulWidget {
  final Map<K, Widget> items;
  final String Function(K key) displayString;
  final void Function(K key)? onSelected;
  final String placeholder;

  const FluentAutoSuggestBox({
    super.key,
    required this.items,
    required this.displayString,
    this.onSelected,
    this.placeholder = "Search…",
  });

  @override
  State<FluentAutoSuggestBox<K>> createState() =>
      _FluentAutoSuggestBoxState<K>();
}

class _FluentAutoSuggestBoxState<K> extends State<FluentAutoSuggestBox<K>> {
  final controller = TextEditingController();
  final flyoutController = FlyoutController();

  List<K> filteredKeys = [];

  void updateSuggestions(String input) {
    final lower = input.toLowerCase();

    setState(() {
      filteredKeys = widget.items.keys
          .where((k) => widget.displayString(k).toLowerCase().contains(lower))
          .toList();
    });

    if (filteredKeys.isNotEmpty) {
      flyoutController.showFlyout(
        builder: (context) {
          return FlyoutContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: filteredKeys.map((key) {
                return ListTile(
                  title: widget.items[key],
                  onPressed: () {
                    controller.text = widget.displayString(key);
                    flyoutController.close();
                    widget.onSelected?.call(key);
                  },
                );
              }).toList(),
            ),
          );
        },
      );
    } else {
      flyoutController.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: flyoutController,
      child: TextBox(
        controller: controller,
        placeholder: widget.placeholder,
        onChanged: updateSuggestions,
      ),
    );
  }
}

  // Map<String, Widget> items = {};

  //                   for (var e in currentCollectionBooks) {
  //                     late String name;
  //                     if (e.name.contains('Προσ')) {
  //                       name = e.name.substring(5);
  //                     } else {
  //                       name = e.name;
  //                     }

  //                     items.addAll({
  //                       e.id: Align(
  //                         alignment: alignment,
  //                         child: Text(
  //                           name,
  //                           overflow: textOverflow,
  //                           textDirection: textDirection,
  //                         ),
  //                       ),
  //                     });
  //                   }

  //                   return FluentAutoSuggestBox(
  //                     items: items,
  //                     displayString: (key) => key,
  //                     onSelected: (value) {
  //                       setActiveColumnKey();
  //                       scrollToReference(
  //                         collection: currentCollection.value,
  //                         bookID: value,
  //                         chapter: currentChapter.value,
  //                         verse: currentVerse.value,
  //                         thisColumnNavigation: true,
  //                       );
  //                     },
  //                   );