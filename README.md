# CmdDock

**A Spotlight-style launcher for the terminal commands you run every day.** Press a hotkey, pick a command, and CmdDock runs it in your terminal — Warp, Terminal, iTerm2 or Ghostty — in a new tab, a new window or the current one. No more copying commands out of a note.

> 🇪🇸 [Leer en español](README.es.md) · The app UI is currently in Spanish — translations are very welcome.

## Features

- **Global hotkey** (default `⌥⌘K`, configurable) opens a floating panel with search and keyboard navigation.
- **Run in your terminal of choice**: Warp, Terminal, iTerm2 or Ghostty; new tab, new window or current tab. Override per command, and set an optional working directory.
- **Groups as tabs**, drag-and-drop reordering (grab the ⠿ handle), drop a row on a tab to move it to that group.
- **Configurable clicks**: single click copies, double click runs (or edit / nothing).
- **History scan (no AI)**: on first launch CmdDock offers to analyse your Warp, zsh, bash and fish history and propose an initial set of grouped commands. Skippable, fully local.
- **Pin the panel** so it stays open while you work, **import** a list pasted from Notes, launch at login.
- **CLI**: `cmddock scan`, `cmddock scan --apply`, `cmddock --version`.

## Install

### Homebrew (recommended)

```bash
brew tap crisdotcom/tap
brew trust --cask crisdotcom/tap/cmddock   # Homebrew 7+ asks you to trust third-party casks
brew install --cask crisdotcom/tap/cmddock
```

CmdDock opens right after installing and asks whether you want it to scan your history (you can skip it). You can run the scan any time later from **Settings → Analizar historial**, the menu bar icon, or:

```bash
cmddock scan          # preview the proposal, changes nothing
cmddock scan --apply  # add it to CmdDock (asks for confirmation)
```

### From source

Requires macOS 14+ and Xcode 15+ (or the Swift 5.9+ toolchain).

```bash
git clone https://github.com/Crisdotcom/CmdDock.git
cd CmdDock
./build.sh install
```

## Permissions

| Permission | Why |
|---|---|
| **Accessibility** | Warp and Ghostty have no scripting API, so CmdDock opens a tab with `⌘T` and pastes the command. Also used for new tabs in Terminal. |
| **Automation** | To talk to Terminal, iTerm2 and System Events via AppleScript. macOS asks the first time. |

> Builds are ad-hoc signed (not notarized), so macOS may ask you to grant Accessibility again after an update.

## How the history scan works

It is a deterministic, rule-based algorithm ([`HistoryScanner.swift`](Sources/CmdDock/HistoryScanner.swift)) — no network, no AI:

1. Reads commands from Warp's local database (including the folder and exit code of each run) and from `~/.zsh_history`, `~/.bash_history` and fish history.
2. Normalizes them (joins `\` continuations, extracts `cd <dir> && …`).
3. Drops trivial commands (`ls`, `cd`…), destructive ones (`rm`, `delete`, `drop`, `--force`…), one-offs (`git clone`, `brew install x`), commands that almost always fail (typos), and **anything that looks like it contains a secret** (passwords, tokens, credentials in URLs).
4. Counts frequency, and for commands that depend on the current folder (`./script`, `npm`, `make`, `.`) remembers the folder where they're usually run.
5. Groups them by **project** (git root of that folder) when two or more commands share it, otherwise by **tool category** (Git, Docker, Cloud, Node, Python, databases…).

You review the proposal and choose what to add.

## Data

Commands live in `~/Library/Application Support/CmdDock/commands.json`. Settings are stored in the app's user defaults.

## Contributing

Pull requests are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md). Good first contributions: translations, more terminals, more categories for the history scanner.

## License

[MIT](LICENSE)
