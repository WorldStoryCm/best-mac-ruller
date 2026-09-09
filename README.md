# Ruller

A small native macOS app that keeps alignment guides above your other windows. Draw a line, switch pages, and see immediately whether the content moved. Built with Swift, AppKit, and native SwiftUI controls. Sparkle provides signed in-app updates hosted on GitHub; drawing and measurement work offline.

## Start

Open `dist/Ruller.app`. A floating control panel appears and a ruler icon lives in your menu bar. **Control–Option–P** toggles the controls between shown and hidden. Hiding or closing the panel finishes editing and leaves your guides visible and click-through. Quit from the ruler menu.

To rebuild from source (macOS 13+, Xcode or Swift command-line tools):

```sh
cd /Users/x11/work/ruller
make run
```

`make build` creates an ad-hoc-signed, universal `dist/Ruller.app` for Apple Silicon and Intel Macs running macOS 13 or later. You can also open `Package.swift` in Xcode.

## Share with another Mac

Download the universal ZIP from [the latest release](https://github.com/WorldStoryCm/best-mac-ruller/releases/latest), or run `make share` to build `dist/Ruller-<version>-mac-universal.zip`. It contains only `Ruller.app`, without your saved lines or preferences. Unzip it, drag Ruller.app to Applications, and open it.

This local build is not Apple-notarized and has no Developer ID certificate, so macOS may block its first launch. After trying to open it, a colleague who trusts the copy you sent can use System Settings → Privacy & Security → Open Anyway. See [Apple's instructions](https://support.apple.com/en-gb/102445). Managed Macs may require IT approval. A Developer ID-signed and notarized release is needed for the standard verified-developer installation experience.

## Updates

Starting with **1.2.0**, choose **Check for Updates…** from the menu-bar ruler icon. **Check Automatically** controls periodic checks. Ruller asks before installing an update; the update replaces the app and relaunches it, keeping your saved guides. The palette closes and editing finishes before the update dialog appears.

If you have **1.1.0 or earlier**, quit Ruller and replace it with the latest download once. Keep the app in Applications rather than running it from the downloaded ZIP or a temporary folder. Subsequent releases can update from inside Ruller.

Update metadata and archives use Ed25519 signatures, verified before extraction. The feed is on GitHub Pages and ZIPs are on GitHub Releases; no private server or user account is required. Update checks contact GitHub and include the app version in the user agent. System profiling is disabled; guides and screen contents are never uploaded. Turn off **Check Automatically** to check only on request.

For developers, [RELEASING.md](docs/RELEASING.md) explains `make release VERSION=1.2.1`, signing-key custody, and optional Apple notarization.

## Use

1. Choose **Vertical**, **Horizontal**, or **Line**. Click anywhere on a display to place an axis guide, or drag to draw an angled line. Hold Shift while drawing for 45° increments.
2. Drag a guide to reposition it. Drag either endpoint of an angled line to resize it. Select a guide in the panel to change its color, opacity, thickness, or exact coordinates.
3. Press **Escape** or choose **Click through**. The overlay stops receiving clicks. Browse, scroll, switch tabs, or change apps: your lines remain fixed on the screen.
4. Press **Control–Option–R** whenever you want to edit again.

The eye button hides all lines. Guides and style settings save automatically and return after relaunch. Each display has its own guides. Disconnected displays' guides are retained and reappear when that display returns; a display picker appears when multiple screens are connected. Clear all removes guides from all displays and can be undone.

## Precision

### Measure the distance between lines

**Distances** is on by default. Add two horizontal or two vertical guides: a bracket and label automatically show the gap between them. With more guides, each neighboring pair gets a measurement. Values update immediately when you drag, nudge, edit coordinates, delete, or undo a guide, and remain visible in click-through mode.

Use **Screen pt** or **Device px** to choose the measurement units. For example, a gap of 0.5 pt on a 2× Retina display reads 1 px. Measurements use the difference between guide coordinates, independent of stroke thickness. Coincident guides read 0. Angled segments retain their length labels; gap measurements are for the horizontal and vertical guide tools.

In **Edit lines** mode, drag a distance label sideways for horizontal guides, or up/down for vertical guides, to move that set of measurements. The guides stay fixed. Closely spaced gap labels move apart with connector lines so 1–2 px gaps remain readable. **Distances** and **Labels** can be toggled separately. Distance visibility and placement save automatically; earlier saved guides remain compatible.

- **Screen pt** uses macOS screen points, measured from the upper-left corner of each display, including the menu bar. At 100% browser zoom these usually correspond to CSS pixels. Browser zoom changes that relationship.
- **Device px** uses the display's macOS backing pixels. A 2× Retina screen has two backing pixels per point; under scaled display modes, these may differ from the physical LCD pixel grid.
- Line thickness is always in backing pixels. Axis guides are drawn on the pixel grid with antialiasing disabled. Angled lines are antialiased.
- Arrow keys move the selected guide by one chosen unit. **Shift** moves by 10 units. **Option** moves by one backing pixel, even in point mode. Hold Option while placing/dragging for backing-pixel precision.
- Angled-line labels show length; vertical and horizontal labels show X or Y. Toggle labels off for a clean comparison.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| Control–Option–R | Toggle edit / click-through globally |
| Control–Option–H | Show / hide lines globally |
| Control–Option–P | Show / hide controls globally |
| Escape | Finish editing; allow clicks through |
| V / H / L | Place vertical / horizontal / angled guide while editing |
| Arrow keys | Nudge selected guide |
| Shift + arrows | Nudge 10 units |
| Option + arrows | Nudge one backing pixel |
| Delete | Delete selected guide while editing |
| Command–D | Duplicate selected guide |
| Command–Z / Command–Shift–Z | Undo / redo |

Global shortcuts use Carbon's hotkey registration, so the app does not ask for Accessibility, Input Monitoring, or Screen Recording permissions. If a shortcut is occupied, a notice appears in the panel and the menu remains available. In edit mode the overlay receives clicks across the displays; Escape always restores click-through. System security screens and OS-owned surfaces can appear above the overlay.

## Development and verification

```sh
make test
make build
```

`make test` runs geometry/serialization tests and an AppKit smoke test. Checks include gap ordering, crossed/deleted guides, subpixel distances, separate displays/axes, readable dense labels, backward-compatible saved files, live gap updates, measurement dragging, overlay visibility, click-through, nudging, undo/redo, drawing input, Escape, and save/reload. It needs a logged-in graphical macOS session and uses isolated temporary state, without touching saved guides. Manual acceptance: draw each guide type; drag and nudge; change opacity; press Escape and switch browser tabs; verify the guides and distances stay fixed; test the global shortcut; quit/relaunch to verify saved guides.

Source layout:

- `Sources/RullerCore`: guide geometry, measurement units, serializable state.
- `Sources/Ruller/Overlay.swift`: transparent AppKit windows, crisp drawing, pointer and keyboard input.
- `Sources/Ruller/Palette.swift`: floating native controls.
- `Sources/Ruller/Model.swift`: selection, undo, autosave, displays.
- `Sources/Ruller/App.swift`: app lifecycle, menu bar, global shortcuts, overlay coordination.
- `Sources/Ruller/UpdateController.swift`: Sparkle update menu and lifecycle.
- `scripts/release.sh`: versioned, signed GitHub releases and appcast publication.

After changing the updater, run `make test-updates` after `make build`. It performs a real Sparkle installation into a disposable app, then checks that modified archives and feeds are rejected. It uses a temporary test signing key and a loopback HTTP server; it does not access the production signing key or launch the real Ruller app.

Saved state: `~/Library/Application Support/Ruller/guides.json`. The app starts in click-through mode, even when guides were last edited. No screen contents are captured or transmitted.

Window behavior follows Apple's documentation for [mouse-transparent windows](https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents) and [overlays that join other applications](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications).
