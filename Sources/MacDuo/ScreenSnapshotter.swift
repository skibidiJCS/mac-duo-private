import AppKit
import ScreenCaptureKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
    static var builtIn: NSScreen? {
        screens.first {
            guard let id = $0.displayID else { return false }
            return CGDisplayIsBuiltin(id) != 0 && CGDisplayIsActive(id) != 0 && CGDisplayIsInMirrorSet(id) == 0
        }
    }
}

/// One in-memory frame per gesture. No live capture loop or stored screenshots.
@MainActor
final class ScreenSnapshotter {
    struct Snapshot { let image: CGImage; let screen: NSScreen }
    private var cachedFilter: SCContentFilter?
    private var cachedDisplay: CGDirectDisplayID?
    private var generation = 0
    private var verifiedAccess = false
    private(set) var accessError: String?
    var hasPermission: Bool { verifiedAccess }

    /// Ask the actual capture service, rather than treating a cached preflight
    /// denial as proof that the Settings switch is off. No pixels are captured.
    func checkAccess() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            verifiedAccess = true
            accessError = nil
            return true
        } catch {
            verifiedAccess = false
            let failure = error as NSError
            accessError = "macOS refused access (\(failure.domain), \(failure.code))."
            return false
        }
    }

    func invalidate() {
        generation += 1
        cachedFilter = nil
        cachedDisplay = nil
    }

    /// Prepare display metadata, never a screen image, before a gesture.
    func prepare() async {
        guard hasPermission, !Task.isCancelled,
              let id = NSScreen.builtIn?.displayID else { return }
        _ = await filter(for: id)
    }

    private func filter(for id: CGDirectDisplayID) async -> SCContentFilter? {
        if cachedDisplay == id, let cachedFilter { return cachedFilter }
        let token = generation
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard !Task.isCancelled, token == generation, NSScreen.builtIn?.displayID == id,
                  let display = content.displays.first(where: { $0.displayID == id }) else { return nil }
            let own = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            cachedFilter = filter
            cachedDisplay = id
            return filter
        } catch { return nil }
    }

    func capture() async -> Snapshot? {
        guard hasPermission, !Task.isCancelled,
              let screen = NSScreen.builtIn, let id = screen.displayID else { return nil }
        do {
            guard let filter = await filter(for: id), !Task.isCancelled else { return nil }
            let config = SCStreamConfiguration()
            config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
            config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
            config.showsCursor = false
            config.capturesAudio = false
            config.scalesToFit = false
            config.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard !Task.isCancelled, NSScreen.builtIn?.displayID == id else { return nil }
            return Snapshot(image: image, screen: screen)
        } catch { verifiedAccess = false; invalidate(); return nil }
    }
}
