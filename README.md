# ShortcutWheel

A macOS menu-bar utility: **hold a trigger** (key, modifier, or mouse side-button)
to open a **radial shortcut menu** at your cursor, **flick** toward a slice, and
**release** to fire it. Slices can send keystrokes, open apps/URLs, run scripts, or
open nested sub-wheels.

- **Platform:** macOS 14+
- **Stack:** native Swift (AppKit + SwiftUI), menu-bar accessory app (no Dock icon)

## Install

Download the latest `ShortcutWheel-x.y.z.dmg` from
[Releases](../../releases), open it, and drag **ShortcutWheel** into **Applications**.

> **First launch — Gatekeeper.** This app is open-source and *not* notarized by
> Apple (that requires a paid Apple Developer account), so macOS will block it the
> first time. Clear the quarantine flag once:
>
> ```sh
> xattr -dr com.apple.quarantine /Applications/ShortcutWheel.app
> ```
>
> Alternatively: double-click it, let it be blocked, then go to **System Settings ▸
> Privacy & Security** and click **Open Anyway**.

Then grant **Accessibility** and **Input Monitoring** (see below). Because the build
is ad-hoc signed, macOS may ask you to re-grant these after installing a new version.

## Build & run

Requires Xcode and [XcodeGen](https://github.com/yonomi/xcodegen) (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -scheme ShortcutWheel -configuration Debug build
open "$(xcodebuild -scheme ShortcutWheel -configuration Debug -showBuildSettings 2>/dev/null \
  | awk '/ BUILT_PRODUCTS_DIR =/{d=$3} / FULL_PRODUCT_NAME =/{n=$3} END{print d"/"n}')"
```

Or open `ShortcutWheel.xcodeproj` in Xcode and run.

## Permissions

ShortcutWheel needs two TCC permissions, granted in
**System Settings ▸ Privacy & Security**:

1. **Accessibility** — to synthesize keystrokes into the focused app.
2. **Input Monitoring** — to observe the global trigger via a `CGEventTap`.

The app prompts on first launch and shows live status in its menu and Settings.

> **Dev note:** the project signs ad-hoc (`CODE_SIGN_IDENTITY = "-"`). TCC keys
> permissions by code signature, so a rebuild can reset granted permissions. For a
> stable dev signature, set `DEVELOPMENT_TEAM` / `CODE_SIGN_STYLE: Automatic` in
> `project.yml`. The App Sandbox is intentionally **off** — event taps and launching
> arbitrary processes are incompatible with sandboxing; distribute via notarized
> direct download rather than the Mac App Store.

## Usage

1. Launch the app and grant the two permissions (it guides you).
2. **Hold the trigger** (default: Right Option ⌥) — the wheel opens at your cursor.
3. **Flick** toward a slice and **release** to fire it.
4. **Dwell** (~0.35s) on a "Tools…" slice to drill into a sub-wheel; dwell in the
   center to go back; release in the center to cancel.
5. Open **Settings** from the menu-bar icon to add/edit wheels and slices, set each
   slice's action (keystrokes, app/URL, script, sub-wheel), and change the trigger.

Config is stored at `~/Library/Application Support/ShortcutWheel/config.json` and
autosaves as you edit.

## Testing

**Automated (unit tests)** — pure logic, no permissions or UI needed:

```sh
xcodegen generate
xcodebuild test -scheme ShortcutWheel -destination 'platform=macOS'
```

Covers wheel geometry (direction→slice, dead zone, seam wraparound, sector angles),
`Color(hex:)` round-trip, the Codable persistence contract (every `Action` case),
trigger bindings, and `ConfigStore` (default-config integrity, save/reload,
corrupt-file backup). Tests live in `Tests/` and use Swift Testing. The app is the
test host but is made inert under test (no event tap / permission prompts).

**Manual (integration)** — for OS-level behavior that can't be unit-tested. After
granting permissions:

1. **Trigger** — hold Right-Option: wheel appears at the cursor; release: it closes.
2. **Selection** — flick toward each slice; the pointed sector highlights; release fires it.
3. **Cancel** — release with the cursor in the center dead-zone: nothing fires.
4. **Actions** — verify a `sendKeys` slice (e.g. ⌘C in a text field), `openURL`,
   `openApp`, and `runScript` each work against a real foreground app.
5. **Sub-wheel** — dwell on "Tools…" to drill in; dwell in center to go back.
6. **Settings** — add/edit/delete wheels & slices, change tint, rebind the trigger
   (the new trigger takes effect immediately); quit & relaunch to confirm persistence.
7. **Edge cases** — multi-monitor (wheel opens on the active screen), over a
   full-screen app, and that the trigger doesn't leak to the focused app.

## Releasing

Releases are built by GitHub Actions (`.github/workflows/release.yml`) — **no Apple
account or signing secrets required**. Push a version tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

CI runs the tests, builds a **universal** (Apple Silicon + Intel) Release app,
**ad-hoc signs** it, packages a `.dmg` (with a checksum), and attaches both to a new
GitHub Release named after the tag.

To build a DMG locally instead:

```sh
./scripts/package-dmg.sh v0.1.0   # → dist/ShortcutWheel-0.1.0.dmg
```

> Ad-hoc signing (`codesign --sign -`) is required so the app runs on Apple Silicon
> at all; it does **not** notarize. See **Install** for the user-side Gatekeeper step.

## Architecture

| Area | Files |
|------|-------|
| App shell (menu-bar accessory, lifecycle) | `App/` |
| TCC permissions (Accessibility + Input Monitoring) | `Permissions/` |
| Global hold detection (`CGEventTap`) | `Input/` |
| Overlay panel + radial wheel + dwell navigation | `Overlay/` |
| Action execution (keys/open/script) | `Actions/` |
| Persisted model + config store | `Model/` |
| Settings / wheel & slice editors | `Settings/` |
