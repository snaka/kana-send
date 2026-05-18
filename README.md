# kana-send

A minimal macOS menu-bar app that turns the left/right ⌘ keys into stateless
英数 / かな input-mode switches on a US keyboard, with a hold threshold so
quick ⌘-then-letter rolls don't fire shortcuts by accident.

## How it works

- **Tap left ⌘** (release within the hold threshold) → sends 英数
- **Tap right ⌘** → sends かな
- **Hold ⌘ past the threshold** → ⌘ becomes a real modifier, ⌘+key shortcuts
  work as usual
- **Press ⌘ then another key before the threshold** → only the other key
  fires; ⌘ is suppressed

A small indicator appears near the mouse cursor showing which path the app
took: `A`, `あ`, or `⌘`.

## Requirements

- macOS 14 (Sonoma) or later
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (only for generating the
  Xcode project): `brew install xcodegen`

## Build

```sh
xcodegen generate
open kana-send.xcodeproj
```

Then in Xcode: select the `kana-send` scheme and **Product → Run**.

On first launch macOS will refuse to register the event tap until you grant
Accessibility permission. The app will pop up a prompt with a button that
takes you to **System Settings → Privacy & Security → Accessibility**. Enable
`kana-send` there and re-launch.

## Configuration

Click the menu bar icon (`あ`) to:

- Toggle the app on/off
- Toggle the cursor-side indicator
- Choose the hold threshold (200 / 300 / 500 / 700 / 1000 ms)

Defaults are stored in `UserDefaults` under `com.snaka.kana-send`.

## Building a redistributable DMG

```sh
./scripts/make-dmg.sh
```

Produces `dist/kana-send-<version>.dmg`. The app is ad-hoc signed (universal
binary, x86_64 + arm64), not notarized — so on a fresh Mac you have to
bypass Gatekeeper manually.

### Cutting a GitHub release

A GitHub Actions workflow (`.github/workflows/release.yml`) builds the DMG
and attaches it to a Release whenever a `v*` tag is pushed:

```sh
# Bump CFBundleShortVersionString in project.yml first, then:
git tag v0.1.0
git push origin v0.1.0
```

The workflow refuses to run if the tag and `project.yml` version disagree.
You can also trigger it manually from the Actions tab (the DMG is uploaded
as a workflow artifact in that case, no Release is created).

### Installing the DMG on another Mac

1. Open the DMG and drag `kana-send.app` into `Applications`.
2. The first time you launch it, macOS will say *"kana-send cannot be opened
   because Apple cannot check it for malicious software."* Cancel that
   dialog, then either:
   - Right-click `kana-send.app` → **Open** → confirm in the next dialog, or
   - System Settings → Privacy & Security → click **Open Anyway** under the
     refused-launch notice, or
   - Run `xattr -d com.apple.quarantine /Applications/kana-send.app` once.
3. Grant Accessibility permission when prompted, then **restart the app**.

## License

MIT
