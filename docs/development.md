# Development notes

```
manifest.json      plugin declaration and setting schema
BarWidget.qml      the widget the bar mounts
AppModel.js        entry normalization, window matching, list editing
bin/taskbar-pick   shows a list in the Omarchy menu, prints the choice
bin/lint           validates the manifest and lints every QML file
```

Two things worth knowing before changing this code:

**Settings arrays are not `Array`s.** Values from `shell.json` round-trip
through a QML `property var`, which stores JS arrays as `QVariantList`. What
comes back is array-*like* but fails `Array.isArray`, so `AppModel.toArray`
duck-types on `length` instead. Trusting `Array.isArray` silently drops every
pinned app at cold start while still working under hot-reload, which makes it a
nasty one to catch — always test with `omarchy restart shell`, not just a save.

**Pins are persisted in-process,** through the shell's own `mutateShellConfig`.
The tidier `omarchy bar set <id> apps '[…]' --json` cannot be used: it forwards
through `qs ipc call`, which splits every argument on commas, so any array past
one element arrives as extra positional arguments and the call is rejected.

Files under `~/.config/omarchy/plugins/` hot-reload on save. Develop in a real
checkout there or copy the plugin into that directory: the validator rejects
symlinks inside plugin folders. Restart the shell when testing settings-related
changes; hot-reload alone does not exercise cold-start persistence.

## Lint

From the repository root, run before opening a pull request:

```bash
./bin/lint
```

The script runs `omarchy plugin validate` on this plugin, then Qt 6's `qmllint`
on every `.qml` file recursively (excluding `.git`). It does not install or
activate the plugin and does not need a running graphical session.

On Omarchy, install `qt6-declarative` if the Qt 6 lint tool is missing. The
script also needs `omarchy`, `jq`, and Quickshell's QML modules. It prefers
`/usr/lib/qt6/bin/qmllint` over the Qt 5 binary often installed as `qmllint`.
**Keep explicit `: void` IPC return types:** Quickshell requires them; Qt 5's
parser rejecting them is a tooling mismatch, not a plugin syntax error.

`OMARCHY_PATH` defaults to `/usr/share/omarchy`. To use a separate Omarchy
checkout or a different Qt 6 tool location:

```bash
OMARCHY_PATH=/path/to/omarchy \
PATH="/path/to/omarchy/bin:$PATH" \
QMLLINT=/path/to/qt6/bin/qmllint ./bin/lint
```

A temporary import directory maps `qs` to the Omarchy shell so `qs.Ui` and
`qs.Commons` resolve. It is removed on exit and stays outside the plugin.
Missing imports, syntax errors, and warnings fail the command. Two existing
warning categories remain visible as informational messages: `missing-property`
(the host's dynamic `bar` and `Style` properties) and `unqualified` (outer IDs
used by delegates). This means the gate does not catch every property typo or
scope mistake in those categories. For a stricter diagnostic pass, use:

```bash
./bin/lint --missing-property warning --unqualified warning
```

GitHub Actions runs the same command for every pull request, pushes to `master`,
and manual dispatches. An Arch container supplies Qt 6 and Quickshell; a pinned
Omarchy checkout supplies the official validator and shell imports without
installing or starting the desktop. Keep the pinned revision in
`.github/workflows/lint.yml` current when updating supported Omarchy APIs. Arch
packages track the distribution, so dependency updates can expose new warnings.

Static lint does not replace runtime checks: exercise pin/unpin, menu cancel,
window focus/cycling, multiple monitors, shell restart, disable/re-enable, and
removal before a release. Back up pins before lifecycle checks that remove the
widget's settings.

References: [Omarchy development guide](https://plugins.omarchy.org/develop.html),
[Quickshell IPC types](https://quickshell.org/docs/v0.2.0/types/Quickshell.Io/IpcHandler/).
