// import 'dart:async';
// import 'dart:math';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:rxdart/rxdart.dart';
// import 'package:provider/provider.dart';
// import 'package:just_audio/just_audio.dart';
// import '../providers/player_manager.dart';

// class ControlButtons extends StatefulWidget {
//   final Function showPlayList; //parent method will be called from this child
//   final int wideVersionBreakPoint;

//   const ControlButtons({
//     super.key,
//     required this.showPlayList,
//     required this.wideVersionBreakPoint,
//   });

//   @override
//   ControlButtonsState createState() => ControlButtonsState();
// }

// class ControlButtonsState extends State<ControlButtons> {
//   late PlayerManager playerManager;
//   late AudioPlayer player;

//   @override
//   void initState() {
//     playerManager = Provider.of<PlayerManager>(context, listen: false);
//     player = playerManager.player;

//     super.initState();
//   }

//   Stream<PositionData> get _positionDataStream =>
//       Rx.combineLatest2<Duration, Duration?, PositionData>(
//         playerManager.player.positionStream,
//         playerManager.player.durationStream,
//         (position, reportedDuration) {
//           final duration = reportedDuration ?? Duration.zero;
//           return PositionData(position, duration);
//         },
//       );

//   @override
//   Widget build(BuildContext context) {
//     if (kDebugMode) debugPrint('player_controls build');

//     final mainRowIconSize = 36.0;

//     return Column(
//       children: [
//         //SeekBar
//         StreamBuilder<PositionData>(
//           stream: _positionDataStream,
//           builder: (context, snapshot) {
//             final positionData = snapshot.data;
//             return SeekBar(
//               duration: positionData?.duration ?? Duration.zero,
//               position: positionData?.position ?? Duration.zero,
//               onChangeEnd: (newPosition) async {
//                 await player.seek(newPosition);
//               },
//             );
//           },
//         ),

//         //This row is the control buttons.
//         Row(
//           mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//           children: [
//             //Previous button
//             Padding(
//               padding: const EdgeInsets.only(left: 5),
//               child: StreamBuilder<int?>(
//                 stream: player.currentIndexStream,
//                 builder: (context, snapshot) => IconButton(
//                   icon: Icon(
//                     Icons.skip_previous_rounded,
//                     size: mainRowIconSize,
//                   ),
//                   onPressed: player.hasPrevious ? player.seekToPrevious : null,
//                 ),
//               ),
//             ),

//             //back 10 seconds button
//             Padding(
//               padding: const EdgeInsets.only(left: 5),
//               child: StreamBuilder<PositionData>(
//                 stream: _positionDataStream,
//                 builder: (context, snapshot) {
//                   final positionData = snapshot.data;
//                   final position = positionData?.position ?? Duration.zero;
//                   return IconButton(
//                     icon: Icon(Icons.replay_10, size: mainRowIconSize),
//                     onPressed: position > Duration(seconds: 11)
//                         ? () async {
//                             await player.seek(position - Duration(seconds: 10));
//                           }
//                         : null,
//                   );
//                 },
//               ),
//             ),

//             // Play button
//             /// This StreamBuilder rebuilds whenever the player state changes, which
//             /// includes the playing/paused state and also the
//             /// loading/buffering/ready state. Depending on the state we show the
//             /// appropriate button or loading indicator.
//             Padding(
//               padding: const EdgeInsets.symmetric(horizontal: 5),
//               child: StreamBuilder<(bool, ProcessingState, int)>(
//                 stream: playerManager.playerStateStream,
//                 builder: (context, snapshot) {
//                   final (playing, processingState, sequenceLength) =
//                       snapshot.data ?? (false, ProcessingState.idle, 0);
//                   if (processingState == ProcessingState.loading ||
//                       processingState == ProcessingState.buffering) {
//                     return Container(
//                       margin: const EdgeInsets.all(8.0),
//                       width: 64.0,
//                       height: 64.0,
//                       child: const CircularProgressIndicator(),
//                     );
//                   } else if (!playing) {
//                     return IconButton(
//                       icon: const Icon(Icons.play_arrow),
//                       iconSize: 64.0,
//                       onPressed: sequenceLength > 0 ? player.play : null,
//                     );
//                   } else if (processingState != ProcessingState.completed) {
//                     return IconButton(
//                       icon: const Icon(Icons.pause),
//                       iconSize: 64.0,
//                       onPressed: player.pause,
//                     );
//                   } else {
//                     return IconButton(
//                       icon: const Icon(Icons.replay),
//                       iconSize: 64.0,
//                       onPressed: sequenceLength > 0
//                           ? () async {
//                               await player.seek(
//                                 Duration.zero,
//                                 index: player.effectiveIndices.first,
//                               );
//                             }
//                           : null,
//                     );
//                   }
//                 },
//               ),
//             ),

//             //forward 10 seconds button
//             Padding(
//               padding: const EdgeInsets.only(right: 5),
//               child: StreamBuilder<PositionData>(
//                 stream: _positionDataStream,
//                 builder: (context, snapshot) {
//                   final positionData = snapshot.data;
//                   final position = positionData?.position ?? Duration.zero;
//                   final duration = positionData?.duration ?? Duration.zero;
//                   return IconButton(
//                     icon: Icon(Icons.forward_10, size: mainRowIconSize),
//                     onPressed: (duration - position) > Duration(seconds: 11)
//                         ? () async {
//                             await player.seek(position + Duration(seconds: 10));
//                           }
//                         : null,
//                   );
//                 },
//               ),
//             ),

//             //Next button
//             Padding(
//               padding: const EdgeInsets.only(right: 5),
//               child: StreamBuilder<int?>(
//                 stream: player.currentIndexStream,
//                 builder: (context, snapshot) => IconButton(
//                   icon: Icon(Icons.skip_next_rounded, size: mainRowIconSize),
//                   onPressed: player.hasNext ? player.seekToNext : null,
//                 ),
//               ),
//             ),
//           ],
//         ),
//         //Second row of control buttons
//         // Download, share, playlist, speed
//         Padding(
//           padding: const EdgeInsets.only(
//             left: 24.0,
//             right: 24,
//             top: 8,
//             bottom: 16,
//           ),
//           child: Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               SizedBox(
//                 height: 48,
//                 width: 48,
//                 child: Center(
//                   child: StreamBuilder<double>(
//                     stream: player.speedStream,
//                     builder: (context, snapshot) {
//                       late String? speed;
//                       if (snapshot.data != null) {
//                         speed = snapshot.data?.toStringAsFixed(1);
//                       } else {
//                         speed = '1.0';
//                       }

//                       return MouseRegion(
//                         cursor: SystemMouseCursors.click,
//                         child: GestureDetector(
//                           child: Text(
//                             "${speed}x",
//                             style: Theme.of(context).textTheme.titleSmall!
//                                 .copyWith(fontWeight: FontWeight.bold),
//                           ),
//                           onTap: () {
//                             _showSliderDialog(
//                               context: context,
//                               title:
//                                   'AppLocalizations.of(context)!.adjustSpeed',
//                               divisions: 10,
//                               min: 0.5,
//                               max: 1.5,
//                               stream: player.speedStream,
//                               onChanged: player.setSpeed,
//                             );
//                           },
//                         ),
//                       );
//                     },
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }

// class SeekBar extends StatefulWidget {
//   final Duration duration;
//   final Duration position;
//   final ValueChanged<Duration>? onChanged;
//   final ValueChanged<Duration>? onChangeEnd;

//   const SeekBar({
//     super.key,
//     required this.duration,
//     required this.position,
//     this.onChanged,
//     this.onChangeEnd,
//   });

//   @override
//   State<SeekBar> createState() => _SeekBarState();
// }

// class _SeekBarState extends State<SeekBar> {
//   double? _dragValue;

//   @override
//   Widget build(BuildContext context) {
//     return Stack(
//       children: [
//         Slider(
//           min: 0.0,
//           max: widget.duration.inMilliseconds.toDouble(),
//           value: min(
//             _dragValue ?? widget.position.inMilliseconds.toDouble(),
//             widget.duration.inMilliseconds.toDouble(),
//           ),
//           onChanged: (value) {
//             setState(() {
//               _dragValue = value;
//             });
//             if (widget.onChanged != null) {
//               widget.onChanged!(Duration(milliseconds: value.round()));
//             }
//           },
//           onChangeEnd: (value) {
//             if (widget.onChangeEnd != null) {
//               widget.onChangeEnd!(Duration(milliseconds: value.round()));
//             }
//             _dragValue = null;
//           },
//         ),
//         Positioned(
//           right: 16.0,
//           bottom: 0.0,
//           // If the player is not yet initialized....
//           child: Text(
//             RegExp(
//                   r'((^0*[1-9]\d*:)?\d{2}:\d{2})\.\d+',
//                 ).firstMatch("$_remaining")?.group(1) ??
//                 '$_remaining',
//             style: Theme.of(context).textTheme.titleSmall,
//           ),
//         ),
//       ],
//     );
//   }

//   Duration get _remaining => widget.duration - widget.position;
// }

// void _showSliderDialog({
//   required BuildContext context,
//   String? title,
//   int? divisions,
//   double min = 0,
//   double max = 0,
//   String valueSuffix = '',
//   Stream<double>? stream,
//   ValueChanged<double>? onChanged,
// }) {
//   showDialog(
//     context: context,
//     builder: (context) => AlertDialog(
//       title: Text(title ?? '', textAlign: TextAlign.center),
//       content: StreamBuilder<double>(
//         stream: stream,
//         builder: (context, snapshot) => SizedBox(
//           height: 100.0,
//           child: Column(
//             children: [
//               Text(
//                 '${snapshot.data?.toStringAsFixed(1)}$valueSuffix',
//                 style: TextStyle(
//                   fontFamily: 'Fixed',
//                   fontWeight: FontWeight.bold,
//                   fontSize: 24.0,
//                 ),
//               ),
//               Slider(
//                 divisions: divisions,
//                 min: min,
//                 max: max,
//                 value: snapshot.data ?? 1.0,
//                 onChanged: onChanged,
//               ),
//             ],
//           ),
//         ),
//       ),
//     ),
//   );
// }

// class PositionData {
//   final Duration position;

//   final Duration duration;

//   PositionData(this.position, this.duration);
// }
