import 'package:fluent_ui/fluent_ui.dart';

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

  void _onFocusChanged() {
    debugPrint('focus changed');
    if (!focusNode.hasFocus) {
      debugPrint('focus changed unfocus');
      _removeOverlay();
      _updateTextFromValue();
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
    // Filter matching keys
    final text = controller.text.trim().toLowerCase();
    bool isInitialState = false;

    if (widget.value != null && widget.items.containsKey(widget.value)) {
      if (text == widget.displayString(widget.value as K).toLowerCase()) {
        isInitialState = true;
      }
    }

    final filteredKeys = isInitialState || text.isEmpty
        ? widget.items.keys.toList()
        : widget.items.keys.where((k) {
            return widget.displayString(k).toLowerCase().contains(text);
          }).toList();

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
    );
  }
}

class _OverlayList<K> extends StatefulWidget {
  final List<K> filteredKeys;
  final FilterComboBox<K> widget;
  final ValueChanged<K> onSelected;

  const _OverlayList({
    required this.filteredKeys,
    required this.widget,
    required this.onSelected,
  });

  @override
  State<_OverlayList<K>> createState() => _OverlayListState<K>();
}

class _OverlayListState<K> extends State<_OverlayList<K>> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Scroll the list perfectly to the currently selected item
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selectedKey = widget.widget.value;
      if (selectedKey != null) {
        final index = widget.filteredKeys.indexOf(selectedKey);
        if (index >= 0) {
          // A standard Fluent UI one-line ListTile is roughly 40px high.
          // By scrolling to exactly index * 40.0, the item will be positioned right at the top edge!
          final offset = index * 40.0;
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(offset);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      controller: _scrollController,
      itemCount: widget.filteredKeys.length,
      itemBuilder: (context, index) {
        final key = widget.filteredKeys[index];
        final isSelected = key == widget.widget.value;

        return Container(
          // Visual feedback for the selected item!
          color: isSelected
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
