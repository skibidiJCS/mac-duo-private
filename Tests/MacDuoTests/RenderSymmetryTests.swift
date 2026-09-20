import XCTest
import AppKit
import Metal
@testable import MacDuo

final class RenderSymmetryTests: XCTestCase {
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
            for angle in [130.0, 120, 110, 100, 85, 65, 40] {
                let progress = min(abs(110 - angle) / 65, 1)
                let gradient = BlurGradient()
                let commands = try XCTUnwrap(renderer.render(corners: DepthGeometry().corners(startAngle: 110, currentAngle: angle, screenSize: CGSize(width: Double(width) / Double(scale), height: Double(height) / Double(scale))), blurStrength: gradient.blurStrength(progress: progress), dimStrength: gradient.dimStrength(progress: progress), hingeFloor: 0, dimHingeFloor: 0.2, dimReach: 0.65, maxBlurRadius: 32, maxDim: 0.45, offscreenTarget: output))
                commands.waitUntilCompleted()
                XCTAssertEqual(commands.status, .completed)
                var bytes = [UInt8](repeating: 0, count: width * height * 4)
                output.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
                if angle == 110 {
                    let original = context.data!.assumingMemoryBound(to: UInt8.self)
                    var identityError = 0
                    for i in stride(from: 0, to: bytes.count, by: 4) {
                        identityError = max(identityError, abs(Int(bytes[i]) - Int(original[i])))
                    }
                    XCTAssertLessThanOrEqual(identityError, 1, "Resting frame must preserve full-resolution pixels")
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
}
