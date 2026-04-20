import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:wolof_bible/logic/data_initializer.dart';
import '../providers/user_prefs.dart';

class FilterComboBox<K> extends StatefulWidget {
  final Map<K, Widget> items;
  final String Function(K key) displayString;
  final void Function(K key)? onSelected;
  final String placeholder;
  final K? value;
  final TextStyle? style;

  const FilterComboBox({
    super.key,
    required this.items,
    required this.displayString,
    this.onSelected,
    this.value,
    this.style,
    this.placeholder = "...",
  });

  @override
  State<FilterComboBox<K>> createState() => _FilterComboBoxState<K>();
}

class _FilterComboBoxState<K> extends State<FilterComboBox<K>> {
  final controller = TextEditingController();
  final focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _updateTextFromValue();
    focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(FilterComboBox<K> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _updateTextFromValue();
    }
  }

  void _updateTextFromValue() {
    if (widget.value != null && widget.items.containsKey(widget.value)) {
      controller.text = widget.displayString(widget.value as K);
    } else {
      controller.clear();
    }
  }

  void _onFocusChanged() {
    // When the focus is lost, reset the text box to the actually selected value
    if (!focusNode.hasFocus) {
      _updateTextFromValue();
    } else {
      // When gaining focus, explicitly select all text. This way, if the user starts typing,
      // it instantly replaces the whole string (just like a native ComboBox).
      // We use a tiny microtask delay so it overrides the default tap-to-place-cursor behavior.
      Future.microtask(() {
        if (mounted && focusNode.hasFocus && controller.text.isNotEmpty) {
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    controller.dispose();
    focusNode.removeListener(_onFocusChanged);
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final translation = Provider.of<UserPrefs>(context).currentTranslation;

    // Map our generic items into AutoSuggestBoxItems
    List<AutoSuggestBoxItem<K>> suggestItems = widget.items.entries.map((
      entry,
    ) {
      // Pass the display name for the text filter, and the child widget for rendering
      return AutoSuggestBoxItem<K>(
        value: entry.key,
        label: widget.displayString(entry.key),
        child: entry.value,
      );
    }).toList();

    return AutoSuggestBox<K>(
      items: suggestItems,
      controller: controller,
      focusNode: focusNode,
      placeholder: widget.placeholder,
      style: widget.style,
      // Provide a custom sorter to handle the initial click behavior!
      sorter: (String text, List<AutoSuggestBoxItem<K>> overlayItems) {
        text = text.trim();
        if (text.isEmpty) return overlayItems;

        // If the text box perfectly equals the currently selected book, it means
        // the user just clicked it and hasn't started typing yet. We should
        // display the full un-filtered list!
        if (widget.value != null && widget.items.containsKey(widget.value)) {
          final currentDisplayString = widget.displayString(widget.value as K);
          if (text.toLowerCase() == currentDisplayString.toLowerCase()) {
            return overlayItems;
          }
        }

        // Otherwise, filter normally to text that contains the typed substring
        return overlayItems.where((element) {
          return element.label.toLowerCase().contains(text.toLowerCase());
        }).toList();
      },
      noResultsFoundBuilder: (context) => SizedBox(
        height: 40,
        child: Center(child: Text(translation.searchNoMatchesFound)),
      ),
      clearButtonEnabled:
          false, // Turn off clear button to mimic ComboBox behavior
      trailingIcon: IconButton(
        icon: Icon(
          FluentIcons.chevron_down,
          // from ComboBox widget, color and size
          size: 8,
          color: FluentTheme.of(context).resources.textFillColorSecondary,
        ),
        onPressed: () {
          debugPrint('onPressed from trailing icon');
          if (focusNode.hasFocus) {
            focusNode.unfocus();
          } else {
            focusNode.requestFocus();
            // controller.clear();
          }
        },
      ),
      onSelected: (item) {
        debugPrint("item selected: ${item.value}");
        // When user makes a selection
        if (item.value != null) {
          widget.onSelected?.call(item.value as K);
        }
      },
    );
  }
}
