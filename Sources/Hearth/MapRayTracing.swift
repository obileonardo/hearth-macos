import AppKit
import Metal
import SceneKit
import simd

/// A small Metal ray-tracing pass augments SceneKit's existing lighting with
/// geometry-correct contact shadows. It never replaces the interactive renderer.
/// Unsupported GPUs, oversized meshes and failed commands keep the native shadows.
final class MapRayTracing: @unchecked Sendable {
    struct Tile: Sendable {
        var center: SIMD3<Float>
        var span: Float
        var opacity: Float
    }
    private let device: MTLDevice
    private let commands: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let worker = DispatchQueue(label: "Hearth.map.contact-light", qos: .utility)
    private let requestLock = NSLock()
    private var requestGeneration: UInt64 = 0
    static let resolution = 128
    static let maximumTriangles = 120_000
    static let maximumTiles = 64

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsRaytracing,
              let commands = device.makeCommandQueue() else { return nil }
        do {
            let options = MTLCompileOptions()
            options.languageVersion = .version2_4
            let library = try device.makeLibrary(source: Self.shader, options: options)
            guard let kernel = library.makeFunction(name: "contactShadows") else { return nil }
            pipeline = try device.makeComputePipelineState(function: kernel)
        } catch { return nil }
        self.device = device
        self.commands = commands
    }

    func request(vertices: [SIMD3<Float>], tiles: [Tile],
                 completion: @escaping @MainActor ([CGImage?]) -> Void) {
        requestLock.lock()
        requestGeneration &+= 1
        let generation = requestGeneration
        requestLock.unlock()
        worker.async { [self] in
            requestLock.lock()
            let current = generation == requestGeneration
            requestLock.unlock()
            guard current else { return } // Rapid drags must not queue obsolete GPU work.
            let images = render(vertices: vertices, tiles: tiles)
            requestLock.lock()
            let stillCurrent = generation == requestGeneration
            requestLock.unlock()
            guard stillCurrent else { return }
            DispatchQueue.main.async { completion(images) }
        }
    }

    /// Also used by isolated regression checks and offline preview exports.
    func render(vertices: [SIMD3<Float>], tiles: [Tile]) -> [CGImage?] {
        guard !tiles.isEmpty, tiles.count <= Self.maximumTiles,
              tiles.allSatisfy({ $0.center.x.isFinite && $0.center.y.isFinite && $0.center.z.isFinite
                  && $0.span.isFinite && $0.span > 0 && $0.opacity.isFinite && (0...1).contains($0.opacity) }),
              vertices.count >= 3, vertices.count % 3 == 0,
              vertices.count / 3 <= Self.maximumTriangles,
              vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { return [] }
        let stride = MemoryLayout<SIMD3<Float>>.stride
        guard let vertexBuffer = vertices.withUnsafeBytes({ bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }) else { return [] }
        let geometry = MTLAccelerationStructureTriangleGeometryDescriptor()
        geometry.vertexBuffer = vertexBuffer
        geometry.vertexStride = stride
        geometry.vertexFormat = .float3
        geometry.triangleCount = vertices.count / 3
        geometry.opaque = true
        let descriptor = MTLPrimitiveAccelerationStructureDescriptor()
        descriptor.geometryDescriptors = [geometry]
        let sizes = device.accelerationStructureSizes(descriptor: descriptor)
        guard sizes.accelerationStructureSize > 0,
              let acceleration = device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
              let scratch = device.makeBuffer(length: max(1, sizes.buildScratchBufferSize), options: .storageModePrivate),
              let command = commands.makeCommandBuffer(),
              let builder = command.makeAccelerationStructureCommandEncoder() else { return [] }
        builder.build(accelerationStructure: acceleration, descriptor: descriptor,
                      scratchBuffer: scratch, scratchBufferOffset: 0)
        builder.endEncoding()
        var outputs: [MTLBuffer] = []
        for tile in tiles {
            guard tile.span.isFinite, tile.span > 0,
                  let output = device.makeBuffer(length: Self.resolution * Self.resolution * 4, options: .storageModeShared),
                  let encoder = command.makeComputeCommandEncoder() else { return [] }
            var bounds = SIMD4<Float>(tile.center.x, tile.center.y, tile.center.z, tile.span)
            var settings = SIMD4<Float>(tile.opacity, Float(Self.resolution), 0, 0)
            encoder.setComputePipelineState(pipeline)
            encoder.setAccelerationStructure(acceleration, bufferIndex: 0)
            encoder.setBuffer(output, offset: 0, index: 1)
            encoder.setBytes(&bounds, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
            encoder.setBytes(&settings, length: MemoryLayout<SIMD4<Float>>.stride, index: 3)
            encoder.dispatchThreads(MTLSize(width: Self.resolution, height: Self.resolution, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            encoder.endEncoding()
            outputs.append(output)
        }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return [] }
        return outputs.map { buffer in
            let data = Data(bytes: buffer.contents(), count: buffer.length)
            guard let provider = CGDataProvider(data: data as CFData) else { return nil }
            return CGImage(width: Self.resolution, height: Self.resolution, bitsPerComponent: 8,
                           bitsPerPixel: 32, bytesPerRow: Self.resolution * 4,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
    }

    /// Extract only visible, opaque triangle geometry that casts a shadow.
    /// Labels, alpha illustrations, glass and glow planes cannot become rectangular occluders.
    @MainActor
    static func triangles(in root: SCNNode) -> [SIMD3<Float>] {
        var vertices: [SIMD3<Float>] = []
        var exceeded = false
        func visit(_ node: SCNNode, opacity: CGFloat) {
            guard !node.isHidden, !exceeded else { return }
            let opacity = opacity * node.opacity
            guard opacity >= 0.75 else { return }
            if node.castsShadow, let geometry = node.geometry,
               let source = geometry.sources(for: .vertex).first,
               source.usesFloatComponents, source.componentsPerVector >= 3,
               source.vectorCount <= maximumTriangles * 3,
               [4, 8].contains(source.bytesPerComponent) {
                let componentBytes = source.bytesPerComponent
                if Self.vertexRangeFits(offset: source.dataOffset, stride: source.dataStride, count: source.vectorCount,
                                        componentBytes: componentBytes, dataSize: source.data.count) {
                    let points: [SIMD3<Float>] = source.data.withUnsafeBytes { bytes in
                        (0..<source.vectorCount).map { index in
                            let offset = source.dataOffset + index * source.dataStride
                            func value(_ c: Int) -> Float {
                                source.bytesPerComponent == 4
                                    ? bytes.loadUnaligned(fromByteOffset: offset + c * componentBytes, as: Float.self)
                                    : Float(bytes.loadUnaligned(fromByteOffset: offset + c * componentBytes, as: Double.self))
                            }
                            let p = node.simdWorldTransform * SIMD4(value(0), value(1), value(2), 1)
                            return SIMD3(p.x, p.y, p.z)
                        }
                    }
                    for (elementIndex, element) in geometry.elements.enumerated() {
                        guard [.triangles, .triangleStrip].contains(element.primitiveType),
                              element.primitiveCount >= 0, element.primitiveCount <= maximumTriangles,
                              [1, 2, 4].contains(element.bytesPerIndex) else { continue }
                        if !geometry.materials.isEmpty {
                            let material = geometry.materials[elementIndex % geometry.materials.count]
                            let alpha = (material.diffuse.contents as? NSColor)?.alphaComponent ?? 1
                            guard material.transparency >= 0.75, alpha >= 0.75 else { continue }
                        }
                        let count = element.primitiveType == .triangles ? element.primitiveCount * 3 : element.primitiveCount + 2
                        guard count * element.bytesPerIndex <= element.data.count else { continue }
                        let indices: [Int] = element.data.withUnsafeBytes { bytes in
                            (0..<count).map { index in
                                let offset = index * element.bytesPerIndex
                                switch element.bytesPerIndex {
                                case 1: return Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt8.self))
                                case 2: return Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                                default: return Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                                }
                            }
                        }
                        for triangle in 0..<element.primitiveCount {
                            let start = element.primitiveType == .triangles ? triangle * 3 : triangle
                            let ids = Array(indices[start..<(start + 3)])
                            guard ids.allSatisfy({ points.indices.contains($0) }), Set(ids).count == 3 else { continue }
                            vertices.append(contentsOf: ids.map { points[$0] })
                            if vertices.count / 3 > maximumTriangles { exceeded = true; return }
                        }
                    }
                }
            }
            for child in node.childNodes { visit(child, opacity: opacity) }
        }
        visit(root, opacity: 1)
        return exceeded ? [] : vertices
    }

    static func vertexRangeFits(offset: Int, stride: Int, count: Int, componentBytes: Int, dataSize: Int) -> Bool {
        guard offset >= 0, count > 0, dataSize >= 0, [4, 8].contains(componentBytes),
              stride >= 3 * componentBytes else { return false }
        let (last, multiplyOverflow) = (count - 1).multipliedReportingOverflow(by: stride)
        let (start, offsetOverflow) = offset.addingReportingOverflow(last)
        let (end, endOverflow) = start.addingReportingOverflow(3 * componentBytes)
        return !multiplyOverflow && !offsetOverflow && !endOverflow && end <= dataSize
    }

    private static let shader = """
    #include <metal_stdlib>
    #include <metal_raytracing>
    using namespace metal;
    using namespace raytracing;
    kernel void contactShadows(primitive_acceleration_structure scene [[buffer(0)]],
                               device uchar4 *pixels [[buffer(1)]],
                               constant float4 &bounds [[buffer(2)]],
                               constant float4 &settings [[buffer(3)]],
                               uint2 pixel [[thread_position_in_grid]]) {
        uint resolution = uint(settings.y);
        if (pixel.x >= resolution || pixel.y >= resolution) return;
        float2 uv = (float2(pixel) + 0.5) / float(resolution);
        float3 origin = bounds.xyz + float3((uv.x - 0.5) * bounds.w, 0.012, (uv.y - 0.5) * bounds.w);
        intersector<triangle_data> query;
        query.assume_geometry_type(geometry_type::triangle);
        query.accept_any_intersection(false);
        float blocked = 0;
        // Short hemisphere rays create a soft, grounded contact shadow, rather
        // than doubling SceneKit's long directional-light shadow.
        const float3 directions[8] = {
            float3(0.25, 1, 0), float3(-0.25, 1, 0), float3(0, 1, 0.25), float3(0, 1, -0.25),
            float3(0.45, 0.8, 0.45), float3(-0.45, 0.8, 0.45),
            float3(0.45, 0.8, -0.45), float3(-0.45, 0.8, -0.45)
        };
        for (uint sample = 0; sample < 8; ++sample) {
            ray r;
            r.origin = origin;
            r.direction = normalize(directions[sample]);
            r.min_distance = 0.004;
            r.max_distance = 0.9;
            auto hit = query.intersect(r, scene);
            if (hit.type != intersection_type::none) blocked += 1.0 - smoothstep(0.12, 0.9, hit.distance);
        }
        float edge = 1.0 - smoothstep(0.40, 0.50, max(abs(uv.x - 0.5), abs(uv.y - 0.5)));
        uchar alpha = uchar(clamp(blocked / 8.0 * settings.x * edge, 0.0, 1.0) * 255.0);
        pixels[pixel.y * resolution + pixel.x] = uchar4(0, 0, 0, alpha);
    }
    """
}
