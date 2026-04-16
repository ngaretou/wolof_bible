import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

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
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _textBoxKey = GlobalKey();
  OverlayEntry? _overlayEntry;

  /// Index of the currently keyboard-highlighted item in the filtered list.
  /// -1 means nothing is highlighted (user is still typing in the text box).
  int _highlightedIndex = -1;

  @override
  void initState() {
    super.initState();
    _updateTextFromValue();
    focusNode.addListener(_onFocusChanged);
    controller.addListener(_onTextChanged);
  }

  String _lastText = '';

  void _onTextChanged() {
    if (controller.text != _lastText) {
      _lastText = controller.text;
      // Reset keyboard highlight when the user types new text
      _highlightedIndex = -1;
      // Whenever the user types and text officially changes, rebuild overlay.
      _overlayEntry?.markNeedsBuild();
    }
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

  /// Returns the current filtered list of keys, using the same logic as the overlay.
  List<K> _getFilteredKeys() {
    final text = controller.text.trim().toLowerCase();
    bool isInitialState = false;

    if (widget.value != null && widget.items.containsKey(widget.value)) {
      if (text == widget.displayString(widget.value as K).toLowerCase()) {
        isInitialState = true;
      }
    }

    return isInitialState || text.isEmpty
        ? widget.items.keys.toList()
        : widget.items.keys.where((k) {
            return widget.displayString(k).toLowerCase().contains(text);
          }).toList();
  }

  void _onFocusChanged() {
    debugPrint('focus changed');
    if (!focusNode.hasFocus) {
      debugPrint('focus changed unfocus');
      _removeOverlay();
      _updateTextFromValue();
      _highlightedIndex = -1;
    } else {
      debugPrint('focus changed focus');
      // Highlight text for immediate typing replacement
      Future.microtask(() {
        if (mounted && focusNode.hasFocus && controller.text.isNotEmpty) {
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          );
        }
      });
      _showOverlay();
    }
  }

  /// Handles keyboard events for navigating the dropdown list.
  /// Down Arrow / Tab: move highlight down (entering list on first press)
  /// Up Arrow: move highlight up
  /// Enter: select the highlighted item
  /// Escape: close the dropdown
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // Only handle key-down and key-repeat events
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // If the overlay isn't open, ignore navigation keys
    if (_overlayEntry == null) return KeyEventResult.ignored;

    final filteredKeys = _getFilteredKeys();
    if (filteredKeys.isEmpty) return KeyEventResult.ignored;

    // Down Arrow or Tab: move highlight down
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      setState(() {
        if (_highlightedIndex < filteredKeys.length - 1) {
          _highlightedIndex++;
        } else {
          // Wrap around to the top
          _highlightedIndex = 0;
        }
      });
      _overlayEntry?.markNeedsBuild();
      return KeyEventResult.handled;
    }

    // Up Arrow: move highlight up
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        if (_highlightedIndex > 0) {
          _highlightedIndex--;
        } else {
          // Wrap around to the bottom
          _highlightedIndex = filteredKeys.length - 1;
        }
      });
      _overlayEntry?.markNeedsBuild();
      return KeyEventResult.handled;
    }

    // Enter: select the highlighted item
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_highlightedIndex >= 0 && _highlightedIndex < filteredKeys.length) {
        final key = filteredKeys[_highlightedIndex];
        focusNode.unfocus();
        widget.onSelected?.call(key);
        return KeyEventResult.handled;
      }
    }

    // Escape: close the dropdown
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      focusNode.unfocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        final box =
            _textBoxKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) {
          debugPrint('box is null');
          return const SizedBox.shrink();
        }

        final size = box.size;
        final globalOffset = box.localToGlobal(Offset.zero);
        final mediaQuery = MediaQuery.of(context);
        final screenHeight = mediaQuery.size.height;
        final overlayY = globalOffset.dy + size.height;

        // Calculate max popup height, falling back to 300px
        double maxHeight = screenHeight - overlayY - 12.0;
        maxHeight = maxHeight.clamp(200.0, 600.0);

        return Positioned(
          width: size.width,
          child: TapRegion(
            groupId: _textBoxKey,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(0, size.height + 4),
              child: _buildOverlayContent(maxHeight),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  Widget _buildOverlayContent(double maxHeight) {
    final filteredKeys = _getFilteredKeys();

    return FluentTheme(
      data: FluentTheme.of(context),
      child: FlyoutContent(
        padding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: filteredKeys.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text('No results found'),
                )
              : _OverlayList<K>(
                  filteredKeys: filteredKeys,
                  widget: widget,
                  highlightedIndex: _highlightedIndex,
                  onSelected: (key) {
                    debugPrint('_OverlayList key selected: $key');
                    focusNode.unfocus();
                    widget.onSelected?.call(key);
                  },
                ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    focusNode.removeListener(_onFocusChanged);
    focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: _textBoxKey,
      child: CompositedTransformTarget(
        link: _layerLink,
        child: Focus(
          // Intercept keyboard events for dropdown navigation
          onKeyEvent: _handleKeyEvent,
          child: TextBox(
            key: _textBoxKey,
            controller: controller,
            focusNode: focusNode,
            placeholder: widget.placeholder,
            style: widget.style,
            suffix: IconButton(
              icon: const Icon(FluentIcons.chevron_down),
              onPressed: () {
                debugPrint('chevron_down IconButton pressed');
                if (focusNode.hasFocus) {
                  focusNode.unfocus();
                } else {
                  focusNode.requestFocus();
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayList<K> extends StatefulWidget {
  final List<K> filteredKeys;
  final FilterComboBox<K> widget;
  final ValueChanged<K> onSelected;
  final int highlightedIndex;

  const _OverlayList({
    required this.filteredKeys,
    required this.widget,
    required this.onSelected,
    this.highlightedIndex = -1,
  });

  @override
  State<_OverlayList<K>> createState() => _OverlayListState<K>();
}

class _OverlayListState<K> extends State<_OverlayList<K>> {
  final ScrollController _scrollController = ScrollController();

  /// Height of a single list item — matches Fluent UI's AutoSuggestBox:
  /// kOneLineTileHeight (40.0) + 2.0 padding = 42.0
  static const double _itemHeight = 42.0;

  @override
  void initState() {
    super.initState();
    // Scroll the list to the currently selected item after the frame is laid out
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToInitialPosition();
    });
  }

  @override
  void didUpdateWidget(_OverlayList<K> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the keyboard-highlighted index changes, scroll to keep it visible
    if (oldWidget.highlightedIndex != widget.highlightedIndex &&
        widget.highlightedIndex >= 0) {
      _scrollToIndex(widget.highlightedIndex);
    }
  }

  /// Scroll to the initially selected item when the dropdown first opens
  void _scrollToInitialPosition() {
    if (!mounted || !_scrollController.hasClients) return;
    final selectedKey = widget.widget.value;
    if (selectedKey != null) {
      final index = widget.filteredKeys.indexOf(selectedKey);
      if (index >= 0) {
        _scrollToIndex(index);
      }
    }
  }

  /// Scroll to ensure the item at [index] is visible in the list
  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;

    final desiredOffset = index * _itemHeight;
    final maxOffset = _scrollController.position.maxScrollExtent;
    final viewportHeight = _scrollController.position.viewportDimension;
    final currentOffset = _scrollController.offset;

    // If the item is already fully visible, don't scroll
    if (desiredOffset >= currentOffset &&
        desiredOffset + _itemHeight <= currentOffset + viewportHeight) {
      return;
    }

    // If item is above the viewport, scroll so it's at the top
    // If item is below the viewport, scroll so it's at the bottom
    double targetOffset;
    if (desiredOffset < currentOffset) {
      targetOffset = desiredOffset;
    } else {
      targetOffset = desiredOffset - viewportHeight + _itemHeight;
    }

    _scrollController.jumpTo(targetOffset.clamp(0.0, maxOffset));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      // Match AutoSuggestBox's internal configuration:
      // shrinkWrap + itemExtent enables proper scroll behavior within the overlay
      shrinkWrap: true,
      itemExtent: _itemHeight,
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 4.0),
      itemCount: widget.filteredKeys.length,
      itemBuilder: (context, index) {
        final key = widget.filteredKeys[index];
        final isSelected = key == widget.widget.value;
        final isHighlighted = index == widget.highlightedIndex;

        return Container(
          // Visual feedback for the selected and keyboard-highlighted items
          color: isHighlighted
              ? FluentTheme.of(context).accentColor.withValues(alpha: 0.35)
              : isSelected
              ? FluentTheme.of(context).accentColor.withValues(alpha: 0.2)
              : Colors.transparent,
          child: Listener(
            onPointerDown: (_) {
              // Firing on PointerDown guarantees it registers the exact microsecond the
              // mouse button goes down, before standard Flutter tap gestures and focus layers
              // have a chance to cancel the event!
              widget.onSelected(key);
            },
            behavior: HitTestBehavior.opaque,
            child: ListTile(
              title:
                  widget.widget.items[key] ??
                  Text(widget.widget.displayString(key)),
              onPressed:
                  null, // Visual feedback is handled natively or manually via the Container
            ),
          ),
        );
      },
    );
  }
}
