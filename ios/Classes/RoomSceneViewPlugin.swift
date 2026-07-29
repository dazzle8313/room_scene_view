import Flutter
import UIKit
import SceneKit

public class RoomSceneViewPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let factory = RoomSceneViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "room_scene_view")
    }
}

class RoomSceneViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withFrame frame: CGRect,
                viewIdentifier viewId: Int64,
                arguments args: Any?) -> FlutterPlatformView {
        return RoomSceneView(frame: frame, viewId: viewId, args: args, messenger: messenger)
    }
}

class RoomSceneView: NSObject, FlutterPlatformView {

    private let scnView: SCNView
    private let channel: FlutterMethodChannel

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        scnView = SCNView(frame: frame)
        channel = FlutterMethodChannel(name: "room_scene_view_\(viewId)",
                                       binaryMessenger: messenger)
        super.init()

        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = UIColor.white

        let status = buildTest()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.channel.invokeMethod("status", arguments: status)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView.addGestureRecognizer(tap)
    }

    func view() -> UIView { return scnView }

    // MARK: - 穴あき壁の生成テスト

    /// 壁1枚を、開口部を避けて上下左右4枚に割って作る。
    /// 単位はメートル。x方向に長さ、y方向に高さ、厚みはごく薄い板。
    private func makeWall(no: Int,
                          length: CGFloat,
                          height: CGFloat,
                          openings: [(t: CGFloat, w: CGFloat, z0: CGFloat, h: CGFloat, kind: String, no: Int)]) -> SCNNode {
        let root = SCNNode()
        root.name = "Wall\(no)"

        let thick: CGFloat = 0.02

        // 開口部を左端からの位置で並べる
        let sorted = openings.sorted { $0.t < $1.t }

        func panel(x0: CGFloat, x1: CGFloat, y0: CGFloat, y1: CGFloat, part: String) {
            let w = x1 - x0, h = y1 - y0
            if w <= 0.001 || h <= 0.001 { return }
            let box = SCNBox(width: w, height: h, length: thick, chamferRadius: 0)
            box.firstMaterial?.diffuse.contents = UIColor(white: 0.92, alpha: 1)
            let n = SCNNode(geometry: box)
            n.position = SCNVector3(x0 + w/2 - length/2, y0 + h/2, 0)
            n.name = "Wall\(no)_\(part)"
            root.addChildNode(n)
        }

        var cursor: CGFloat = 0
        for o in sorted {
            let cx = o.t * length
            let x0 = max(0, cx - o.w/2)
            let x1 = min(length, cx + o.w/2)

            // 開口の左側は全高
            panel(x0: cursor, x1: x0, y0: 0, y1: height, part: "L")
            // 開口の下
            panel(x0: x0, x1: x1, y0: 0, y1: o.z0, part: "under\(o.no)")
            // 開口の上
            panel(x0: x0, x1: x1, y0: o.z0 + o.h, y1: height, part: "over\(o.no)")

            // 開口そのもの（枠として薄い板を置き、タップ対象にする）
            let fw = x1 - x0, fh = o.h
            if fw > 0.001 && fh > 0.001 {
                let plane = SCNPlane(width: fw, height: fh)
                plane.firstMaterial?.diffuse.contents =
                    (o.kind == "door") ? UIColor.systemOrange.withAlphaComponent(0.35)
                                       : UIColor.systemBlue.withAlphaComponent(0.30)
                plane.firstMaterial?.isDoubleSided = true
                let pn = SCNNode(geometry: plane)
                pn.position = SCNVector3(x0 + fw/2 - length/2, o.z0 + fh/2, 0)
                pn.name = (o.kind == "door") ? "Door\(o.no)" : "Window\(o.no)"
                root.addChildNode(pn)
            }

            cursor = x1
        }
        // 最後の開口より右側
        panel(x0: cursor, x1: length, y0: 0, y1: height, part: "R")

        return root
    }

    private func buildTest() -> String {
        let scene = SCNScene()
        scene.background.contents = UIColor.white

        // 床
        let floor = SCNBox(width: 4.2, height: 0.02, length: 3.2, chamferRadius: 0)
        floor.firstMaterial?.diffuse.contents = UIColor(white: 0.97, alpha: 1)
        let fn = SCNNode(geometry: floor)
        fn.position = SCNVector3(0, -0.01, 0)
        fn.name = "Floor"
        scene.rootNode.addChildNode(fn)

        // 壁0: 窓2つ
        let w0 = makeWall(no: 0, length: 4.0, height: 2.4, openings: [
            (t: 0.30, w: 1.2, z0: 0.9, h: 1.2, kind: "window", no: 0),
            (t: 0.72, w: 0.8, z0: 0.9, h: 1.0, kind: "window", no: 1),
        ])
        w0.position = SCNVector3(0, 0, -1.5)
        scene.rootNode.addChildNode(w0)

        // 壁1: ドア1つ（床から）
        let w1 = makeWall(no: 1, length: 3.0, height: 2.4, openings: [
            (t: 0.5, w: 0.85, z0: 0.0, h: 2.0, kind: "door", no: 2),
        ])
        w1.position = SCNVector3(-2.0, 0, 0)
        w1.eulerAngles = SCNVector3(0, Float.pi/2, 0)
        scene.rootNode.addChildNode(w1)

        // 壁2: 開口なし
        let w2 = makeWall(no: 2, length: 4.0, height: 2.4, openings: [])
        w2.position = SCNVector3(0, 0, 1.5)
        scene.rootNode.addChildNode(w2)

        scnView.scene = scene

        var names: [String] = []
        scene.rootNode.enumerateChildNodes { n, _ in
            if let s = n.name, !s.isEmpty { names.append(s) }
        }
        return "TEST OK: nodes=\(names.count)\n" + names.prefix(12).joined(separator: ", ")
    }

    // MARK: - タップ

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let p = g.location(in: scnView)
        let hits = scnView.hitTest(p, options: nil)
        guard let hit = hits.first else {
            channel.invokeMethod("tap", arguments: "MISS")
            return
        }
        var chain: [String] = []
        var node: SCNNode? = hit.node
        while let cur = node {
            chain.append(cur.name ?? "(noname)")
            node = cur.parent
        }
        channel.invokeMethod("tap", arguments: chain.joined(separator: "  <  "))
    }
}
