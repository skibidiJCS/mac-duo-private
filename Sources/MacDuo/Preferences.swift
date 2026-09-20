import Combine
import Foundation

/// Appearance is automatic; only the master switch is persisted here.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "isEnabled") }
    }
    private init() {
        UserDefaults.standard.register(defaults: ["isEnabled": true])
        isEnabled = UserDefaults.standard.bool(forKey: "isEnabled")
        // Old manual tuning must not silently override the automatic preset.
        for key in ["thresholdAngle", "blurSpan", "maxBlurRadius", "maxDim", "viewingDistance", "recession", "blurEvenness", "dimReach", "isLivePicture", "isTimeoutEnabled", "showsAngleInMenuBar"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
