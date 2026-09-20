import AppKit
import Metal
import QuartzCore
import simd

/// A borderless window above everything, including the menu bar and full
/// screen spaces. It never takes focus and never takes clicks.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Cast a ray through each point on the moving glass onto the held desktop.
/// Direct inverse projection crops the original plane; it never fits that plane
/// into a shrinking rectangle. The assumed eye remains fixed through recovery.
struct DepthGeometry {
    static let viewingDistance = 4.0

    func screenToPicture(startAngle: Double, currentAngle: Double, screenSize: CGSize,
                         viewingAngle: Double? = nil) -> simd_double3x3 {
        let a = startAngle * .pi / 180
        let view = (viewingAngle ?? startAngle) * .pi / 180
        let delta = (startAngle - currentAngle) * .pi / 180
        let height = Double(screenSize.height)
        let reach = height * (Self.viewingDistance * sin(view) + 0.5 * cos(view))
        let rise = height * (-Self.viewingDistance * cos(view) + 0.5 * sin(view))
        let normalDistance = reach * sin(a) - rise * cos(a)
        let along = reach * cos(a) + rise * sin(a)
        let safeDistance = max(normalDistance, height * 0.05)
        let depthSlope = sin(delta) / safeDistance
        return simd_double3x3(columns: (
            SIMD3(1, 0, 0),
            SIMD3(-Double(screenSize.width) * 0.5 * depthSlope,
                  cos(delta) - along * depthSlope, -depthSlope),
            SIMD3(0, 0, 1)
        ))
    }
}

/// The settings that shape one frame.
struct DepthTuning {
    var blurEvenness: Double = 0.4
    var dimReach: Double = 0.7
    var maxBlurRadius: Double = 55
    var maxDim: Double = 0.4
}

private final class MetalHostView: NSView {
    init(layer metalLayer: CALayer, scale: CGFloat) {
        super.init(frame: .zero)
        metalLayer.contentsScale = scale
        self.layer = metalLayer
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layout() {
        super.layout()
        layer?.frame = bounds
    }
}

/// Owns the overlay window for one run of the effect.
@MainActor
final class DepthOverlay {

    private var window: OverlayWindow?
    /// The window of the previous run while it fades out. AppKit keeps it
    /// alive past the fade, so a new run has to take it down itself.
    private var fadingWindow: OverlayWindow?
    /// Built once and kept.
    private var renderer: DepthRenderer?
    private var hasTriedToBuildRenderer = false
    private var buildToken = 0
    private let buildQueue = DispatchQueue(label: "MacDuo.pictureUpload", qos: .userInteractive)

    private var screenSize: CGSize = .zero
    private var startAngle: Double = 90
    private var viewingAngle: Double = 90
    private var geometry = DepthGeometry()
    private var gradient = BlurGradient()
    private var tuning = DepthTuning()
    private var fadeIn: TimeInterval = 0.07
    private var hasRevealed = false

    var isVisible: Bool { window != nil }
    var isPictureReady: Bool { renderer?.isReady ?? false }
    var hostWindow: NSWindow? { window }

    @discardableResult
    func warmUp() -> Bool {
        if !hasTriedToBuildRenderer {
            hasTriedToBuildRenderer = true
            renderer = DepthRenderer()
        }
        return renderer != nil
    }

    func show(
        image: CGImage,
        on screen: NSScreen,
        startAngle: Double,
        currentAngle: Double,
        tuning: DepthTuning,
        fadeIn: TimeInterval,
        latestPose: @escaping () -> (reference: Double, angle: Double)
    ) {
        dismiss(animated: false)
        // The screenshot's screen can be stale once the lid shuts into
        // clamshell mode, so no window goes up at its old frame.
        guard let displayID = screen.displayID, displayID == NSScreen.builtIn?.displayID else { return }
        guard warmUp(), let renderer else { return }
        self.startAngle = startAngle
        self.viewingAngle = startAngle
        self.tuning = tuning
        self.fadeIn = fadeIn
        screenSize = screen.frame.size

        let pixelScale = screen.frame.width > 0
            ? Double(image.width) / Double(screen.frame.width)
            : Double(screen.backingScaleFactor)

        makeWindow(on: screen, pixelScale: pixelScale)
        guard let window else { return }

        buildToken += 1
        let token = buildToken
        let size = screenSize
        buildQueue.async { [weak self, weak renderer] in
            guard let renderer else { return }
            let picture = renderer.makePicture(image: image, screenSize: size, pixelScale: CGFloat(pixelScale))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.buildToken == token, self.window === window,
                          let picture else { return }
                    renderer.adopt(picture)
                    let pose = latestPose()
                    self.update(progress: min(abs(pose.reference - pose.angle) / 65, 1),
                                currentAngle: pose.angle, referenceAngle: pose.reference, tuning: self.tuning)
                    self.reveal()
                }
            }
        }
    }

    private func makeWindow(on screen: NSScreen, pixelScale: Double) {
        guard let renderer else { return }
        let view = MetalHostView(layer: renderer.makeLayer(), scale: CGFloat(pixelScale))
        view.frame = NSRect(origin: .zero, size: screenSize)
        view.autoresizingMask = [.width, .height]

        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.setFrame(screen.frame, display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()
        hasRevealed = false
        self.window = window
    }

    /// Fades the window in once, and only once the picture has something to
    /// draw.
    private func reveal() {
        guard let window, !hasRevealed, renderer?.isReady == true else { return }
        hasRevealed = true
        if fadeIn <= 0 {
            window.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeIn
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    func update(progress: Double, currentAngle: Double, referenceAngle: Double? = nil, tuning: DepthTuning) {
        guard let renderer, renderer.isReady else { return }
        self.tuning = tuning
        renderer.render(
            screenToPicture: geometry.screenToPicture(
                startAngle: referenceAngle ?? startAngle,
                currentAngle: currentAngle,
                screenSize: screenSize, viewingAngle: viewingAngle
            ),
            blurStrength: gradient.blurStrength(progress: progress),
            dimStrength: gradient.dimStrength(progress: progress),
            hingeFloor: tuning.blurEvenness,
            dimHingeFloor: gradient.dimHingeFloor,
            dimReach: tuning.dimReach,
            maxBlurRadius: tuning.maxBlurRadius,
            maxDim: tuning.maxDim
        )
    }

    func dismiss(animated: Bool, duration: TimeInterval = 0.22) {
        closeFadingWindow()
        guard let window else { return }
        self.window = nil
        buildToken += 1
        renderer?.release()

        guard animated else {
            window.orderOut(nil)
            window.close()
            return
        }

        fadingWindow = window
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if let self, self.fadingWindow === window { self.fadingWindow = nil }
                window.orderOut(nil)
                window.close()
            }
        }
    }

    /// Takes down a window that is still fading.
    private func closeFadingWindow() {
        guard let fadingWindow else { return }
        self.fadingWindow = nil
        fadingWindow.orderOut(nil)
        fadingWindow.close()
    }
}
