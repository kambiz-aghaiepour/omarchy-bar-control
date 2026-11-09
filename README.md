# Bar Control (omarchy)

One bar icon, one panel over the whole bar stack: plugin lifecycle for **Glassy Bar** and **Bar Autohide**, every glassy config key with live preview, the autohide delay, and full bar-entry reordering.

## Install

```sh
omarchy plugin add https://github.com/kambiz-aghaiepour/omarchy-bar-control --enable
omarchy bar put io.github.kambiz.bar-control rightEnd   # or --after <id>
```

Click the gear. Remote: `omarchy-shell io.github.kambiz.bar-control toggle|open|close|refresh|tab <name>|picker <#hex>|isopen`.

## Tabs

**Plugins** — state dot + enable/disable for `glassy.bar` and `ericvrp.bar-autohide`; Install buttons when absent (`omarchy plugin add <upstream> --enable`). Disabling Glassy hands the bar back to stock `omarchy.bar`; enabling it retires the stock bar again.

**Glassy** — every key of `~/.config/glassy.bar/config.json`, written on change (the bar watches the file, so edits apply live):

| Group | Keys |
|---|---|
| Geometry | `position` (cycle theme/top/right/bottom/left), `width` (full / px / %), `margin.edge`+`sides`, `padding`, `radius` (pill ↔ px presets) |
| Colors & transparency | `opacity` (%), `background`, `foreground` (hex or empty = theme), swatch preview |
| Effects | `blur`, `split`, `border.width`+`opacity`, `shadow.depth`+`opacity`+`tint` |

**Autohide** — `hideDelayMs` (0–5000) into the plugin's `shell.json` entry, plus a detached one-button shell restart (required for the delay to apply; the panel closes with the shell and the bar returns ~2 s later).

**Layout** — every bar entry grouped by section with ▲▼ (reorder in section) and ◀▶ (previous/next section), implemented on the stock `omarchy bar move` plumbing, so changes persist to `shell.json` and nudge the live bar. A move rebuilds the bar widgets, so the panel leaves a one-shot reopen note and returns on the same tab. Each row also carries a **color** checkbox: when ticked, a palette row under the plugin sets that widget's text/icon color (`color` key on the layout entry); unticked removes it and the widget returns to the Glassy foreground. This needs the local per-entry tint support in `glassy.bar` (`ModuleSlot.tintColor` + a `MultiEffect` colorization layer over the widget content) — a glassy update that lacks it simply ignores the key.

## Files

```
BarControl.qml            widget: gear button, script runner, IPC
Panel.qml                 tabbed control panel
scripts/barctl-plugins    status / install / enable / disable (bar handoff logic)
scripts/barctl-glassy     get/set every glassy config key (typed, atomic)
scripts/barctl-autohide   hideDelayMs get/set in shell.json
scripts/barctl-layout     layout list; move via omarchy bar move; per-entry color; reopen note
scripts/barctl-restart-shell  detached user-systemd shell restart
tests/smoke.sh            script roundtrips without the shell
```

Env overrides for testing: `OMARCHY_GLASSY_CONFIG`, `OMARCHY_SHELL_JSON`.

## Uninstall

```sh
omarchy plugin remove io.github.kambiz.bar-control
```

Glassy/autohide settings persist (they live in their own plugin configs); rerunning `omarchy plugin enable glassy.bar`-equivalents is untouched by removal. If the bar disappears on uninstall, `omarchy plugin enable omarchy.bar`... is not needed — removal does not touch other plugins' enabled state.

## License

MIT.
