import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RoomSceneView extends StatefulWidget {
  final String usdzPath;
  final ValueChanged<String>? onMessage;

  const RoomSceneView({
    Key? key,
    required this.usdzPath,
    this.onMessage,
  }) : super(key: key);

  @override
  State<RoomSceneView> createState() => _RoomSceneViewState();
}

class _RoomSceneViewState extends State<RoomSceneView> {
  MethodChannel? _channel;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return const ColoredBox(
        color: Color(0xFFEEEEEE),
        child: Center(child: Text('iOS jikki nomi')),
      );
    }
    return UiKitView(
      viewType: 'room_scene_view',
      layoutDirection: TextDirection.ltr,
      creationParams: <String, dynamic>{'usdzPath': widget.usdzPath},
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onCreated,
    );
  }

  void _onCreated(int id) {
    final ch = MethodChannel('room_scene_view_$id');
    ch.setMethodCallHandler((call) async {
      widget.onMessage?.call('${call.method}: ${call.arguments}');
      return null;
    });
    _channel = ch;
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }
}
