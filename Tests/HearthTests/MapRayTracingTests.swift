import AppKit
import Metal
import SceneKit
import XCTest
@testable import Hearth

final class MapRayTracingTests: XCTestCase {
    func testMalformedGeometryRangesFailClosed() {
        XCTAssertTrue(MapRayTracing.vertexRangeFits(offset: 0, stride: 12, count: 2, componentBytes: 4, dataSize: 24))
        XCTAssertFalse(MapRayTracing.vertexRangeFits(offset: -1, stride: 12, count: 2, componentBytes: 4, dataSize: 24))
        XCTAssertFalse(MapRayTracing.vertexRangeFits(offset: 0, stride: Int.max, count: 3, componentBytes: 4, dataSize: 24))
        XCTAssertFalse(MapRayTracing.vertexRangeFits(offset: Int.max, stride: 12, count: 2, componentBytes: 4, dataSize: 24))
        XCTAssertFalse(MapRayTracing.vertexRangeFits(offset: 0, stride: 12, count: 2, componentBytes: 4, dataSize: 23))
    }

    func testInvalidTilesAndVerticesFailClosed() throws {
        guard MTLCreateSystemDefaultDevice()?.supportsRaytracing == true else { throw XCTSkip("Unsupported GPU") }
        let tracer = try XCTUnwrap(MapRayTracing())
        let vertices: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1)]
        XCTAssertTrue(tracer.render(vertices: vertices, tiles: [.init(center: SIMD3(.nan, 0, 0), span: 2, opacity: 0.5)]).isEmpty)
        XCTAssertTrue(tracer.render(vertices: vertices, tiles: [.init(center: .zero, span: 2, opacity: .infinity)]).isEmpty)
        XCTAssertTrue(tracer.render(vertices: vertices, tiles: [.init(center: .zero, span: -1, opacity: 0.5)]).isEmpty)
        XCTAssertTrue(tracer.render(vertices: [SIMD3(.nan, 0, 0), vertices[1], vertices[2]], tiles: [.init(center: .zero, span: 2, opacity: 0.5)]).isEmpty)
    }

    @MainActor func testVisibleOpaqueMeshAndWorldTransform() async {
        let root = SCNNode()
        let box = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
        box.position.x = 4
        root.addChildNode(box)
        let vertices = MapRayTracing.triangles(in: root)
        XCTAssertGreaterThanOrEqual(vertices.count, 36)
        XCTAssertTrue(vertices.allSatisfy { $0.x >= 3.5 && $0.x <= 4.5 })
        box.castsShadow = false
        XCTAssertTrue(MapRayTracing.triangles(in: root).isEmpty)
        box.castsShadow = true
        root.isHidden = true
        XCTAssertTrue(MapRayTracing.triangles(in: root).isEmpty)
    }

    @MainActor func testTransparentArtworkDoesNotCastRectangle() async {
        let material = SCNMaterial()
        material.transparency = 0.3
        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
        box.materials = [material]
        XCTAssertTrue(MapRayTracing.triangles(in: SCNNode(geometry: box)).isEmpty)
    }

    func testMetalKernelProducesOcclusionAndTransparentEdges() throws {
        guard MTLCreateSystemDefaultDevice()?.supportsRaytracing == true else {
            throw XCTSkip("GPU does not support Metal ray tracing; SceneKit fallback remains available")
        }
        let tracer = try XCTUnwrap(MapRayTracing())
        let vertices: [SIMD3<Float>] = [SIMD3(-0.4, 0.3, -0.4), SIMD3(0.4, 0.3, -0.4), SIMD3(0.4, 0.3, 0.4),
                                      SIMD3(-0.4, 0.3, -0.4), SIMD3(0.4, 0.3, 0.4), SIMD3(-0.4, 0.3, 0.4)]
        let images = tracer.render(vertices: vertices, tiles: [.init(center: .zero, span: 2, opacity: 0.5)])
        let image = try XCTUnwrap(images.first ?? nil)
        let data = try XCTUnwrap(image.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        let n = MapRayTracing.resolution
        XCTAssertGreaterThan(bytes[(n / 2 * n + n / 2) * 4 + 3], 20)
        XCTAssertEqual(bytes[3], 0)
        XCTAssertTrue(tracer.render(vertices: [], tiles: [.init(center: .zero, span: 2, opacity: 0.5)]).isEmpty)
    }
}
