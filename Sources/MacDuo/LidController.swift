import AppKit
import Combine
import LidAngleKit
import QuartzCore

struct Layout: Equatable {
    var displayID: CGDirectDisplayID?
    var frame: CGRect?
}

@MainActor
final class LidController: ObservableObject {
    @Published private(set) var isSensorAvailable = false
    @Published private(set) var isActive = false
    @Published private(set) var hasBuiltInDisplay = false
    @Published private(set) var hasScreenPermission = false
    @Published private(set) var isCheckingPermission = false
    @Published private(set) var statusMessage = "Checking…"
    private var preparation: Task<Void, Never>?
    let snapshotter = ScreenSnapshotter()
    private let preferences: Preferences
    private let sensor = LidAngleSensor()
    private let overlay = DepthOverlay()
    private var motion = LidMotion()
    private var visualAngle = CriticallyDampedSpring()
    private var subscription: AnyCancellable?
    private var timer: Timer?
    private var pollInterval: TimeInterval = 0
    private var displayLink: CADisplayLink?
    private var lastFrameTime: TimeInterval = 0
    private var lastRendered: (Double, Double)?
    private var captureTask: Task<Void, Never>?
    private var captureGeneration = 0
    private var captureStarted: TimeInterval = 0
    private var failures = 0
    private var suspended = false
    private var locked = false
    private var layout = Layout()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var localObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var previewStarted: TimeInterval?
    private var previewOrigin: Double = 110
    private var hasStarted = false
    private var canCapture = false

    // Twenty inexpensive HID reads/sec bounds polling latency to about 50 ms.
    // Rendering follows display refresh only while the image actually changes.
    private static let idleInterval = 1.0 / 20
    private static let activeInterval = 1.0 / 60
    private let tuning = DepthTuning(blurEvenness: 0,
                                    dimReach: 0.65, maxBlurRadius: 32, maxDim: 0.45)

    init(preferences: Preferences) {
        self.preferences = preferences
        subscription = preferences.$isEnabled.dropFirst().removeDuplicates().sink { [weak self] enabled in
            // @Published emits before the stored value changes.
            DispatchQueue.main.async {
                guard let self, self.hasStarted else { return }
                self.cancelEffect()
                if enabled { self.refreshReadiness(); self.prepareForMotion() }
                else { self.preparation?.cancel(); self.snapshotter.invalidate(); self.stopPolling(); self.statusMessage = "Animation is off" }
            }
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        isSensorAvailable = sensor.isAvailable
        refreshLayout()
        prepareForMotion()
        observeEvents()
        resetBaseline()
        schedulePolling()
        refreshReadiness()
        checkPermission()
    }

    func stop() {
        hasStarted = false
        preparation?.cancel()
        snapshotter.invalidate()
        stopPolling()
        cancelEffect()
        for token in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        for token in localObservers { NotificationCenter.default.removeObserver(token) }
        for token in distributedObservers { DistributedNotificationCenter.default().removeObserver(token) }
        workspaceObservers.removeAll(); localObservers.removeAll(); distributedObservers.removeAll()
    }

    func checkPermission() {
        guard !isCheckingPermission else { return }
        isCheckingPermission = true
        statusMessage = "Checking access with macOS…"
        Task { [weak self] in
            guard let self else { return }
            let allowed = await self.snapshotter.checkAccess()
            self.isCheckingPermission = false
            if allowed { self.refreshReadiness() }
            else {
                self.canCapture = false
                self.hasScreenPermission = false
                self.cancelEffect(); self.stopPolling()
                self.statusMessage = self.snapshotter.accessError ?? "macOS denied capture access."
            }
        }
    }

    func refreshReadiness() {
        canCapture = snapshotter.hasPermission
        hasScreenPermission = canCapture
        if !preferences.isEnabled { statusMessage = "Animation is off" }
        else if !isSensorAvailable { statusMessage = "No compatible lid sensor" }
        else if isCheckingPermission { statusMessage = "Checking access with macOS…" }
        else if !canCapture { statusMessage = snapshotter.accessError ?? "Screen Recording permission needed" }
        else if !hasBuiltInDisplay { statusMessage = "Open your MacBook; turn off display mirroring" }
        else if locked || suspended { statusMessage = "Waiting for the desktop to wake" }
        else { statusMessage = "Ready — move the lid or use Preview" }
        if !canCapture { cancelEffect(); stopPolling(); return }
        if timer == nil { resetBaseline(); schedulePolling(); prepareForMotion() }
    }

    private func prepareForMotion() {
        guard canCapture, hasBuiltInDisplay, preferences.isEnabled, !locked, !suspended else { return }
        guard overlay.warmUp() else { statusMessage = "Graphics initialization failed. Relaunch the app."; return }
        preparation?.cancel()
        preparation = Task { [weak self] in await self?.snapshotter.prepare() }
    }

    private func resetBaseline() {
        let angle = sensor.angle() ?? 90
        motion.reset(angle: angle, at: CACurrentMediaTime())
        visualAngle.reset(to: angle)
        failures = 0
    }

    private func refreshLayout() {
        let screen = NSScreen.builtIn
        layout = Layout(displayID: screen?.displayID, frame: screen?.frame)
        hasBuiltInDisplay = layout.displayID != nil
        canCapture = snapshotter.hasPermission
        hasScreenPermission = canCapture
    }

    private func stopPolling() {
        timer?.invalidate(); timer = nil; pollInterval = 0
    }

    private func schedulePolling() {
        guard hasStarted, preferences.isEnabled, isSensorAvailable,
              !suspended, !locked, hasBuiltInDisplay, canCapture else { stopPolling(); return }
        let interval = motion.phase == .idle && previewStarted == nil ? Self.idleInterval : Self.activeInterval
        guard interval != pollInterval else { return }
        stopPolling()
        pollInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func runPreview() {
        guard preferences.isEnabled, hasBuiltInDisplay, !suspended, !locked,
              snapshotter.hasPermission else { return }
        cancelEffect()
        previewOrigin = sensor.angle() ?? 110
        motion.reset(angle: previewOrigin, at: CACurrentMediaTime())
        visualAngle.reset(to: previewOrigin)
        previewStarted = CACurrentMediaTime()
        schedulePolling()
    }

    private func poll() {
        let now = CACurrentMediaTime()
        let angle: Double
        if let start = previewStarted {
            let elapsed = now - start
            let travel = min(45, max(previewOrigin - 8, 0))
            if elapsed < 1 { angle = previewOrigin - travel * elapsed }
            else if elapsed < 2.4 { angle = previewOrigin - travel }
            else if elapsed < 3.4 { angle = previewOrigin - travel + travel * (elapsed - 2.4) }
            else if elapsed < 4.8 { angle = previewOrigin }
            else { cancelEffect(); resetBaseline(); schedulePolling(); return }
        } else if let value = sensor.angle() {
            angle = value; failures = 0
        } else {
            failures += 1
            if failures >= 4 { cancelEffect(); resetBaseline(); schedulePolling() }
            return
        }
        let started = motion.sample(angle, at: now)
        if started { beginGesture(at: now) }
        if motion.phase == .idle {
            if isActive || captureTask != nil {
                let preview = previewStarted
                cancelEffect()
                previewStarted = preview
            }
        } else if captureTask != nil, now - captureStarted > 1.5 {
            // An unresponsive capture service must never leave a stuck overlay.
            cancelEffect(); motion.reset(angle: angle, at: now)
        } else if overlay.isVisible {
            let needsFrame = !overlay.isPictureReady || motion.phase == .settling
                || lastRendered == nil || abs((lastRendered?.0 ?? angle) - angle) > 0.005
            if needsFrame { startDisplayLink() }
        }
        schedulePolling()
    }

    private func beginGesture(at now: TimeInterval) {
        guard snapshotter.hasPermission else { return }
        cancelCapture()
        guard overlay.warmUp() else { return }
        visualAngle.reset(to: motion.anchor)
        captureStarted = now
        let generation = captureGeneration
        captureTask = Task { [weak self] in
            guard let self else { return }
            // At most one retry, only after an actual capture failure.
            var snapshot = await self.snapshotter.capture()
            if snapshot == nil, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 150_000_000)
                snapshot = await self.snapshotter.capture()
            }
            guard !Task.isCancelled, generation == self.captureGeneration else { return }
            self.captureTask = nil
            if snapshot == nil { self.statusMessage = "Capture failed. Check Screen Recording, then relaunch." }
            guard let snapshot, self.motion.phase != .idle, !self.suspended, !self.locked,
                  self.preferences.isEnabled, snapshot.screen.displayID == self.layout.displayID else { return }
            self.visualAngle.reset(to: self.motion.angle)
            self.overlay.show(image: snapshot.image, on: snapshot.screen,
                              startAngle: self.motion.reference(at: CACurrentMediaTime()),
                              currentAngle: self.motion.angle, tuning: self.tuning, fadeIn: 0,
                              latestPose: { [weak self] in
                                  guard let self else { return (90, 90) }
                                  self.visualAngle.reset(to: self.motion.angle)
                                  return (self.motion.reference(at: CACurrentMediaTime()), self.motion.angle)
                              })
            self.statusMessage = "Ready — move the lid or use Preview"
            self.isActive = self.overlay.isVisible
            self.startDisplayLink()
        }
    }

    private func cancelCapture() {
        captureGeneration += 1
        captureTask?.cancel(); captureTask = nil
    }

    private func cancelEffect() {
        cancelCapture()
        stopDisplayLink()
        overlay.dismiss(animated: false)
        isActive = false
        lastRendered = nil
        previewStarted = nil
    }

    private func startDisplayLink() {
        guard displayLink == nil, let window = overlay.hostWindow else { return }
        let link = window.displayLink(target: self, selector: #selector(step(_:)))
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastFrameTime = CACurrentMediaTime()
    }

    private func stopDisplayLink() {
        displayLink?.invalidate(); displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        guard overlay.isPictureReady else { return }
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastFrameTime, 1.0 / 240), 0.1)
        lastFrameTime = now
        visualAngle.advance(to: motion.angle, dt: dt)
        let reference = motion.reference(at: now)
        let angle = visualAngle.value
        if let lastRendered, abs(lastRendered.0 - angle) < 0.005,
           abs(lastRendered.1 - reference) < 0.005, motion.phase != .settling {
            stopDisplayLink()
            return
        }
        overlay.update(progress: min(abs(reference - angle) / 65, 1), currentAngle: angle,
                       referenceAngle: reference, tuning: tuning)
        lastRendered = (angle, reference)
    }

    private func suspend() {
        suspended = true
        preparation?.cancel()
        snapshotter.invalidate()
        stopPolling(); cancelEffect()
        statusMessage = "Waiting for the desktop to wake"
    }

    private func resume() {
        guard !locked else { return }
        guard suspended else { refreshReadiness(); return }
        suspended = false
        cancelEffect(); refreshLayout(); resetBaseline(); schedulePolling(); prepareForMotion(); refreshReadiness()
    }

    private func observeEvents() {
        localObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.hasScreenPermission { self.checkPermission() }
                else { self.refreshReadiness() }
            }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspend() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            })
        }
        let distributed = DistributedNotificationCenter.default()
        for (name, isLocked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributedObservers.append(distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.locked = isLocked
                    if isLocked { self.suspend() } else { self.resume() }
                }
            })
        }
        localObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let old = self.layout
                self.refreshLayout()
                guard old != self.layout else { return }
                self.preparation?.cancel(); self.snapshotter.invalidate()
                self.cancelEffect(); self.resetBaseline(); self.schedulePolling(); self.prepareForMotion(); self.refreshReadiness()
            }
        })
    }
}
