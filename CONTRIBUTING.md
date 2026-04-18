# Contributing to Focus Timer

Thanks for considering contributing! Whether you're fixing bugs, translating, or adding features, your help is incredibly valuable.

## Reporting issues

Found a bug? Please check the [Troubleshooting](#troubleshooting) section first.

When opening an issue on [GitHub](https://github.com/focustimerhq/FocusTimer/issues), include:
- App version
- Desktop environment and version
- Relevant [logs](#getting-logs) or a [stack trace](#getting-a-stack-trace)
- Steps to reproduce the bug

Suggestions and feature requests are always welcome!

## Troubleshooting

### Missing indicator
If you're on GNOME, you'll need the [Focus Timer extension](https://github.com/focustimerhq/gnome-shell-extension-focus-timer). Check its [troubleshooting page](https://github.com/focustimerhq/gnome-shell-extension-focus-timer/blob/main/CONTRIBUTING.md#troubleshooting) if you already have it.

There is no support for the ayatana / [SNI interface](https://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/StatusNotifierItem/) on other desktop environments yet.

### Missing Automation panel
If you installed the app via Flathub, restricted permissions hide this panel. Try another [installation option](README.md#installation) if you need it.

### Getting logs

Since boot:
```bash
journalctl --user -t io.github.focustimerhq.FocusTimer
```

Real-time:
```bash
journalctl --user -t -f io.github.focustimerhq.FocusTimer
```

With debug output. Run in the terminal and reproduce the issue:
```bash
flatpak run io.github.focustimerhq.FocusTimer --quit
flatpak run --env=G_MESSAGES_DEBUG=focus-timer io.github.focustimerhq.FocusTimer
```

### Getting a stack trace

If the app crashes, providing steps to reproduce it is usually enough. However, to share a stack trace, install the debug info:
```bash
flatpak install --user --include-sdk --include-debug io.github.focustimerhq.FocusTimer
```

Find the app PID from recent crashes:
```bash
coredumpctl list focus-timer
```

Run gdb with your `<pid>`:
```bash
flatpak-coredumpctl -m <pid> io.github.focustimerhq.FocusTimer
```

Inside gdb, get the full trace:
```gdb
bt full
```

## Translating

We use Gettext, with `.pot` and `.po` files located in the [`po/` directory](po). Note that the app and the [GNOME Shell extension](https://github.com/focustimerhq/gnome-shell-extension-focus-timer) have separate translations.

**To add or update a language:**
1. Generate or update your language's `.po` file in `po/` (e.g., using `msginit`).
2. Add your language to the [`po/LINGUAS`](po/LINGUAS) file.
3. Submit a Pull Request.

LLM prompt to ease the process:
> Fill-in missing translations and update fuzzy translations for the given file. Translations are for an desktop Pomodoro timer app. Take care to use consistent same translations for words: "break", "pause", "start", "stop", "rewind", "interruption". "pause" refers to the timer action, while "break" refers to taking a break from work, "interruption" refers to a distraction. Translations does not need to be exact, but must convey same meaning - make them sound natural. Mark modified entries as fuzzy. Output the updated .po file for download, do not truncate it.

*Note: We keep `.po` files synced with the `.pot` template automatically, so you don't need to do this manually.*

## Development

We recommend using [GNOME Builder](https://flathub.org/en/apps/org.gnome.Builder) with the provided Flatpak manifest.

When running `Devel` manifest some features will not work, including notifications and background indicator. SQLite database will be separate from user session.

### Running unit tests

Run:
```bash
ninja -C build test
```

or run unit tests through your IDE.

### Useful Resources

* [Vala Documentation](https://docs.vala.dev/tutorials/programming-language/main.html)
* [Vala Bindings](https://valadoc.org/index.htm)
* [Adwaita Documentation](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/index.html)
* [Meson Reference Manual](https://mesonbuild.com/Reference-manual.html)
* [Portals Documentation](https://flatpak.github.io/xdg-desktop-portal/docs/api-reference.html)
