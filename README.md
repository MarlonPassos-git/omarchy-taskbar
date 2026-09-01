# Taskbar

A pinned application launcher for the [Omarchy](https://omarchy.org/) bar.

Each pinned app is one icon in the bar. Click it to launch the app — or to
focus it, when it already has a window open. A small indicator under each icon
shows what's running, and highlights the app you're currently focused on.

Built as a third-party `bar-widget` plugin for `omarchy-shell` (Omarchy 4+).

## Install

```bash
omarchy plugin add https://github.com/<you>/omarchy-taskbar.git --enable --yes
```

Then place it in the bar:

```bash
omarchy bar move joeyvigil.taskbar --section left
```

## Interactions

| Input | What it does |
|---|---|
| Left click | Launch the app, or focus it if it's already running |
| Left click (focused app) | Cycle to that app's next window |
| Right click | Always launch a new instance |
| Hover | App name, plus window count when more than one is open |

## Configuration

Settings are inline on the widget's entry in `~/.config/omarchy/shell.json`,
which hot-reloads on save.

```json
{
  "id": "joeyvigil.taskbar",
  "apps": ["Alacritty", "chromium", "code"],
  "iconSize": 17,
  "spacing": 2,
  "runningIndicator": true,
  "dimWhenClosed": true,
  "cycleWindows": true
}
```

| Key | Default | Meaning |
|---|---|---|
| `apps` | `[]` | The pinned entries, in bar order |
| `iconSize` | `17` | Icon edge length in pixels |
| `spacing` | `2` | Gap between icons in pixels |
| `runningIndicator` | `true` | Draw the running/focused indicator |
| `dimWhenClosed` | `true` | Fade icons for apps with no open window |
| `cycleWindows` | `true` | Re-clicking a focused app advances to its next window |

`allowMultiple` is on, so you can run several taskbar instances with different
app sets — one per bar section, for example.

### Pinned entries

The short form is a desktop entry id, without the `.desktop` suffix:

```json
"apps": ["Alacritty", "org.gnome.Nautilus", "code"]
```

The long form takes overrides:

```json
"apps": [
  "Alacritty",
  { "desktopId": "code", "match": "code|Code", "label": "Editor" },
  { "label": "Scratch VM", "icon": "computer", "exec": "uwsm-app -- virt-manager", "match": "virt-manager" }
]
```

| Field | Meaning |
|---|---|
| `desktopId` | Desktop entry id. Supplies the icon, name, and launch command. |
| `match` | Regex matched (case-insensitively, on word boundaries) against window app id and class. Defaults to the desktop id. |
| `exec` | Launch command override. Takes precedence over `desktopId`. |
| `icon` | Icon name or absolute path override. |
| `label` | Tooltip override. |
| `matchTitle` | Also match the regex against window titles. Off by default — titles produce false positives for browsers. |

### When an icon never lights up

The running indicator depends on `match` finding the app's window. Check what
the compositor actually reports:

```bash
hyprctl clients -j | jq -r '.[] | "\(.class)\t\(.title)"'
```

If the class doesn't contain the desktop id, set `match` explicitly.

## Development

The plugin is a plain directory of QML plus a manifest:

```
manifest.json    plugin declaration and setting schema
BarWidget.qml    the widget the bar mounts
AppModel.js      entry normalization and window matching
```

Files under `~/.config/omarchy/plugins/` hot-reload on save. If you develop
from a checkout elsewhere and symlink it in, `inotify` won't see through the
symlink — reload by hand after each edit:

```bash
omarchy-shell shell rescanPlugins
```

## License

MIT
