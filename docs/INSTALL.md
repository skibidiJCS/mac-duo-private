# Download and install Mac Duo Private 0.4.6

## Which file to download

Download **Mac-Duo-Private.dmg**. This contains the ready-to-run Mac app.

On GitHub, open **Releases → latest release → Assets → Mac-Duo-Private.dmg**. Do not choose **Code → Download ZIP**, **Source code**, or **Mac-Duo-Private-Source.tar.gz**; those contain source files, not an installed app.

## Install or replace an older version

1. Click the **laptop icon in the menu bar → Quit**. If there is more than one laptop icon from Mac Duo, quit each copy.
2. Open the downloaded **Mac-Duo-Private.dmg** in Finder.
3. Drag **Mac Duo Private.app** onto **Applications** in that window. Choose **Replace** if Finder asks. Wait for copying to finish.
4. Eject the **Mac Duo Private** disk from Finder's sidebar. Do not run the app from that disk.
5. In Finder, press **Shift–Command–A** to open Applications. Open **Mac Duo Private** there.
6. Click its laptop menu-bar icon. Confirm **Version 0.4.6** appears and **Lid animation** is on. There is no normal Dock icon.

## Allow the animation

1. Click **Allow Screen Recording…** in the app, or open **System Settings → Privacy & Security → Screen & System Audio Recording** (called **Screen Recording** on some macOS versions).
2. Enable **Mac Duo Private**. If it is missing, use the **+** button and select **Applications → Mac Duo Private.app**.
3. If macOS offers **Quit & Reopen**, choose it. Otherwise quit the app from its menu and reopen the Applications copy.
4. If an old permission entry stays ineffective after an update, remove that Mac Duo entry using **−**, add the Applications copy again using **+**, enable it, and reopen the app. Do not change permissions for other apps.
5. Open the MacBook lid. Use its built-in screen, with display mirroring off.
6. The menu should say **Ready — move the lid or use Preview**. Click **Preview animation**, then try actual lid movement.

The app processes frames in memory; it does not record files, capture audio, or upload screen contents. macOS can ask for permission again after updates that change signing identity.

## The switch is already enabled but the app disagrees

Version 0.4.3 adds **I've enabled it — check again**. Use that button to query ScreenCaptureKit directly; this does not save or upload a screen image. A successful check enables Preview and starts lid monitoring. An error is shown instead of silently leaving the effect disabled.

The original 0.1–0.4 builds were ad-hoc signed, so every rebuilt executable had a new privacy identity. The installed 0.4.3 repair uses the available stable Apple Development certificate. Switching from the old ad-hoc identity can still require one new consent: quit the app, remove its old entry from Screen Recording, add `/Applications/Mac Duo Private.app`, enable it, then reopen. Do this only if the direct check still reports access denied. Future locally built updates use the same available certificate rather than silently changing to ad-hoc signing.

## If macOS blocks opening

This build is not Apple-notarized. After attempting to open it, go to **System Settings → Privacy & Security**, find the message about Mac Duo Private, and click **Open Anyway** if you trust this build. Then confirm **Open**. Do not disable Gatekeeper or system-wide security settings.

## Quick troubleshooting

| What you see | What to do |
| --- | --- |
| An older version in the menu | Quit it, replace the Applications copy, and reopen that exact copy. |
| “Running from the installer” | Quit, copy to Applications, eject the disk, then open from Applications. |
| “Screen Recording permission needed” | Follow the permission steps above, including reopening. |
| “Animation is off” | Turn on Lid animation. |
| “Open your MacBook…” | Open the lid and disable mirroring. External screens intentionally receive no effect. |
| “Capture failed…” | Recheck the Applications copy's permission, then quit/reopen. |
| “No compatible lid sensor” | This Mac's sensor is unsupported; permission changes will not add one. |
| Preview works, real movement doesn't | Move the lid by several degrees. The 1.5° noise threshold ignores tiny changes. |
| Effect absent while locked/asleep | Expected: macOS owns the lock screen and powered-off panel. |

The app removes avoidable startup work but cannot guarantee zero latency: hardware sensor updates, movement threshold, macOS capture, and display refresh all take time. There is no continuous capture while idle.
