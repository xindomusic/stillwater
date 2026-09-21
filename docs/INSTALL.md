# Install Stillwater 1.0

Stillwater is a native freshwater aquarium wallpaper for Apple Silicon Macs running macOS 14 or later. Intel binaries are not included in this release.

## Download and open

1. Download `Stillwater-1.0.4-macOS-arm64.dmg` or `.zip` from https://github.com/xindomusic/stillwater/releases/tag/v1.0.4.
2. For the DMG, open the disk image and drag **Stillwater.app** to **Applications**. For the ZIP, extract it and move the app to Applications.
3. Open Stillwater. Its fish icon appears in the menu bar, and the settings window opens.

This release is ad-hoc signed, without an Apple Developer ID signature or notarization. If macOS blocks it and you choose to trust the download, first attempt to open the app, then choose **System Settings → Privacy & Security → Open Anyway** and confirm. See [Apple’s instructions](https://support.apple.com/guide/mac-help/mh40616/mac). Do not disable Gatekeeper system-wide.

To verify downloaded files, put the archives and `SHA256SUMS.txt` in one folder and run:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

The checksum file covers both archives; checking only one download will report the other as missing. Compare the matching archive’s result.

## Everyday use

- Click the fish menu icon to reopen settings.
- Change scenes and fish populations without restarting.
- Feed with **Control–Option–Command–F** from any app, **Command–F** in Stillwater, or **Feed fish**.
- Enable optional bubbles and particles in **Motion & light**.
- Use **Day & night → Follow Mac** for automatic Light/Dark appearance matching.
- Closing the settings window keeps the wallpaper alive. Quit from the fish menu to stop it.

The wallpaper ignores mouse input so desktop icons remain accessible. The app does not add a login item automatically; add it through macOS Login Items if desired.

## Troubleshooting

**The shortcut does nothing:** confirm Live mode, nonzero swimming speed, and at least one fish. Check that the global shortcut is enabled in Motion & light. Another app may own that key combination; the button and local Command–F remain available. Wait a few seconds between portions.

**The aquarium is still:** choose Live aquarium. Rendering also pauses during display sleep, hidden previews, and critical thermal conditions. Low Power Mode or serious thermal pressure reduces the selected frame rate.

**Night mode stays on:** choose Follow Mac or Day. Follow Mac uses macOS appearance, not a separate sunrise/sunset calculation.

**A saved wallpaper does not animate:** exported PNGs are fixed images. Enable the live desktop aquarium to resume motion.

**Performance:** select Quiet (15 fps), reduce the fish population, and close the large preview. A 60 fps setting is a target, not a guarantee on every display or Mac.

## Update or remove

Quit Stillwater before replacing it with a newer download. Preferences are retained. To uninstall, quit the app and move it to Trash. Previously exported images and any permanent macOS wallpaper remain until you remove or change them yourself.
