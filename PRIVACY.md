# Privacy

Mac Duo Private contains no analytics, advertising, accounts, update checker, network client, or third-party dependencies. It sends no data anywhere.

It reads the built-in lid angle and captures one built-in display frame per gesture using Apple's ScreenCaptureKit. A failed capture can be retried once. Screen Recording permission is needed. No audio is captured. Frames stay in RAM/GPU memory and are not saved or uploaded. References are released when the gesture ends, the app disables, the screen sleeps, the session locks, the display arrangement changes, or the app quits. No app diagnostic or lid-history logs are written.

Only local preferences and the welcome-version flag persist. macOS manages permissions, optional launch-at-login registration, system diagnostics, swap, and compositing. This statement does not describe the operating system's own data handling.

External displays are excluded; mirrored arrangements disable the effect. The optional development-only `lidprobe` command prints sensor measurements when manually run; it is not bundled inside the app and does not run automatically.
