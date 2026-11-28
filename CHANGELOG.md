# Changelog

## Unreleased

- **Variables in commands**: `{{name}}` and `{{name:default}}`. Running or copying a command with variables opens a form with a live preview; last-used values are remembered per command. Also works from the menu bar.

## 1.0.0 — 2026-11-26

First public release.

- Floating panel opened with a configurable global hotkey.
- Runs commands in Warp, Terminal, iTerm2 or Ghostty (new tab, new window or current tab), with per-command overrides and working directory.
- Groups shown as tabs, drag-and-drop reordering, move to group by dropping on a tab.
- Configurable single/double click actions, pinnable panel, import from pasted text, launch at login.
- First-launch history scan (Warp, zsh, bash, fish) that proposes grouped commands — local and rule-based, no AI. Also available as `cmddock scan`.
