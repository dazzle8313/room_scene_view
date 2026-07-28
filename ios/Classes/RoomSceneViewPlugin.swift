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

let status = load(args: args)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.channel.invokeMethod("status", arguments: status)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView.addGestureRecognizer(tap)
    }

    func view() -> UIView {
        return scnView
    }

    private func load(args: Any?) -> String {
        guard let dict = args as? [String: Any] else {
            return "ERR: no creationParams"
        }
        guard let path = dict["usdzPath"] as? String, !path.isEmpty else {
            return "ERR: usdzPath is empty"
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return "ERR: file not found\n\(path)"
        }
        do {
            let scene = try SCNScene(url: URL(fileURLWithPath: path), options: nil)
            scnView.scene = scene

            var names: [String] = []
            scene.rootNode.enumerateChildNodes { node, _ in
                if let n = node.name, !n.isEmpty { names.append(n) }
            }
            let head = names.prefix(10).joined(separator: ", ")
            return "OK: nodes=\(names.count)\n\(head)"
        } catch {
            return "ERR: load failed\n\(error.localizedDescription)"
        }
    }

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
