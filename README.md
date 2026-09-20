# Mac Duo Private 0.4.3

A native, local-only MacBook lid effect inspired by the iPhone Duo. Built on Makito's Apache-2.0 Mac Duo renderer, with a rewritten gesture controller. This is an independent modified build, not an Apple or official upstream app.

[Step-by-step download and installation](docs/INSTALL.md) · [Push to GitHub and publish downloads](docs/GITHUB.md)

## Install / update

Quit the old version using its menu-bar icon. Open `dist/Mac-Duo-Private.dmg` and drag **Mac Duo Private** into Applications, replacing the previous copy. Launch it. Allow Screen Recording if macOS requests it; frames are processed in memory only. Reopen the app after changing permission if requested by macOS.

The current local build is Apple Development signed, not Apple-notarized. Builds on other machines use an available stable certificate or an explicitly warned ad-hoc fallback. If Gatekeeper blocks a downloaded copy, use System Settings → Privacy & Security → Open Anyway. Do not disable system security protections.

## Automatic behavior

The actual resting lid angle becomes the starting plane; there is no fixed 90° activation threshold. During movement the picture stays on that plane while the glass moves underneath, in either direction. After roughly 0.85 seconds without significant movement, the picture returns to the glass over 0.32 seconds and adopts the new angle. Movement during the return continues smoothly from the visible plane. Further gestures work from the new position, even below 90°.

Those timings are visual approximations of the supplied reference, not verified Apple constants. Perspective assumes an ordinary seated viewing position; no camera or eye tracking is used.

The menu offers Animation, Open at login, Preview, About, and Quit. No manual appearance tuning is needed. Old tuning values are removed on upgrade. Credits and license remain under About and in the app bundle.

## Energy and privacy

- One in-memory desktop snapshot per gesture, with at most one retry on failure. No continuous screen stream, audio, uploads, analytics, updater, or saved screenshots.
- Twenty small sensor polls/second while enabled on the built-in display. A timer tolerance allows macOS to coalesce wakeups.
- No polling while disabled, asleep, locked, lacking capture permission, or without an eligible built-in display.
- No menu-bar refresh timer. GPU rendering runs only while the image changes; the blur pyramid is built once per snapshot. Frames and drawable references are released after the gesture.
- The renderer follows the display refresh rate and caps it at 60 Hz in Low Power Mode.

These choices reduce energy use, but no running app can promise zero battery cost. See `PRIVACY.md`.

## Compatibility and limits

macOS 14+, a compatible MacBook lid sensor, and Screen Recording permission. The supplied build targets Apple Silicon; `./build.sh --universal` also builds Intel code but does not add missing sensors.

Only the built-in display is captured and animated. Clamshell and mirroring modes disable the effect. macOS controls panel sleep and the secure lock screen: the app cannot show the effect while the panel is off or over the secure lock screen. On wake, the first readable position becomes the new reference and subsequent movement triggers it. Very fast motion may finish before capture is ready. Motion below 1.5° is treated as sensor noise; extremely slow sub-threshold movement can settle between samples. The brief effect holds a still image; video underneath resumes visibly after it clears. Protected/HDR content may differ in capture.

## Build

Requires Xcode / Swift 6. No third-party dependencies or network needed.

```sh
swift test
./build.sh
./package.sh
```

Nothing installs or enables login items automatically. `./build.sh --run` explicitly restarts the local preview.

## Attribution

Original: https://github.com/sumimakito/Mac-Duo at `2a9fa18bea0e92293bf59227b539fe3de0e91328`, © 2026 Makito, Apache 2.0. LICENSE and NOTICE are preserved in the app and distributions.

Modified 2026-09-19: automatic reference-plane tracking, repeatable gesture state, pause-and-adapt recovery, single-frame capture, reduced polling, event-based suspension, cancellation tokens, simplified settings, privacy controls, and packaging. Version 0.2 replaces the fixed-angle controller and continuous stream from 0.1.

## Verification of version 0.2

Release build and all 14 automated tests passed. Tests exercise 1,000 rapid reversals, 1,000 complete gesture/rearm cycles, pauses at arbitrary angles, continuation during recovery, noise, slow cumulative movement, reset after interruption, both projection directions, frame-rate-independent smoothing, and actual Metal initialization/frame release. Native menu layout and off/on controls were inspected.

The rebuilt app requires Screen Recording approval again on the development Mac. End-to-end physical lid/capture testing and normal-use battery measurements are therefore pending. The observed permission-disabled idle state is not a measurement of active animation energy use.

## Version 0.3 rendering correction

GPU-rendered white and symmetric-grid fixtures reproduced the left/right dark-edge mismatch. The old Gaussian-pyramid sampling shifted and stretched the image as blur increased. A centered downsampling kernel now preserves the image center at each level, including odd texture dimensions. It is built once per gesture; no continuous capture or additional idle work was added. The blur and dim gradient now follow distance from the physical hinge on the glass, rather than the warped image coordinates.

All 16 tests pass, including 56 actual Metal renders across opening and closing angles, odd/even dimensions, and 1×/2× scale. Uniform fixtures differ by at most 1/255 across mirrored pixels; grid fixtures by at most 3/255. An independent world-space ray-intersection test verifies the perspective geometry. These checks use synthetic images and do not establish an exact match from every human viewing position.

## Version 0.4 startup and installation fixes

The installed v0.3 copy was verified against the matching build. Version 0.4 shows its version, readiness, and capture failures in the menu, warns when running from a mounted installer, and rejects duplicate running copies. Renderer compilation and display-filter metadata are prepared before lid motion; no screenshot is taken during this preparation. Metadata is invalidated on sleep/display changes and capture failure. Polling checks every 50 ms rather than 125 ms, and the extra 40 ms overlay fade is removed. Duplicate wake notifications no longer reset an active gesture. Capture and sensor latency still prevent a guarantee of instantaneous onset.

## Version 0.4.2 permission repair

Permission status is shared between controller and menu. A manual recheck queries ScreenCaptureKit directly instead of allowing Core Graphics preflight alone to block capture. Build signing now selects a stable available certificate (Developer ID preferred, then Apple Development) and fails on ambiguous identities unless SIGN_IDENTITY is set. With no certificate, it explicitly warns before ad-hoc fallback. Signing takes place in temporary storage to avoid FileProvider/Finder metadata corrupting verification in synced project folders. The repaired local app was installed in Applications after backing up the old copy. A stable signature was verified; actual capture access still requires macOS consent.

## Version 0.4.3 projection and image quality

The assumed viewer sits in front of the original screen plane and stays fixed throughout the gesture and recovery. A more distant assumed viewpoint reduces exaggerated enlargement on opening. The projection preserves a rigid plane; apparent enlargement and cropping when opening are physically necessary for that model. Exact alignment from every real viewing position is not possible without head tracking, which this app does not use. Blur radius is now corrected for the local projection scale so opening does not magnify the blur. Full-resolution image upload uses high-quality interpolation.

No capture loop, idle rendering, dependencies, or data collection were added. Automated tests cover interior-point projection against independent 3D ray intersections, opening/closing symmetry, and full-resolution identity frames. Physical viewing quality and active battery use still require testing on the device.
