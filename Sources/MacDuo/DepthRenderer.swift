import AppKit
import Metal
import QuartzCore
import simd

/// Draws the picture with Metal.
///
/// The picture sits on a black margin in one texture, with a centered blur pyramid
/// over it. Each frame is one full screen pass.
@MainActor
final class DepthRenderer {

    /// Black margin around the picture, in points. Stays above the largest
    /// blur radius, so the blur reaches real black on every side.
    nonisolated private static let paddingInPoints: CGFloat = 120

    private struct Uniforms {
        var column0: SIMD4<Float>
        var column1: SIMD4<Float>
        var column2: SIMD4<Float>
        var screenAndOrigin: SIMD4<Float>
        var paddedAndBlur: SIMD4<Float>
        var shape: SIMD4<Float>
        var light: SIMD4<Float>
    }

    /// One held picture, built off the main thread and adopted on it.
    struct PreparedPicture {
        let texture: MTLTexture
        let colourSpace: CGColorSpace
        let paddedOrigin: CGPoint
        let paddedSize: CGSize
        let maxLevel: Float
        let pixelScale: CGFloat
        let screenSize: CGSize
    }

    /// Where the next frame goes.
    ///
    /// A layer belongs to one view at a time, so every overlay window needs
    /// its own.
    private(set) var layer = CAMetalLayer()

    nonisolated private let device: MTLDevice
    nonisolated private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    nonisolated private let blurPipeline: MTLComputePipelineState
    private var texture: MTLTexture?
    private var screenSize: CGSize = .zero
    private var pixelScale: CGFloat = 2
    private var paddedOrigin: CGPoint = .zero
    private var paddedSize: CGSize = .zero
    private var maxLevel: Float = 0

    var isReady: Bool { texture != nil }

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue

        do {
            let library = try device.makeLibrary(source: DepthShaders.source, options: nil)
            guard let blurFunction = library.makeFunction(name: "centeredDownsample") else { return nil }
            blurPipeline = try device.makeComputePipelineState(function: blurFunction)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "depthVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "depthFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            Diagnostics.geometry.error("metal pipeline failed: \(String(describing: error), privacy: .public)")
            return nil
        }

        configure(layer)
    }

    /// A fresh layer for a new overlay window. Later frames go to this one.
    func makeLayer() -> CAMetalLayer {
        let fresh = CAMetalLayer()
        configure(fresh)
        layer = fresh
        return fresh
    }

    private func configure(_ target: CAMetalLayer) {
        target.device = device
        target.pixelFormat = .bgra8Unorm_srgb
        target.framebufferOnly = true
        // An opaque layer covering the screen makes the window server mark
        // every window behind it as hidden, and apps stop drawing. The shader
        // writes alpha 1 everywhere, so blending gives the same picture.
        target.isOpaque = false
        // Waiting for the refresh here blocks the main thread. While a capture
        // stream leaves this app out of its own picture, the window server
        // draws the screen twice, the drawable comes back late, and the wait
        // lands a refresh later: 60 frames per second becomes 32. The display
        // link already paces the drawing.
        target.displaySyncEnabled = false
        target.needsDisplayOnBoundsChange = true
    }

    /// Puts the picture on a black margin, uploads it, and builds the pyramid.
    /// Call this off the main thread.
    nonisolated func makePicture(image: CGImage, screenSize: CGSize, pixelScale: CGFloat) -> PreparedPicture? {
        let started = CFAbsoluteTimeGetCurrent()
        let padding = Self.paddingInPoints
        let paddedSize = CGSize(
            width: screenSize.width + 2 * padding,
            height: screenSize.height + 2 * padding
        )
        let width = Int((paddedSize.width * pixelScale).rounded())
        let height = Int((paddedSize.height * pixelScale).rounded())
        guard width > 0, height > 0 else { return nil }
        let byteCount = width * height * 4

        guard let staging = device.makeBuffer(length: byteCount, options: .storageModeShared) else { return nil }

        let colourSpace: CGColorSpace
        if let space = image.colorSpace, space.model == .rgb {
            colourSpace = space
        } else {
            colourSpace = CGColorSpaceCreateDeviceRGB()
        }
        guard let context = CGContext(
            data: staging.contents(),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colourSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        let contextReady = CFAbsoluteTimeGetCurrent()

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let inset = padding * pixelScale
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(
            x: inset,
            y: inset,
            width: CGFloat(width) - 2 * inset,
            height: CGFloat(height) - 2 * inset
        ))
        let drawn = CFAbsoluteTimeGetCurrent()

        let levels = Int(floor(log2(Double(max(width, height))))) + 1
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: width,
            height: height,
            mipmapped: true
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .pixelFormatView]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor),
              let commands = queue.makeCommandBuffer(),
              let blit = commands.makeBlitCommandEncoder() else { return nil }
        blit.copy(
            from: staging,
            sourceOffset: 0,
            sourceBytesPerRow: width * 4,
            sourceBytesPerImage: byteCount,
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: texture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()

        // Build once per gesture, with no phase drift or odd-size stretching.
        for level in 1..<levels {
            guard let source = texture.makeTextureView(pixelFormat: .bgra8Unorm_srgb, textureType: .type2D,
                                                       levels: (level - 1)..<level, slices: 0..<1),
                  let target = texture.makeTextureView(pixelFormat: .bgra8Unorm, textureType: .type2D,
                                                       levels: level..<(level + 1), slices: 0..<1),
                  let compute = commands.makeComputeCommandEncoder() else { return nil }
            compute.setComputePipelineState(blurPipeline)
            compute.setTexture(source, index: 0)
            compute.setTexture(target, index: 1)
            compute.dispatchThreads(MTLSize(width: target.width, height: target.height, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            compute.endEncoding()
        }
        commands.commit()
        commands.waitUntilCompleted()
        let finished = CFAbsoluteTimeGetCurrent()

        Diagnostics.geometry.notice(
            """
            metal texture \(width)x\(height) px, \(levels) levels: \
            context \((contextReady - started) * 1000, format: .fixed(precision: 1)) ms, \
            draw \((drawn - contextReady) * 1000, format: .fixed(precision: 1)) ms, \
            gpu \((finished - drawn) * 1000, format: .fixed(precision: 1)) ms
            """
        )
        return PreparedPicture(
            texture: texture,
            colourSpace: colourSpace,
            paddedOrigin: CGPoint(x: -padding, y: -padding),
            paddedSize: paddedSize,
            maxLevel: Float(levels - 1),
            pixelScale: pixelScale,
            screenSize: screenSize
        )
    }

    // MARK: - Still source

    func adopt(_ picture: PreparedPicture) {
        texture = picture.texture
        // Without a tag the window server treats the drawable as sRGB and
        // converts it to the display space.
        layer.colorspace = picture.colourSpace
        paddedOrigin = picture.paddedOrigin
        paddedSize = picture.paddedSize
        maxLevel = picture.maxLevel
        pixelScale = picture.pixelScale
        screenSize = picture.screenSize
        layer.drawableSize = CGSize(
            width: picture.screenSize.width * picture.pixelScale,
            height: picture.screenSize.height * picture.pixelScale
        )
    }

    func release() {
        texture = nil
        // Drop our reference to the last drawable once its window closes.
        layer = CAMetalLayer()
        configure(layer)
    }

    /// - Parameter corners: the picture corners projected onto the screen, in
    ///   points, listed bottom-left, bottom-right, top-right, top-left.
    @discardableResult
    func render(
        corners: [CGPoint],
        blurStrength: Double,
        dimStrength: Double,
        hingeFloor: Double,
        dimHingeFloor: Double,
        dimReach: Double,
        maxBlurRadius: Double,
        maxDim: Double,
        offscreenTarget: MTLTexture? = nil
    ) -> MTLCommandBuffer? {
        guard let commands = queue.makeCommandBuffer() else { return nil }
        let drawable = offscreenTarget == nil ? layer.nextDrawable() : nil
        guard let texture, screenSize.width > 0, screenSize.height > 0,
              let target = offscreenTarget ?? drawable?.texture else { return nil }

        let forward = Homography.matrix(
            width: Double(screenSize.width),
            height: Double(screenSize.height),
            to: corners.map { SIMD2(Double($0.x), Double($0.y)) }
        )
        let inverse = forward.inverse

        func column(_ index: Int) -> SIMD4<Float> {
            let c = inverse[index]
            return SIMD4(Float(c.x), Float(c.y), Float(c.z), 0)
        }
        var uniforms = Uniforms(
            column0: column(0),
            column1: column(1),
            column2: column(2),
            screenAndOrigin: SIMD4(
                Float(screenSize.width), Float(screenSize.height),
                Float(paddedOrigin.x), Float(paddedOrigin.y)
            ),
            paddedAndBlur: SIMD4(
                Float(paddedSize.width), Float(paddedSize.height),
                Float(maxBlurRadius * Double(pixelScale)), Float(blurStrength)
            ),
            shape: SIMD4(Float(hingeFloor), Float(maxDim), Float(pixelScale), maxLevel),
            light: SIMD4(Float(dimHingeFloor), Float(dimStrength), Float(dimReach), 0)
        )

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else {
            return nil
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        if let drawable { commands.present(drawable) }
        commands.commit()
        return commands
    }
}
