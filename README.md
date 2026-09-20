# Mac Duo Private 0.4.9

A native, local-only MacBook lid effect inspired by the iPhone Duo. Built on Makito's Apache-2.0 Mac Duo renderer, with a rewritten gesture controller. This is an independent modified build, not an Apple or official upstream app.

[Step-by-step download and installation](docs/INSTALL.md) · [Push to GitHub and publish downloads](docs/GITHUB.md)

## Install / update

Quit the old version using its menu-bar icon. Open `dist/Mac-Duo-Private.dmg` and drag **Mac Duo Private** into Applications, replacing the previous copy. Launch it. Allow Screen Recording if macOS requests it; frames are processed in memory only. Reopen the app after changing permission if requested by macOS.

The current local build is Apple Development signed, not Apple-notarized. Builds on other machines use an available stable certificate or an explicitly warned ad-hoc fallback. If Gatekeeper blocks a downloaded copy, use System Settings → Privacy & Security → Open Anyway. Do not disable system security protections.

## Automatic behavior

The actual resting lid angle becomes the gesture reference; there is no fixed 90° activation threshold. The renderer traces the moving glass back to the held desktop plane using a fixed assumed viewing position. It crops that plane instead of fitting it into a compressed strip. Exposed sides darken with one symmetric mask for both motion directions. Strong blur increases away from the hinge and around the edges. At extreme magnification, the same mapped image becomes softer; no stationary desktop copy is blended behind it. After roughly 0.85 seconds without significant movement, the picture returns to the glass over 0.32 seconds and adopts the new angle. Movement during the return continues smoothly from the visible plane.

The supplied video was reviewed directly, including paused close-up frames. This is a reference-informed adaptation, not a verified pixel-for-pixel reproduction. The timings and assumed viewing position remain approximations; no camera or head tracking is used. See [reference observations](docs/REFERENCE.md).

The menu offers Animation, Open at login, Preview, About, and Quit. No manual appearance tuning is needed. Old tuning values are removed on upgrade. Credits and license remain under About and in the app bundle.

## Energy and privacy

- One in-memory desktop snapshot per gesture, with at most one retry on failure. No continuous screen stream, audio, uploads, analytics, updater, or saved screenshots.
- Twenty small sensor polls/second while idle and enabled on the built-in display; 60/second only during a gesture. A timer tolerance allows macOS to coalesce wakeups.
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

## Version 0.4.4 restrained motion

Replaced perspective projection with a bounded uniform transform. Opening and closing preserve aspect ratio, never enlarge source pixels, and keep the entire picture inside the panel even at extreme angles. Blur and dimming are gentler. The first rendered frame reads the latest lid position after texture upload rather than revealing an outdated pose. Smoothing reaches 90% of a new sample within 70 ms; this is not an end-to-end latency measurement. Idle polling stays at 20 Hz; active polling is 60 Hz only during a gesture. Capture remains one frame per gesture, and the smaller blur margin reduces temporary image memory.

All 17 tests pass, including 3,721 angle pairs for shape, scale, and bounds, 56 GPU renders, full-resolution resting image fidelity, repeated gestures, and reversals. Hardware sensor and capture latency remain; battery drain and the physical feel are not established by these tests.

## Version 0.4.5 full hinge movement

Restored full-angle hinge rotation instead of the subtle 6% shrink. The reference orientation remains anchored until the existing pause/recovery completes. Orthographic projection avoids opening magnification and perspective singularities; at edge-on it keeps a half-degree sliver instead of flipping the back of the image into view. Straight lines remain straight. Anisotropic texture filtering preserves more detail across the hinge while filtering the compressed direction.

All 18 tests pass, including independent 3D projection checks, the 90° to 15° closing example, reversals, recovery, and 88 GPU renders with image fidelity and symmetry checks. Idle polling, one-frame capture, and the fast smoothing from 0.4.4 remain unchanged. Physical viewing quality and active battery usage still require on-device testing.

## Version 0.4.6 frosted-glass composition

Replaced the rejected orthographic squeeze with direct inverse perspective onto the original plane. The viewing position is held fixed through tracking and recovery. Edge-extended texture padding and a blurred continuation fill the glass instead of exposing a black background. A continuous magnification guard fades detail into frost at grazing angles. Anisotropic filtering, full-resolution capture, fast smoothing, and the latest-pose first frame remain.

All 18 tests pass: independent world-space ray comparisons, signed opening/closing perspective, finite transforms across the sensor range, reversal/recovery, and 88 GPU frames covering symmetry, resting pixel fidelity, and absence of black collapse. This does not establish a precise match for every physical viewing position or measure battery drain. The new composition adds one texture sample per animated pixel but no extra capture, retained image, or idle rendering.

## Version 0.4.7 edge shading and blur quality

Restored dark side wedges during closing, based on the projected image boundary rather than a full-screen vignette. The assumed viewing distance increased from 3.5 to 4 screen heights to reduce perspective exaggeration slightly while preserving held-plane movement. Coarse blur levels use cubic reconstruction and continuous level blending to smooth visible texel cells; low-blur and resting pixels retain the existing full-resolution path. The reconstruction filter's additional softness is compensated slightly to keep the blur strength close to the previous version.

All 19 tests pass, including 88 rendered frames, symmetric closing shadows, bright centers, opening coverage, resting pixel fidelity, and a GPU test for blur slope continuity and correct mip-level selection. More texture reads are used where strong blur needs reconstruction; capture count, image memory, sensor polling, and idle rendering are unchanged. Physical appearance and battery usage still require on-device verification.

## Version 0.4.8 soft outline

Kept the approved 0.4.7 projection, dimensions, and motion unchanged. Added a centred feather around the projected outline, with extra blur localized to that edge band. Edge distance is measured on the glass, so its softness remains consistent under perspective. Closing shadows are applied once after compositing, allowing the image to soften into the dark sides without moving the underlying boundary inward. Edge blur fades with the existing motion/recovery strength and is absent at rest.

All 19 tests pass, including GPU checks for blur outside and inside the original boundary, symmetry, dark closing sides, sharp resting pixels, and smooth blur reconstruction. No additional capture, texture allocation, or idle work was added. The reference was reviewed again at its close-up transition; exact physical appearance still depends on the viewing position.

## Version 0.4.9 single-image composition

Removed the stationary blurred desktop blended behind the held image, which could appear as two competing layers. Magnification protection now blurs the same projected coordinates. A single symmetric side mask applies during opening and closing, and the overlay is opaque. The accepted projection and timing are unchanged. Blur reaches 64 points instead of 32, starts earlier, and has a wider edge band. Zero-duration reveal sets opacity directly without a window animation.

GPU regressions cover opaque output, black exposed sides, asymmetric source colours, repeatable frames after direction changes, resting fidelity, and symmetry at odd/even and Retina dimensions. The change removes the background sampling path and adds no captures, texture allocations, or idle work. Physical lid feel and battery use still require on-device verification.
