# Taskbar

Pinned app icons for the [Omarchy](https://omarchy.org/) bar.

Click an icon to launch the app — or to focus it, if it's already open. A small
indicator under each icon shows what's running and which app you're in.

Pin and unpin from the bar itself. Apps can optionally own a named workspace,
also configured from the bar.

![The taskbar in the Omarchy bar](docs/bar.png)

## Install

```bash
omarchy plugin add https://github.com/MarlonPassos-git/omarchy-taskbar.git --enable --yes
omarchy bar move io.github.joeyvigil.taskbar --section left
```

Needs Omarchy 4+, with the built-in `omarchy.menu` plugin enabled.

## Using it

| Input | What it does |
|---|---|
| **Left click** | Launch the app, or focus it if it's already running |
| **Left click** (already focused) | Cycle to that app's next window |
| **Middle click** | Always launch a new instance |
| **Right click** | Actions: new instance, dedicated workspace, move left/right, unpin |
| **Click the `+`** | Pin an app, from a searchable list of everything installed |
| **Hover** | App name, plus window count when more than one is open |

<img src="docs/picker.png" alt="Pinning an app from the bar" width="420">

Pinning through the `+` also works out how to recognise that app's windows, so
the running indicator just works — including for Omarchy web apps, which
Chromium reports under names like `chrome-discord.com__channels_@me-Default`.

## Dedicated workspaces

Right-click an app and choose **Use dedicated workspace**. The plugin creates a
named workspace from the app label and sends every newly opened matching window
there, including apps started from a keyboard shortcut, launcher, or terminal.

All instances share that workspace. The newly active window follows its move;
background windows move silently. Existing matching windows are also assigned
when the setting is enabled or the shell starts. Manual moves remain possible.
The named workspace disappears naturally after its last window closes.

## Settings

Stored inline on the widget's entry in `~/.config/omarchy/shell.json`, which
hot-reloads on save. The bar UI writes to this same place.

| Key | Default | Meaning |
|---|---|---|
| `apps` | `[]` | The pinned entries, in bar order |
| `iconSize` | `17` | Icon edge length in pixels |
| `spacing` | `2` | Gap between icons in pixels |
| `runningIndicator` | `true` | Draw the running/focused indicator |
| `dimWhenClosed` | `true` | Fade icons for apps with no open window |
| `cycleWindows` | `true` | Re-clicking a focused app advances to its next window |
| `showAddButton` | `true` | Show the trailing `+` for pinning apps |

> **Disabling the widget discards your pins.** Omarchy stores widget settings
> inline on the bar layout entry, and disabling removes that entry. Copy the
> `apps` array out first if you plan to disable and re-enable.

## Remove

```bash
omarchy plugin remove io.github.joeyvigil.taskbar
```

This takes the pin list with it, for the same reason as above.

## More

- [Advanced configuration](docs/configuration.md) — per-app overrides, custom
  launch commands, the command-line interface, and what to do when an icon
  never lights up.
- [Development notes](docs/development.md) — layout of the code, and two
  non-obvious things about the plugin host worth knowing before changing it.

## License

MIT
