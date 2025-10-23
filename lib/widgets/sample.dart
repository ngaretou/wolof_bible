// class SelectableSpans extends StatefulWidget {
//   final TextSpan span;
//   final void Function(TextSpan? downSpan, TextSpan? upSpan) onSpanInteraction;

//   const SelectableSpans({
//     required this.span,
//     required this.onSpanInteraction,
//     super.key,
//   });

//   @override
//   State<SelectableSpans> createState() => _SelectableSpansState();
// }

// class _SelectableSpansState extends State<SelectableSpans> {
//   final GlobalKey _textKey = GlobalKey();
//   TextPainter? _painter;

//   @override
//   Widget build(BuildContext context) {
//     return Listener(
//       onPointerDown: (event) {
//         final span = _hitTestSpan(event.localPosition);
//         widget.onSpanInteraction(span, null);
//       },
//       onPointerUp: (event) {
//         final span = _hitTestSpan(event.localPosition);
//         widget.onSpanInteraction(null, span);
//       },
//       child: SelectableText.rich(
//         widget.span,
//         key: _textKey,
//       ),
//     );
//   }

//   TextSpan? _hitTestSpan(Offset localOffset) {
//     final renderBox = _textKey.currentContext?.findRenderObject() as RenderBox?;
//     if (renderBox == null) return null;

//     final size = renderBox.size;
//     final textStyle = DefaultTextStyle.of(context).style;

//     _painter ??= TextPainter(
//       text: widget.span,
//       textDirection: TextDirection.ltr,
//     )..layout(maxWidth: size.width);

//     final pos = _painter!.getPositionForOffset(localOffset);
//     final span = _painter!.text!.getSpanForPosition(pos);
//     return span as TextSpan?;
//   }
// }

// SelectableSpans(
//   span: TextSpan(
//     text: "Hello ",
//     children: [
//       TextSpan(text: "world", style: TextStyle(color: Colors.blue)),
//       TextSpan(text: " again"),
//     ],
//   ),
//   onSpanInteraction: (down, up) {
//     if (down != null) {
//       print("Pointer down on: ${down.text}");
//     }
//     if (up != null) {
//       print("Pointer up on: ${up.text}");
//     }
//   },
// )

