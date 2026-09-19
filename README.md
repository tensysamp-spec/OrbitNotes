# Orbit Notes for macOS

A calm, fast notes app for Mac with the tools you need to actually get things done — a focus timer, reminders with real notifications, and charts that show how much you write and focus.

- ✏️ Notes with search, auto-save and Markdown export (⌘⇧E)
- ⏱ **Focus timer** — Pomodoro-style focus/break cycles with a live progress ring and a chime + notification when time's up (⌘⇧Space to start/pause)
- 🔔 **Reminders** — press the bell on any note; macOS notifies you at the time you pick
- 📈 **Insights** — words written per day, focus minutes, notes created, plus your daily streak
- 🔄 Built-in update check — a banner appears when a new version is on GitHub
- 🌙 Follows light/dark mode; glassy panels with an indigo→cyan accent

## Install

1. Download the latest `OrbitNotes-x.y.z.dmg` from the [Releases](../../releases) page.
2. Open the DMG and drag **Orbit Notes** into **Applications**.
3. First launch: macOS will say the app is from an unidentified developer.
   **Right-click the app → Open → Open.** (Only needed once.)
   If that doesn't work, run in Terminal:
   ```
   xattr -d com.apple.quarantine /Applications/OrbitNotes.app
   ```
4. Allow notifications when asked, so reminders and the timer can alert you.

## Build it yourself

Requires Xcode Command Line Tools (`xcode-select --install`).

```
./scripts/build_dmg.sh 1.0.0
```

The DMG appears in `dist/`. For quick development, `swift run` starts the app — but notifications only work from a real `.app` bundle, so use the build script to test reminders and timer alerts.

## Updates

The app checks this repo's **Releases** page once a day (and on **Orbit Notes → Check for Updates…**). If a newer version exists, a banner offers to download it. Notes are kept across updates — they live in `~/Library/Application Support/OrbitNotes/`.

Before your first release, open `Sources/OrbitNotes/AppConfig.swift` and set `githubRepo` to your repo, e.g. `"artem/OrbitNotes"`. Version numbers come from the git tag (`v1.2.0` → `1.2.0`).

## Releasing on GitHub

```
git tag v1.0.0
git push --tags
```

GitHub Actions builds the DMG and attaches it to a Release automatically.
