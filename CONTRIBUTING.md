# Contributing to CmdDock

Thanks for helping! Issues and pull requests are welcome in English or Spanish.

## Development

```bash
git clone https://github.com/Crisdotcom/CmdDock.git
cd CmdDock
swift build            # debug build
swift test             # unit tests (history scanner)
./build.sh install     # build the .app, install to /Applications and launch
```

Requirements: macOS 14+, Xcode 15+ (Swift 5.9+). No third-party dependencies.

### Project layout

| File | What it does |
|---|---|
| `Sources/CmdDock/main.swift` | App delegate, floating panel, menu bar item |
| `Sources/CmdDock/PanelView.swift` | Main panel UI: rows, action bar, editor |
| `Sources/CmdDock/GroupTabs.swift` | Group tabs |
| `Sources/CmdDock/Runner.swift` | Sends a command to the selected terminal (AppleScript) |
| `Sources/CmdDock/HistoryScanner.swift` | Rule-based history analysis and grouping |
| `Sources/CmdDock/OnboardingView.swift` | First-launch scan offer and review |
| `Sources/CmdDock/CLI.swift` | `cmddock` command-line interface |
| `Sources/CmdDock/Models.swift` | Data model, settings, persistence |

## Pull requests

1. Fork and create a branch from `main`.
2. Keep PRs focused on one change; describe *what* and *why*.
3. Make sure `swift build` and `swift test` pass (CI runs both).
4. For UI changes, include a screenshot.
5. A maintainer reviews every PR before it is merged into `main`.

### Ideas that are especially welcome

- **Translations** (the UI is in Spanish today).
- **More terminals** (Kitty, WezTerm, Alacritty, Hyper…) in `Runner.swift`.
- **History scanner rules**: new tool categories in `HistoryScanner.categories`, better secret detection (please add a test in `Tests/CmdDockTests`).

### History scanner principles

The scanner must stay **local, deterministic and conservative**: no network, no AI, and when in doubt, *don't* propose a command. Anything that may contain a secret or destroy data must be filtered out — add a test for every new pattern.

## Releases (maintainers)

1. Update `CHANGELOG.md`, then tag: `git tag v1.2.0 && git push origin v1.2.0`.
2. The `Release` workflow builds a universal `.app`, publishes `CmdDock-1.2.0.zip` on GitHub Releases and, if the `HOMEBREW_TAP_TOKEN` secret is set, updates the cask in `Crisdotcom/homebrew-tap`.
