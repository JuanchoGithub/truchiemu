import Foundation
import Metal
import simd

//////////////////////////////////////////////////////////////////////////
//
// CC0 1.0 Universal (CC0 1.0)
// Public Domain Dedication
//
// The .m3d mesh format and the screen/frame meshes are the work of
// J. Kyle Pittman, published under CC0 1.0 with CRTSim
// (https://github.com/MinorKeyGames/CRTSim).
//
//////////////////////////////////////////////////////////////////////////

// MARK: - Pittman Mesh Loader

/// Parses MinorKeyGames .m3d mesh files (see M3D.cpp in CRTSim) into Metal
/// buffers. Layout: magic + version + counts + 16-bit indices + per-stream
/// (usage enum, stride, payload). Stream usages: 0 position (3f),
/// 1 normal (3f), 4 color (ARGB uint), 5 texcoord0 (2f), 6 texcoord1 (1f).
/// Vertices interleave to pos(3f) + normal(3f) + color RGBA(4f) + uv(2f) +
/// blend(1f); missing blend streams default to 0.
struct PittmanMesh {
    var vertexBuffer: MTLBuffer
    var indexBuffer: MTLBuffer
    var indexCount: Int
    var vertexCount: Int
}

enum M3DMeshLoader {
    // Interleaved vertex floats: 3 + 3 + 4 + 2 + 1.
    static let floatsPerVertex = 13

    static func load(name: String, device: MTLDevice) -> PittmanMesh? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "m3d") else {
            LoggerService.error(category: "Pittman", "M3D mesh not in bundle: \(name).m3d")
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            LoggerService.error(category: "Pittman", "Cannot read mesh: \(name).m3d")
            return nil
        }
        var off = 0
        // NOTE: Data storage is not 4-byte aligned: never load() directly
        // (misaligned-trap). loadUnaligned handles any offset safely.
        func read<T>(_ type: T.Type) -> T? {
            let size = MemoryLayout<T>.size
            guard off + size <= data.count else { return nil }
            defer { off += size }
            return data[off..<(off + size)].withUnsafeBytes { $0.loadUnaligned(as: T.self) }
        }
        guard let magic: UInt32 = read(UInt32.self), magic == 0x64336D2E else {
            LoggerService.error(category: "Pittman", "Bad M3D magic in \(name).m3d")
            return nil
        }
        off += 4 // major, minor, alignment[2]
        guard let numStreams: UInt32 = read(UInt32.self),
              let numVerts: UInt32 = read(UInt32.self),
              let numIndices: UInt32 = read(UInt32.self) else { return nil }
        off += 1 // unused bool
        guard let indexSize: UInt32 = read(UInt32.self), indexSize == 2 else {
            LoggerService.error(category: "Pittman", "Expected 16-bit indices in \(name).m3d")
            return nil
        }
        let nv = Int(numVerts), ni = Int(numIndices), ns = Int(numStreams)
        guard off + ni * 2 <= data.count else { return nil }
        var indices = [UInt16](repeating: 0, count: ni)
        _ = indices.withUnsafeMutableBytes { dst in
            data.copyBytes(to: dst, from: off..<(off + ni * 2))
        }
        off += ni * 2

        var positions = [Float](repeating: 0, count: nv * 3)
        var normals = [Float](repeating: 0, count: nv * 3)
        var colors = [Float](repeating: 1, count: nv * 4)
        var uvs = [Float](repeating: 0, count: nv * 2)
        var blends = [Float](repeating: 0, count: nv)
        for _ in 0..<ns {
            guard let usage: Int32 = read(Int32.self),
                  let stride: UInt32 = read(UInt32.self) else { return nil }
            let bytes = nv * Int(stride)
            guard off + bytes <= data.count else { return nil }
            switch usage {
            case 0: // position
                _ = positions.withUnsafeMutableBytes { dst in
                    data.copyBytes(to: dst, from: off..<(off + bytes))
                }
            case 1: // normal
                _ = normals.withUnsafeMutableBytes { dst in
                    data.copyBytes(to: dst, from: off..<(off + bytes))
                }
            case 4: // color: D3DCOLOR ARGB uint -> RGBA floats
                for i in 0..<nv {
                    let argb: UInt32 = data[off + i * 4..<(off + i * 4 + 4)].withUnsafeBytes {
                        $0.loadUnaligned(as: UInt32.self)
                    }
                    colors[i * 4 + 0] = Float((argb >> 16) & 0xFF) / 255.0
                    colors[i * 4 + 1] = Float((argb >> 8) & 0xFF) / 255.0
                    colors[i * 4 + 2] = Float(argb & 0xFF) / 255.0
                    colors[i * 4 + 3] = Float((argb >> 24) & 0xFF) / 255.0
                }
            case 5: // texcoord0
                _ = uvs.withUnsafeMutableBytes { dst in
                    data.copyBytes(to: dst, from: off..<(off + bytes))
                }
            case 6: // texcoord1.x blend weight
                for i in 0..<nv {
                    let o = off + i * Int(stride)
                    blends[i] = data[o..<(o + 4)].withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
                }
            default:
                break
            }
            off += bytes
        }

        var interleaved = [Float](repeating: 0, count: nv * floatsPerVertex)
        for i in 0..<nv {
            let o = i * floatsPerVertex
            interleaved[o + 0] = positions[i * 3 + 0]
            interleaved[o + 1] = positions[i * 3 + 1]
            interleaved[o + 2] = positions[i * 3 + 2]
            interleaved[o + 3] = normals[i * 3 + 0]
            interleaved[o + 4] = normals[i * 3 + 1]
            interleaved[o + 5] = normals[i * 3 + 2]
            interleaved[o + 6] = colors[i * 4 + 0]
            interleaved[o + 7] = colors[i * 4 + 1]
            interleaved[o + 8] = colors[i * 4 + 2]
            interleaved[o + 9] = colors[i * 4 + 3]
            interleaved[o + 10] = uvs[i * 2 + 0]
            interleaved[o + 11] = uvs[i * 2 + 1]
            interleaved[o + 12] = blends[i]
        }
        guard let vbo = device.makeBuffer(bytes: interleaved,
                                          length: interleaved.count * 4, options: []),
              let ibo = device.makeBuffer(bytes: indices,
                                          length: indices.count * 2, options: []) else {
            return nil
        }
        return PittmanMesh(vertexBuffer: vbo, indexBuffer: ibo,
                           indexCount: ni, vertexCount: nv)
    }
}

// MARK: - D3D Camera Math (column-major simd equivalents)

/// Exact column-major equivalents of the D3DX calls in Main.cpp Render().
/// D3D and Metal both use a 0..1 depth range, so no range fixup applies.
enum PittmanCamera {
    /// D3DXMatrixLookAtRH(eye, at, up) as column-major simd_float4x4.
    static func lookAtRH(eye: SIMD3<Float>, at: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye - at)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)
        return simd_float4x4(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
        ))
    }

    /// Right-handed perspective matching D3DXMatrixPerspectiveFovRH:
    /// visible viewZ in [-zf,-zn] maps to NDC [1,0] with w = -viewZ.
    /// Column-major. Verified by boundary conditions (NDC(-zn) = 0,
    /// NDC(-zf) = 1); the LH form (positive col2.z/w) puts everything
    /// outside the depth range.
    static func perspectiveFovRH(fovY: Float, aspect: Float, zn: Float, zf: Float) -> simd_float4x4 {
        let f = 1.0 / tan(fovY * 0.5)
        let q = zf / (zf - zn)
        return simd_float4x4(columns: (
            SIMD4<Float>(f / aspect, 0, 0, 0),
            SIMD4<Float>(0, f, 0, 0),
            SIMD4<Float>(0, 0, -q, -1),
            SIMD4<Float>(0, 0, -q * zn, 0)
        ))
    }

    /// Main.cpp camera: FOV 15 deg, eye (-dist,0,0), target origin,
    /// up (0,0,1), near 1, far 100. World is identity.
    /// Fit: the cabinet (frame.m3d) spans half-width 1.653 and half-height
    /// 1.32 (measured). The original distance fills only the screen and
    /// crops the cabinet; pull back so the whole cabinet fits with a 3%
    /// margin, never closer than the original distance.
    static func wvp(aspect: Float) -> (wvp: simd_float4x4, camPos: SIMD4<Float>, lightPos: SIMD4<Float>) {
        let tanHalf = tan(7.5 * Float.pi / 180.0)
        let margin: Float = 1.03
        let dist = max(1.0 / tanHalf,
                       1.32 * margin / tanHalf,
                       1.653 * margin / (aspect * tanHalf))
        let eye = SIMD3<Float>(-dist, 0, 0)
        let view = lookAtRH(eye: eye, at: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 0, 1))
        let proj = perspectiveFovRH(fovY: 15.0 * Float.pi / 180.0, aspect: aspect, zn: 1, zf: 100)
        // Tuning_LightPos (-10, -5, 10) from Parameters.cpp.
        return (proj * view, SIMD4<Float>(eye, 0), SIMD4<Float>(-10, -5, 10, 0))
    }
}
