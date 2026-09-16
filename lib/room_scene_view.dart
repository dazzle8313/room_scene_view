import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RoomSceneView extends StatefulWidget {
  final String usdzPath;

  /// plan.json の文字列。渡すと3Dをこの内容から組み立て直す。
  /// 空なら usdzPath のモデルをそのまま表示する。
  final String planJson;

  /// 平面図で選択中の番号。3D側で色を変える。選択なしは -1。
  final int selNo;

  final ValueChanged<String>? onMessage;

  const RoomSceneView({
    Key? key,
    required this.usdzPath,
    this.planJson = '',
    this.selNo = -1,
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
      creationParams: <String, dynamic>{
        'usdzPath': widget.usdzPath,
        'planJson': widget.planJson,
      },
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
    // 生成中に値が変わっていることがあるので、いまの状態を送り直す
    _send();
  }

  @override
  void didUpdateWidget(covariant RoomSceneView old) {
    super.didUpdateWidget(old);
    if (old.planJson != widget.planJson || old.selNo != widget.selNo) {
      _send(planChanged: old.planJson != widget.planJson);
    }
  }

  void _send({bool planChanged = true}) {
    final ch = _channel;
    if (ch == null) return;
    if (planChanged && widget.planJson.isNotEmpty) {
      ch.invokeMethod('plan', widget.planJson);
    }
    ch.invokeMethod('select', widget.selNo);
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }
}
