# WindowDirector

A tiny macOS menu bar app that lists every open window, grouped by app — and lets you switch to, close, or quit them without the list going away.

Click the icon in the menu bar and a menu-style panel drops down with all your windows. Unlike a normal menu, it stays open while you work through it, so you can close several windows in a row.

## Features

- **See every window at a glance** — all running apps and their windows, grouped by app, in a panel that looks like a native macOS menu.
- **Switch** — click a window to bring it to the front (minimized windows are restored).
- **Close** — click `×` to close a window, just like its red close button.
- **Quit** — click `⏻` to quit an app. Apps still ask you to save unsaved documents.
- **Stays open** — the list stays up while you switch and close, and refreshes itself every 1.5 seconds.
- **Out of your way** — lives only in the menu bar: no Dock icon, not in `⌘ Tab`.

## Requirements

- macOS 26 (Tahoe) or later — the panel uses the system glass material. Tested on macOS 27.
- Xcode Command Line Tools (for `swiftc`). Install with `xcode-select --install` if you don't have them.

## Install

WindowDirector is currently distributed as source. Building takes a few seconds and needs no Xcode project.

```bash
git clone https://github.com/yahara4274/WindowDirector.git
cd WindowDirector
./build.sh
```

`build.sh` compiles the app, installs it to `/Applications/WindowDirector.app`, and launches it.

- If you have an Apple Development certificate, the app is signed with it, so the Accessibility permission survives rebuilds.
- Otherwise it is ad-hoc signed. In that case you'll need to re-enable the Accessibility permission after each rebuild.

### Grant Accessibility permission

On first launch macOS asks for Accessibility access. Turn on **WindowDirector** in
**System Settings → Privacy & Security → Accessibility**.

If the panel still says permission is needed, remove WindowDirector from the list with `−`, add `/Applications/WindowDirector.app` again with `+`, and relaunch the app.

### Start at login (optional)

**System Settings → General → Login Items → `+`** and choose `WindowDirector.app`.

## Usage

| Action | How |
|---|---|
| Open / close the list | Click the menu bar icon |
| Switch to a window | Click the window's row |
| Bring an app to the front | Click the app's row |
| Close a window | Click `×` on the window's row |
| Quit an app | Click `⏻` on the app's row |
| Dismiss the list | Click anywhere outside it, or press `esc` |
| Quit WindowDirector | Click "Quit WindowDirector" at the bottom of the list |

## Privacy & security

WindowDirector needs the Accessibility permission because that is the only way macOS lets an app read other apps' window titles and press their close buttons. It uses the permission only to list, raise, and close windows.

- **No network access** — nothing leaves your Mac.
- **Nothing is stored** — window titles are never written to disk or logs.
- **No keystrokes are read** — to close the list when you click elsewhere, it only listens for "a mouse button was pressed", not where or what you typed.
- **No third-party code** — built only from Apple frameworks (AppKit, SwiftUI, Accessibility).

The list shows up in screen sharing and screenshots like any other menu, so avoid opening it while sharing if your window titles are private.

## Limitations

- Windows on other Spaces (desktops) may not be listed, depending on the app. This is a limit of the public Accessibility API.
- Windows without a title are shown as "Untitled".

## Uninstall

1. Click "Quit WindowDirector" at the bottom of the list.
2. Delete `/Applications/WindowDirector.app`.
3. Remove it from **Login Items** and **Accessibility** in System Settings if you added it there.

## License

[MIT](LICENSE)
