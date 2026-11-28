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

### Getting logs

Since boot:
```bash
journalctl --user -b -t io.github.focustimerhq.FocusTimer
```

Real-time:
```bash
journalctl --user -f -t io.github.focustimerhq.FocusTimer
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
coredumpctl list --since=today focus-timer
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

Thank you for your interest in translating Focus Timer!

Focus Timer uses GNU gettext for localization. The [app](https://github.com/focustimerhq/FocusTimer) and the [GNOME Shell extension](https://github.com/focustimerhq/gnome-shell-extension-focus-timer) have separate translations. You can submit translations via GitHub or Weblate.

### GitHub

All original English strings are stored in `po/focus-timer.pot`. Translations are stored in language-specific `.po` files (e.g., `fr.po`, `es.po`). For editing `.po` files you'll need [Translation Editor](https://flathub.org/en/apps/org.gnome.Gtranslator) or [Poedit](https://flathub.org/en/apps/net.poedit.Poedit). To get started, follow the instructions below:

1. [Fork](https://github.com/focustimerhq/FocusTimer/fork) the repository and clone the `main` branch locally:

    ```
    git clone https://github.com/<your-username>/FocusTimer.git
    cd FocusTimer
    ```

2. If your language is not in `po/` directory yet, create a new file:

    ```
    msginit --input=po/focus-timer.pot --locale=LL --output-file=po/LL.po
    ```

    Replace `LL` with your language code (e.g., `de`, `fr`, `es`, `pt_BR`, etc.).

    Open the file and check the header. Make sure the language, [plural forms](https://www.gnu.org/software/gettext/manual/html_node/Plural-forms.html), and charset are correct.

    Add your language code to `po/LINGUAS`.

3. Fill translations using your preferred editor. To get a first draft from an LLM, use this prompt:

    ```markdown
    Fill-in missing translations and update fuzzy translations for the given gettext file. Translations are for a desktop Pomodoro timer app. Use terms consistently:
    - "pause": the timer action
    - "break": taking a break from work
    - "session": all pomodoros and breaks until a long break
    - "cycle": a pomodoro followed by a break
    - "interruption": a distraction
    - "rewind": the timer action

    Translations do not need to be exact, but they must keep the same meaning and sound natural. Keep C-format placeholders (such as `%s` and `%d`) and GTK mnemonics unchanged. Follow the GNOME Human Interface Guidelines (https://developer.gnome.org/hig/guidelines/writing-style.html) for capitalization (sentence case vs. label case). Mark modified entries as `fuzzy`. Output the full updated `.po` file for download, without truncating it.
    ```

    An LLM doesn't know where each text appears in the app, so please check that the translations fit their context.

    Note that we keep `.po` files up to date with the latest `.pot` template. There's no need to update it on your own.

4. Add your name to `translator-credits` as a new line. Your name will be listed in the *About* dialog in the app.

5. Commit and push your changes to your fork.

6. Submit a [Pull Request](https://docs.github.com/en/pull-requests/how-tos/create-pull-requests/creating-a-pull-request).

Thank you for making the app more accessible for everyone!

### Weblate

You can also use [Weblate](https://hosted.weblate.org/projects/focus-timer/focus-timer/). Weblate covers only the app, not the extension. The current translation status:

[![Translation status](https://hosted.weblate.org/widget/focus-timer/focus-timer/multi-blue.svg?sort=percent)](https://hosted.weblate.org/engage/focus-timer/)

## Development

We recommend using [GNOME Builder](https://flathub.org/apps/org.gnome.Builder) with the provided Flatpak manifest.

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
