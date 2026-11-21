import Foundation
import RealityKit
import UIKit
import simd

// Загрузка 3D-модели тела.
// 1) Своя профессиональная модель: Документы/OxionBody/body.usdz — объекты должны называться по ID справочника
//    («chest_upper_l», «lats_r», …). Всё остальное в файле считается кожей и не выбирается.
// 2) Встроенная модель: Assets → body.dataset/body.oxb (сжатый DEFLATE, 41 часть по тем же ID + «skin»).

struct BodyMeshPart: @unchecked Sendable {
    let name: String
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let indices: [UInt32]
    let boundsMin: SIMD3<Float>
    let boundsMax: SIMD3<Float>
}

enum Body3DSource: String { case builtIn = "Встроенная модель", custom = "Своя модель (USDZ)" }

struct Body3DLoaded {
    let body: Entity                       // корень модели, центр тела в (0,0,0), рост 1.8
    let parts: [MusclePartID: Entity]      // выбираемые объекты
    let skin: [Entity]
    let meshes: [MusclePartID: BodyMeshPart]   // для точного попадания касанием (встроенная модель)
    var skinMeshes: [BodyMeshPart] = []
    let source: Body3DSource
}

enum Body3DAssetError: LocalizedError {
    case missing, broken, noParts
    var errorDescription: String? {
        switch self {
        case .missing: "Файл модели не найден в приложении"
        case .broken: "Файл модели повреждён"
        case .noParts: "В USDZ нет объектов с именами мышц (например, chest_upper_l)"
        }
    }
}

enum Body3DAsset {
    static var customURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("OxionBody", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("body.usdz")
    }
    static var hasCustom: Bool { FileManager.default.fileExists(atPath: customURL.path) }

    static func installCustom(from url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if hasCustom { try FileManager.default.removeItem(at: customURL) }
        try FileManager.default.copyItem(at: url, to: customURL)
    }

    static func removeCustom() { try? FileManager.default.removeItem(at: customURL) }

    @MainActor private static var cache: [BodyMeshPart]?

    @MainActor
    static func load() async throws -> Body3DLoaded {
        if hasCustom, let c = try? await loadCustom() { return c }
        return try await loadBuiltIn()
    }

    // MARK: встроенная

    @MainActor
    static func loadBuiltIn() async throws -> Body3DLoaded {
        let parts: [BodyMeshPart]
        if let cache { parts = cache } else {
            guard let asset = NSDataAsset(name: "body") else { throw Body3DAssetError.missing }
            let raw = asset.data
            guard let p = await Task.detached(priority: .userInitiated, operation: { parse(raw) }).value else { throw Body3DAssetError.broken }
            cache = p
            parts = p
        }
        let body = Entity()
        body.name = "oxion_body"
        var map: [MusclePartID: Entity] = [:]
        var meshes: [MusclePartID: BodyMeshPart] = [:]
        var skin: [Entity] = []
        var skinMeshes: [BodyMeshPart] = []
        for p in parts {
            var d = MeshDescriptor(name: p.name)
            d.positions = MeshBuffers.Positions(p.positions)
            d.normals = MeshBuffers.Normals(p.normals)
            d.primitives = .triangles(p.indices)
            let mesh = try MeshResource.generate(from: [d])
            let e = ModelEntity(mesh: mesh, materials: [Body3DPalette.material(Body3DPalette.skin)])
            e.name = p.name
            body.addChild(e)
            if let id = MusclePartID(p.name) { map[id] = e; meshes[id] = p } else { skin.append(e); skinMeshes.append(p) }
            await Task.yield()
        }
        return Body3DLoaded(body: body, parts: map, skin: skin, meshes: meshes, skinMeshes: skinMeshes, source: .builtIn)
    }

    // MARK: своя USDZ

    @MainActor
    static func loadCustom() async throws -> Body3DLoaded {
        let root = try await Entity(contentsOf: customURL)
        var map: [MusclePartID: Entity] = [:]
        var skin: [Entity] = []
        func walk(_ e: Entity) {
            if let id = MusclePartID(e.name.lowercased()) {
                map[id] = e
                return
            }
            if e.components.has(ModelComponent.self) { skin.append(e) }
            for c in e.children { walk(c) }
        }
        walk(root)
        guard !map.isEmpty else { throw Body3DAssetError.noParts }
        // нормализуем: рост 1.8, центр тела в нуле
        let b = root.visualBounds(relativeTo: nil)
        let h = max(0.001, b.extents.y)
        let s = 1.8 / h
        let holder = Entity()
        holder.name = "oxion_body"
        holder.addChild(root)
        root.scale = SIMD3(repeating: s)
        root.position = -b.center * s
        root.generateCollisionShapes(recursive: true)
        return Body3DLoaded(body: holder, parts: map, skin: skin, meshes: [:], source: .custom)
    }

    // MARK: разбор встроенного файла

    static func parse(_ compressed: Data) -> [BodyMeshPart]? {
        guard let data = try? (compressed as NSData).decompressed(using: .zlib) as Data else { return nil }
        return data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> [BodyMeshPart]? in
            guard buf.count > 32, buf[0] == 0x4F, buf[1] == 0x58, buf[2] == 0x42, buf[3] == 0x31 else { return nil }
            var o = 4
            func f32() -> Float { let v = buf.loadUnaligned(fromByteOffset: o, as: Float.self); o += 4; return v }
            func u32() -> Int { let v = buf.loadUnaligned(fromByteOffset: o, as: UInt32.self); o += 4; return Int(v) }
            let mn = SIMD3<Float>(f32(), f32(), f32())
            let mx = SIMD3<Float>(f32(), f32(), f32())
            let sc = (mx - mn) / 65535
            let n = u32()
            var out: [BodyMeshPart] = []
            for _ in 0..<n {
                guard o < buf.count else { return nil }
                let l = Int(buf[o]); o += 1
                let name = String(decoding: UnsafeRawBufferPointer(rebasing: buf[o..<(o + l)]), as: UTF8.self); o += l
                let vc = u32(), ic = u32()
                guard o + vc * 9 + ic * 4 <= buf.count else { return nil }
                var pos = [SIMD3<Float>](); pos.reserveCapacity(vc)
                var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
                for i in 0..<vc {
                    let b = o + i * 6
                    let q = SIMD3<Float>(Float(buf.loadUnaligned(fromByteOffset: b, as: UInt16.self)),
                                         Float(buf.loadUnaligned(fromByteOffset: b + 2, as: UInt16.self)),
                                         Float(buf.loadUnaligned(fromByteOffset: b + 4, as: UInt16.self)))
                    let p = mn + q * sc
                    pos.append(p)
                    lo = simd_min(lo, p); hi = simd_max(hi, p)
                }
                o += vc * 6
                var nrm = [SIMD3<Float>](); nrm.reserveCapacity(vc)
                for i in 0..<vc {
                    let b = o + i * 3
                    nrm.append(SIMD3<Float>(Float(buf.loadUnaligned(fromByteOffset: b, as: Int8.self)),
                                            Float(buf.loadUnaligned(fromByteOffset: b + 1, as: Int8.self)),
                                            Float(buf.loadUnaligned(fromByteOffset: b + 2, as: Int8.self))) / 127)
                }
                o += vc * 3
                var idx = [UInt32](repeating: 0, count: ic)
                idx.withUnsafeMutableBytes { dst in
                    dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: buf[o..<(o + ic * 4)]))
                }
                o += ic * 4
                out.append(BodyMeshPart(name: name, positions: pos, normals: nrm, indices: idx, boundsMin: lo, boundsMax: hi))
            }
            return out
        }
    }

    /// Точное попадание луча в треугольники (Мёллер — Трумбор). Луч в координатах модели.
    static func hit(_ parts: [MusclePartID: BodyMeshPart], origin: SIMD3<Float>, dir: SIMD3<Float>) -> MusclePartID? {
        var best: Float = .greatestFiniteMagnitude
        var bestId: MusclePartID?
        let inv = SIMD3<Float>(1 / (abs(dir.x) < 1e-8 ? 1e-8 : dir.x), 1 / (abs(dir.y) < 1e-8 ? 1e-8 : dir.y), 1 / (abs(dir.z) < 1e-8 ? 1e-8 : dir.z))
        for (id, p) in parts {
            // быстрый отсев по рамке
            let t1 = (p.boundsMin - origin) * inv, t2 = (p.boundsMax - origin) * inv
            let tmin = simd_reduce_max(simd_min(t1, t2)), tmax = simd_reduce_min(simd_max(t1, t2))
            if tmax < max(tmin, 0) || tmin > best { continue }
            let v = p.positions, ix = p.indices
            var i = 0
            while i + 2 < ix.count {
                let a = v[Int(ix[i])], b = v[Int(ix[i + 1])], c = v[Int(ix[i + 2])]
                i += 3
                let e1 = b - a, e2 = c - a
                let pv = simd_cross(dir, e2)
                let det = simd_dot(e1, pv)
                if abs(det) < 1e-9 { continue }
                let id_ = 1 / det
                let tv = origin - a
                let u = simd_dot(tv, pv) * id_
                if u < 0 || u > 1 { continue }
                let qv = simd_cross(tv, e1)
                let w = simd_dot(dir, qv) * id_
                if w < 0 || u + w > 1 { continue }
                let t = simd_dot(e2, qv) * id_
                if t > 0, t < best { best = t; bestId = id }
            }
        }
        return bestId
    }

    /// Ближайшее попадание по коже — чтобы касание «сквозь» руку не выбирало мышцу за ней
    static func skinDistance(_ skin: [BodyMeshPart], origin: SIMD3<Float>, dir: SIMD3<Float>) -> Float {
        var best: Float = .greatestFiniteMagnitude
        for p in skin {
            let v = p.positions, ix = p.indices
            var i = 0
            while i + 2 < ix.count {
                let a = v[Int(ix[i])], b = v[Int(ix[i + 1])], c = v[Int(ix[i + 2])]
                i += 3
                let e1 = b - a, e2 = c - a
                let pv = simd_cross(dir, e2)
                let det = simd_dot(e1, pv)
                if abs(det) < 1e-9 { continue }
                let id_ = 1 / det
                let tv = origin - a
                let u = simd_dot(tv, pv) * id_
                if u < 0 || u > 1 { continue }
                let qv = simd_cross(tv, e1)
                let w = simd_dot(dir, qv) * id_
                if w < 0 || u + w > 1 { continue }
                let t = simd_dot(e2, qv) * id_
                if t > 0, t < best { best = t }
            }
        }
        return best
    }
}

enum Body3DPalette {
    static let skin = SIMD4<Float>(0.91, 0.72, 0.60, 1)
    static let selected = SIMD4<Float>(0xB2 / 255.0, 0xEE / 255.0, 0x37 / 255.0, 1)   // фирменный цвет OXION

    static func ui(_ c: SIMD4<Float>) -> UIColor { UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: CGFloat(c.w)) }
    static func simd(_ c: UIColor) -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
    }

    static func material(_ color: SIMD4<Float>, glow: Float = 0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: ui(color))
        m.roughness = .init(floatLiteral: 0.62)
        m.metallic = .init(floatLiteral: 0)
        if glow > 0.001 {
            m.emissiveColor = .init(color: ui(color))
            m.emissiveIntensity = glow
        }
        return m
    }

    static func glowTexture() -> TextureResource? {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).image { ctx in
            let lime = ui(selected)
            let colors = [lime.withAlphaComponent(0.5).cgColor, lime.withAlphaComponent(0.1).cgColor, UIColor.clear.cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1])!
            ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                                             endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [])
        }
        guard let cg = img.cgImage else { return nil }
        return try? TextureResource(image: cg, options: .init(semantic: .color))
    }

    static func floorEntity(size: Float) -> ModelEntity {
        var m = UnlitMaterial(color: .white)
        if let t = glowTexture() { m.color = .init(tint: .white, texture: .init(t)) }
        m.blending = .transparent(opacity: .init(floatLiteral: 1))
        return ModelEntity(mesh: .generatePlane(width: size, depth: size), materials: [m])
    }
}
