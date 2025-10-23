// import 'package:flutter/gestures.dart';
// import 'package:flutter/material.dart';

// class SelectableTextWithSpanGestures extends StatefulWidget {
//   final TextSpan text;
//   final void Function(TextSpan? downSpan, TextSpan? upSpan)? onSpanInteraction;

//   const SelectableTextWithSpanGestures({
//     super.key,
//     required this.text,
//     this.onSpanInteraction,
//   });

//   @override
//   State<SelectableTextWithSpanGestures> createState() =>
//       _SelectableTextWithSpanGesturesState();
// }

// class _SelectableTextWithSpanGesturesState
//     extends State<SelectableTextWithSpanGestures> {
//   final GlobalKey _textKey = GlobalKey();
//   TextPainter? _painter;
//   TextSpan? _downSpan;

//   @override
//   Widget build(BuildContext context) {
//     return Listener(
//       onPointerDown: (event) {
//         _downSpan = _hitTestSpan(event.localPosition);
//         widget.onSpanInteraction?.call(_downSpan, null);
//       },
//       onPointerUp: (event) {
//         final upSpan = _hitTestSpan(event.localPosition);
//         widget.onSpanInteraction?.call(null, upSpan);
//       },
//       child: SelectableText.rich(
//         widget.text,
//         key: _textKey,
//       ),
//     );
//   }

//   TextSpan? _hitTestSpan(Offset localOffset) {
//     final renderBox = _textKey.currentContext?.findRenderObject() as RenderBox?;
//     if (renderBox == null) return null;

//     final size = renderBox.size;

//     // Build a TextPainter with the same span
//     _painter ??= TextPainter(
//       text: widget.text,
//       textDirection: TextDirection.ltr,
//     )..layout(maxWidth: size.width);

//     // Find the text position at the pointer offset
//     final pos = _painter!.getPositionForOffset(localOffset);

//     // Resolve which span contains that position
//     final span = _painter!.text!.getSpanForPosition(pos);
//     return span as TextSpan?;
//   }
// }

// SelectableTextWithSpanGestures(
//   text: TextSpan(
//     text: "Hello ",
//     style: const TextStyle(color: Colors.black, fontSize: 18),
//     children: [
//       TextSpan(
//         text: "world",
//         style: const TextStyle(color: Colors.blue),
//       ),
//       const TextSpan(text: " and "),
//       TextSpan(
//         text: "friends",
//         style: const TextStyle(color: Colors.green),
//       ),
//     ],
//   ),
//   onSpanInteraction: (down, up) {
//     if (down != null) {
//       debugPrint("Pointer down on: ${down.text}");
//     }
//     if (up != null) {
//       debugPrint("Pointer up on: ${up.text}");
//     }
//   },
// )
