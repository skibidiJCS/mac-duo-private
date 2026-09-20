import XCTest
import AppKit
import Metal
@testable import MacDuo

final class RenderSymmetryTests: XCTestCase {
    @MainActor func testBlurReconstructionSmoothsMipCellsAndUsesCorrectLevel() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let source = DepthShaders.source + """

        kernel void checkSmooth(texture2d<float> image [[texture(0)]],
                                device float2 *output [[buffer(0)]],
                                uint i [[thread_position_in_grid]]) {
            constexpr sampler linear(filter::linear, mip_filter::nearest, address::clamp_to_edge);
            float2 uv = float2((float(i) + 0.5) / 256.0, 0.5);
            output[i] = float2(cubicLevel(image, uv, 2).r, image.sample(linear, uv, level(2)).r);
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let pipeline = try device.makeComputePipelineState(function: try XCTUnwrap(library.makeFunction(name: "checkSmooth")))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: 32, height: 32, mipmapped: true)
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        for level in 0..<texture.mipmapLevelCount {
            let size = max(32 >> level, 1)
            let values: [Float] = (0..<(size * size)).map { level == 2 ? Float(($0 % size) % 2) : 0.1 }
            values.withUnsafeBytes { bytes in
                texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: level,
                                withBytes: bytes.baseAddress!, bytesPerRow: size * 4)
            }
        }
        let output = try XCTUnwrap(device.makeBuffer(length: 256 * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared))
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(commands.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setBuffer(output, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: 256, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 32, height: 1, depth: 1))
        encoder.endEncoding(); commands.commit(); commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed)
        let pixels = output.contents().assumingMemoryBound(to: SIMD2<Float>.self)
        var cubicJump: Float = 0, linearJump: Float = 0, mean: Float = 0
        for i in 1..<255 {
            let change = pixels[i + 1] - 2 * pixels[i] + pixels[i - 1]
            cubicJump = max(cubicJump, abs(change.x)); linearJump = max(linearJump, abs(change.y))
            mean += pixels[i].x / 254
        }
        XCTAssertEqual(mean, 0.5, accuracy: 0.01, "Must sample the requested blurred level, not the full-resolution base")
        XCTAssertLessThan(cubicJump, linearJump * 0.2, "Blur should not show abrupt slope changes at mip texel boundaries")
    }

    @MainActor func testSymmetricDesktopStaysCenteredThroughBlurAndPerspective() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try XCTUnwrap(DepthRenderer())
        for (width, height, scale) in [(512, 330, 1), (734, 478, 1), (513, 333, 1), (1280, 832, 2)] {
          for grid in [false, true] {
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            if grid {
                context.setFillColor(CGColor(gray: 0.15, alpha: 1))
                for x in stride(from: 20, to: width / 2, by: 40) {
                    context.fill(CGRect(x: x, y: 0, width: 5, height: height))
                    context.fill(CGRect(x: width - x - 5, y: 0, width: 5, height: height))
                }
                for y in stride(from: 20, to: height, by: 40) {
                    context.fill(CGRect(x: 0, y: y, width: width, height: 5))
                }
            }
            let picture = try XCTUnwrap(renderer.makePicture(image: try XCTUnwrap(context.makeImage()), screenSize: CGSize(width: Double(width) / Double(scale), height: Double(height) / Double(scale)), pixelScale: CGFloat(scale)))
            renderer.adopt(picture)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.renderTarget]
            let output = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
            for angle in [170.0, 150, 130, 120, 110, 100, 85, 65, 40, 25, 20] {
                let progress = min(abs(110 - angle) / 65, 1)
                let gradient = BlurGradient()
                let commands = try XCTUnwrap(renderer.render(screenToPicture: DepthGeometry().screenToPicture(startAngle: 110, currentAngle: angle, screenSize: CGSize(width: Double(width) / Double(scale), height: Double(height) / Double(scale))), blurStrength: gradient.blurStrength(progress: progress), dimStrength: gradient.dimStrength(progress: progress), hingeFloor: 0, dimHingeFloor: 0.2, dimReach: 0.65, maxBlurRadius: 64, maxDim: 0.12, offscreenTarget: output))
                commands.waitUntilCompleted()
                XCTAssertEqual(commands.status, .completed)
                var bytes = [UInt8](repeating: 0, count: width * height * 4)
                output.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
                XCTAssertTrue(stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 }, "The live desktop must never show through the overlay")
                if angle == 110 {
                    let original = context.data!.assumingMemoryBound(to: UInt8.self)
                    var identityError = 0
                    for i in stride(from: 0, to: bytes.count, by: 4) {
                        identityError = max(identityError, abs(Int(bytes[i]) - Int(original[i])))
                    }
                    XCTAssertLessThanOrEqual(identityError, 1, "Resting frame must preserve full-resolution pixels")
                }
                if !grid {
                    let center = Int(bytes[((height / 2) * width + width / 2) * 4])
                    XCTAssertGreaterThan(center, 200, "Closing must not darken the entire desktop")
                    if angle < 110 {
                        let side = Int(bytes[((height / 2) * width) * 4])
                        XCTAssertLessThan(side, center - 25, "Closing must darken the exposed sides")
                        if angle == 65 && width >= 512 {
                            // The original boundary remains the midpoint of a
                            // feather, with visible light spilling outside it.
                            let screenHeight = Double(height) / Double(scale)
                            let screenY = screenHeight - (Double(height / 2) + 0.5) / Double(scale)
                            let matrix = DepthGeometry().screenToPicture(startAngle: 110, currentAngle: angle,
                                screenSize: CGSize(width: Double(width) / Double(scale), height: screenHeight))
                            let edgeX = -matrix[1].x * screenY * Double(scale)
                            let outsideX = max(Int(edgeX) - 4 * scale, 0)
                            let insideX = min(Int(edgeX) + 4 * scale, width - 1)
                            let outside = Int(bytes[((height / 2) * width + outsideX) * 4])
                            let inside = Int(bytes[((height / 2) * width + insideX) * 4])
                            XCTAssertGreaterThan(outside, 20, "Edge blur must spill outside the projected image")
                            XCTAssertLessThan(outside, inside, "The feather must fade continuously toward the dark side")
                            XCTAssertLessThan(inside, center - 5, "Blur must also soften the inside of the outline")
                        }
                    }
                }
                var worst = 0
                var sum = 0
                for y in 0..<height {
                    for x in 0..<(width / 2) {
                        let delta = abs(Int(bytes[(y * width + x) * 4]) - Int(bytes[(y * width + width - 1 - x) * 4]))
                        worst = max(worst, delta); sum += delta
                    }
                }
                let mean = Double(sum) / Double(width * height / 2)
                print("SYMMETRY \(width)x\(height) scale=\(scale) grid=\(grid) angle=\(angle) max=\(worst) mean=\(mean)")
                XCTAssertLessThanOrEqual(worst, 3, "\(width)x\(height), angle \(angle)")
                XCTAssertLessThan(mean, 0.25)
                if let folder = ProcessInfo.processInfo.environment["DUO_RENDER_FIXTURES"] {
                    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32))
                    for i in stride(from: 0, to: bytes.count, by: 4) {
                        bitmap.bitmapData![i] = bytes[i+2]; bitmap.bitmapData![i+1] = bytes[i+1]
                        bitmap.bitmapData![i+2] = bytes[i]; bitmap.bitmapData![i+3] = bytes[i+3]
                    }
                    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(width)-\(Int(angle))-\(grid ? "grid" : "plain").png"))
                }
            }
          }
        }
    }
    @MainActor func testOpaqueSidesAndReversalsWithAsymmetricDesktop() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try XCTUnwrap(DepthRenderer())
        let width = 734, height = 478
        let size = CGSize(width: width, height: height)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        renderer.adopt(try XCTUnwrap(renderer.makePicture(image: try XCTUnwrap(context.makeImage()),
            screenSize: size, pixelScale: 1)))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget]
        let output = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        var previous: [Double: [UInt8]] = [:]
        for angle in [65.0, 150, 20, 110, 150, 65, 20, 65, 110] {
            let progress = min(abs(110 - angle) / 65, 1)
            let gradient = BlurGradient()
            let commands = try XCTUnwrap(renderer.render(screenToPicture: DepthGeometry().screenToPicture(
                startAngle: 110, currentAngle: angle, screenSize: size),
                blurStrength: gradient.blurStrength(progress: progress),
                dimStrength: gradient.dimStrength(progress: progress), hingeFloor: 0,
                dimHingeFloor: 0.2, dimReach: 0.65, maxBlurRadius: 64, maxDim: 0.12,
                offscreenTarget: output))
            commands.waitUntilCompleted()
            XCTAssertEqual(commands.status, .completed)
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            output.getBytes(&pixels, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            if let earlier = previous[angle] {
                XCTAssertEqual(pixels, earlier, "Reversals must not accumulate an old image or mask")
            }
            previous[angle] = pixels
            if angle == 65 {
                for x in [0, width - 1] {
                    let index = ((height / 4) * width + x) * 4
                    XCTAssertEqual(Array(pixels[index..<index + 4]), [0, 0, 0, 255],
                        "Exposed sides must be opaque black, with no stationary desktop behind")
                }
            }
            // Different source colours must not change the left/right mask.
            for y in stride(from: 0, to: height, by: 7) {
                for x in 0..<(width / 4) {
                    let left = (y * width + x) * 4
                    let right = (y * width + width - 1 - x) * 4
                    XCTAssertEqual(Int(pixels[left + 2]), Int(pixels[right]), accuracy: 3)
                }
            }
        }
    }

}
