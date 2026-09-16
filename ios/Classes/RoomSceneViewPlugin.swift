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

    /// plan.json から組み立てた中身を入れる箱。作り直すときはこの下だけ消す。
    private var content = SCNNode()
    private var cameraNode = SCNNode()
    private var framed = false

    /// 最後に受け取った plan.json
    private var plan: [String: Any]? = nil
    /// 平面図で選ばれている番号
    private var selNo: Int = -1

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        scnView = SCNView(frame: frame)
        channel = FlutterMethodChannel(name: "room_scene_view_\(viewId)",
                                       binaryMessenger: messenger)
        super.init()

        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = UIColor.white

        // Flutter から渡された usdzPath を読む（plan.json が来るまでの仮表示）
        let dict = args as? [String: Any]
        let path = (dict?["usdzPath"] as? String) ?? ""
        let status = loadUsdz(path: path)

        // 生成時に plan.json が渡っていればそれを使う
        if let pj = dict?["planJson"] as? String, !pj.isEmpty {
            applyPlan(jsonText: pj)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.channel.invokeMethod("status", arguments: status)
        }

        // Flutter からの指示を受ける
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(nil); return }
            switch call.method {
            case "plan":
                if let s = call.arguments as? String { self.applyPlan(jsonText: s) }
                result(nil)
            case "select":
                if let n = call.arguments as? NSNumber {
                    let v = n.intValue
                    if v != self.selNo {
                        self.selNo = v
                        self.rebuild()
                    }
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView.addGestureRecognizer(tap)
    }

    func view() -> UIView { return scnView }

    // MARK: - plan.json から組み立てる

    private func applyPlan(jsonText: String) {
        guard let data = jsonText.data(using: .utf8) else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let d = obj as? [String: Any] else { return }
        plan = d
        rebuild()
    }

    /// mm の平面座標を SceneKit の座標に直す。平面のyは奥行き（-z）。
    private func pt(_ x: Double, _ y: Double) -> SCNVector3 {
        return SCNVector3(Float(x / 1000.0), 0, Float(-y / 1000.0))
    }

    private func rebuild() {
        guard let d = plan else { return }

        // 前の中身を捨てる
        content.removeFromParentNode()
        content = SCNNode()
        content.name = "PlanRoot"

        if scnView.scene == nil {
            let sc = SCNScene()
            sc.background.contents = UIColor.white
            scnView.scene = sc
        }
        // USDZ の中身が残っていたら消す
        scnView.scene?.rootNode.childNodes.forEach { n in
            if n !== cameraNode { n.removeFromParentNode() }
        }
        scnView.scene?.rootNode.addChildNode(content)

        var deleted = Set<Int>()
        if let dl = d["deleted"] as? [Any] {
            for v in dl { if let n = v as? NSNumber { deleted.insert(n.intValue) } }
        }

        // ---- 床 ----
        if let ring = d["ring"] as? [[Any]], ring.count >= 3 {
            let path = UIBezierPath()
            for (i, p) in ring.enumerated() {
                guard let a = p.first as? NSNumber, let b = p.last as? NSNumber else { continue }
                let x = CGFloat(a.doubleValue / 1000.0)
                let y = CGFloat(b.doubleValue / 1000.0)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            path.close()
            let shape = SCNShape(path: path, extrusionDepth: 0.02)
            shape.firstMaterial?.diffuse.contents = UIColor(white: 0.95, alpha: 1)
            shape.firstMaterial?.isDoubleSided = true
            let fn = SCNNode(geometry: shape)
            fn.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            fn.position = SCNVector3(0, -0.01, 0)
            fn.name = "PFloor"
            content.addChildNode(fn)
        }

        // ---- 開口部を壁ごとに束ねる ----
        var opensByWall: [Int: [[String: Any]]] = [:]
        if let ops = d["opens"] as? [[String: Any]] {
            for o in ops {
                guard let no = (o["no"] as? NSNumber)?.intValue,
                      let wn = (o["wall"] as? NSNumber)?.intValue else { continue }
                if deleted.contains(no) { continue }
                opensByWall[wn, default: []].append(o)
            }
        }

        // ---- 壁 ----
        if let walls = d["walls"] as? [[String: Any]] {
            for w in walls {
                guard let no = (w["no"] as? NSNumber)?.intValue,
                      let a = w["a"] as? [Any], let b = w["b"] as? [Any],
                      let ax = a.first as? NSNumber, let ay = a.last as? NSNumber,
                      let bx = b.first as? NSNumber, let by = b.last as? NSNumber
                else { continue }
                if deleted.contains(no) { continue }

                let x0 = ax.doubleValue, y0 = ay.doubleValue
                let x1 = bx.doubleValue, y1 = by.doubleValue
                let dx = x1 - x0, dy = y1 - y0
                let L = (dx * dx + dy * dy).squareRoot() / 1000.0
                if L < 0.001 { continue }
                let h = ((w["h"] as? NSNumber)?.doubleValue ?? 2400) / 1000.0
                let t = ((w["t"] as? NSNumber)?.doubleValue ?? 120) / 1000.0
                let outer = (w["outer"] as? NSNumber)?.boolValue ?? false

                var ops: [(s: CGFloat, w: CGFloat, z0: CGFloat, h: CGFloat,
                           kind: String, no: Int)] = []
                for o in (opensByWall[no] ?? []) {
                    let ono = (o["no"] as? NSNumber)?.intValue ?? 0
                    let ow = ((o["w"] as? NSNumber)?.doubleValue ?? 0) / 1000.0
                    var os = ((o["s"] as? NSNumber)?.doubleValue ?? 0) / 1000.0
                    let oh0 = ((o["h"] as? NSNumber)?.doubleValue ?? 0) / 1000.0
                    let osl = ((o["sill"] as? NSNumber)?.doubleValue ?? 0) / 1000.0
                    let kind = (o["kind"] as? String) ?? "window"
                    if ow <= 0.001 { continue }
                    // 高さが未入力なら、壁の高さの7割を仮に使う
                    let oh = oh0 > 0.001 ? oh0 : h * 0.7
                    if ow >= L { os = L / 2 } else {
                        os = min(max(os, ow / 2), L - ow / 2)
                    }
                    ops.append((s: CGFloat(os), w: CGFloat(ow),
                                z0: CGFloat(min(osl, max(0, h - oh))),
                                h: CGFloat(oh), kind: kind, no: ono))
                }

                let node = makeWall(no: no, length: CGFloat(L), height: CGFloat(h),
                                    thick: CGFloat(t), outer: outer, openings: ops)
                node.position = pt((x0 + x1) / 2, (y0 + y1) / 2)
                node.eulerAngles = SCNVector3(0, Float(atan2(dy, dx)), 0)
                content.addChildNode(node)
            }
        }

        // ---- 物体（階段・収納のみ）----
        if let objs = d["objs"] as? [[String: Any]] {
            for o in objs {
                guard let no = (o["no"] as? NSNumber)?.intValue,
                      let kind = o["kind"] as? String,
                      let pts = o["pts"] as? [[Any]], pts.count >= 3
                else { continue }
                if deleted.contains(no) { continue }
                if kind != "stairs" && kind != "storage" { continue }

                let oh: CGFloat = 0.7
                let path = UIBezierPath()
                for (i, p) in pts.enumerated() {
                    guard let a = p.first as? NSNumber, let b = p.last as? NSNumber else { continue }
                    let x = CGFloat(a.doubleValue / 1000.0)
                    let y = CGFloat(b.doubleValue / 1000.0)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                path.close()
                let shape = SCNShape(path: path, extrusionDepth: oh)
                shape.firstMaterial?.diffuse.contents =
                    (no == selNo) ? UIColor.systemRed.withAlphaComponent(0.6)
                                  : UIColor(white: 0.72, alpha: 1)
                shape.firstMaterial?.isDoubleSided = true
                let n = SCNNode(geometry: shape)
                n.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
                n.position = SCNVector3(0, Float(oh / 2), 0)
                n.name = "PB\(no)"
                content.addChildNode(n)
            }
        }

        // カメラは最初の1回だけ全体に合わせる
        if !framed {
            framed = true
            if cameraNode.camera == nil {
                cameraNode = SCNNode()
                cameraNode.camera = SCNCamera()
                cameraNode.camera?.zNear = 0.01
                cameraNode.camera?.zFar = 500
                scnView.scene?.rootNode.addChildNode(cameraNode)
                scnView.pointOfView = cameraNode
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                self.scnView.defaultCameraController.frameNodes([self.content])
            }
        }
    }

    // MARK: - 壁1枚を作る

    /// 壁1枚を、開口部を避けて上下左右に割って作る。
    /// 単位はメートル。x方向に長さ、y方向に高さ、z方向に厚み。
    /// 開口部の位置 s は壁の始点からの距離。
    private func makeWall(no: Int,
                          length: CGFloat,
                          height: CGFloat,
                          thick: CGFloat,
                          outer: Bool,
                          openings: [(s: CGFloat, w: CGFloat, z0: CGFloat, h: CGFloat, kind: String, no: Int)]) -> SCNNode {
        let root = SCNNode()
        root.name = "PW\(no)"

        let isSel = (no == selNo)
        let wallColor: UIColor = isSel
            ? UIColor.systemRed.withAlphaComponent(0.7)
            : UIColor(white: outer ? 0.86 : 0.93, alpha: 1)

        // 外壁は室内側の面を動かさず外向きに厚みを振る。内壁は芯から左右半分ずつ。
        let zc: CGFloat = outer ? (thick / 2) : 0

        let sorted = openings.sorted { $0.s < $1.s }

        func panel(x0: CGFloat, x1: CGFloat, y0: CGFloat, y1: CGFloat, part: String) {
            let w = x1 - x0, h = y1 - y0
            if w <= 0.001 || h <= 0.001 { return }
            let box = SCNBox(width: w, height: h, length: thick, chamferRadius: 0)
            box.firstMaterial?.diffuse.contents = wallColor
            let n = SCNNode(geometry: box)
            n.position = SCNVector3(Float(x0 + w / 2 - length / 2),
                                    Float(y0 + h / 2),
                                    Float(zc))
            n.name = "PW\(no)_\(part)"
            root.addChildNode(n)
        }

        var cursor: CGFloat = 0
        for o in sorted {
            let x0 = max(0, o.s - o.w / 2)
            let x1 = min(length, o.s + o.w / 2)

            panel(x0: cursor, x1: x0, y0: 0, y1: height, part: "L\(o.no)")
            panel(x0: x0, x1: x1, y0: 0, y1: o.z0, part: "under\(o.no)")
            panel(x0: x0, x1: x1, y0: o.z0 + o.h, y1: height, part: "over\(o.no)")

            // 開口そのもの。薄い板を置いてタップ対象にする。
            let fw = x1 - x0, fh = o.h
            if fw > 0.001 && fh > 0.001 {
                let plane = SCNPlane(width: fw, height: fh)
                plane.firstMaterial?.diffuse.contents =
                    (o.no == selNo) ? UIColor.systemRed.withAlphaComponent(0.55)
                                    : openColor(o.kind)
                plane.firstMaterial?.isDoubleSided = true
                let pn = SCNNode(geometry: plane)
                pn.position = SCNVector3(Float(x0 + fw / 2 - length / 2),
                                         Float(o.z0 + fh / 2),
                                         Float(zc))
                pn.name = "PO\(o.no)"
                root.addChildNode(pn)
            }

            cursor = max(cursor, x1)
        }
        panel(x0: cursor, x1: length, y0: 0, y1: height, part: "R")

        return root
    }

    private func openColor(_ kind: String) -> UIColor {
        switch kind {
        case "door":    return UIColor(red: 0.95, green: 0.45, blue: 0.00, alpha: 0.40)
        case "slide":   return UIColor(red: 0.26, green: 0.63, blue: 0.28, alpha: 0.40)
        case "closet":  return UIColor(red: 0.56, green: 0.14, blue: 0.67, alpha: 0.40)
        case "opening": return UIColor(red: 0.33, green: 0.43, blue: 0.48, alpha: 0.35)
        default:        return UIColor(red: 0.05, green: 0.55, blue: 0.85, alpha: 0.35)
        }
    }

    // MARK: - USDZ の読み込み（plan.json が来るまでの仮表示）

    private func loadUsdz(path: String) -> String {
        if path.isEmpty { return "USDZ path empty" }
        if !FileManager.default.fileExists(atPath: path) {
            return "USDZ not found: \(path)"
        }
        do {
            let url = URL(fileURLWithPath: path)
            let scene = try SCNScene(url: url, options: [.checkConsistency: false])
            scene.background.contents = UIColor.white
            scnView.scene = scene

            cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.camera?.zNear = 0.01
            cameraNode.camera?.zFar = 500
            scene.rootNode.addChildNode(cameraNode)
            scnView.pointOfView = cameraNode

            let (minV, maxV) = scene.rootNode.boundingBox
            let cx = (minV.x + maxV.x) / 2
            let cy = (minV.y + maxV.y) / 2
            let cz = (minV.z + maxV.z) / 2
            let sx = maxV.x - minV.x
            let sy = maxV.y - minV.y
            let sz = maxV.z - minV.z
            let span = max(max(sx, sy), sz)
            let dd = max(span * 1.6, 1.0)
            cameraNode.position = SCNVector3(cx + dd * 0.6, cy + dd * 0.8, cz + dd * 0.9)
            cameraNode.look(at: SCNVector3(cx, cy, cz))
            scnView.defaultCameraController.target = SCNVector3(cx, cy, cz)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self, self.plan == nil,
                      let root = self.scnView.scene?.rootNode else { return }
                self.scnView.defaultCameraController.frameNodes([root])
            }

            var names: [String] = []
            scene.rootNode.enumerateChildNodes { n, _ in
                if let s = n.name, !s.isEmpty { names.append(s) }
            }
            let head = names.prefix(8).joined(separator: ", ")
            return "USDZ OK nodes=\(names.count) [\(head)]"
        } catch {
            return "USDZ load error: \(error.localizedDescription)"
        }
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
