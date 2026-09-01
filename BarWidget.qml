import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "AppModel.js" as AppModel

// Pinned application launcher for the Omarchy bar.
//
// Each pinned entry is one icon. Clicking launches the app, or focuses it when
// it already has a window, so the strip doubles as a switcher. Windows are
// matched to entries by app id / window class, which is also what drives the
// running indicator under each icon.
//
// Pinning is done from the bar itself: the trailing + opens an app picker and
// right-clicking an icon opens its actions. Both borrow the Omarchy menu's
// dmenu mode rather than growing a second picker UI, and both persist through
// `omarchy bar set`, so shell.json stays the single source of truth.
BarWidget {
  id: root
  moduleName: "joeyvigil.taskbar"

  // AppLibrary owns desktop-entry icon resolution (including the on-disk index
  // that catches icons Qt's cache missed). The bar hands us the shell root.
  readonly property var appLibrary: bar && bar.shell ? bar.shell.appLibrary : null

  readonly property var pinned: AppModel.normalizeApps(root.setting("apps", []))
  readonly property int iconSize: Math.max(8, root.setting("iconSize", 17))
  readonly property int gap: Math.max(0, root.setting("spacing", 2))
  readonly property bool runningIndicator: root.setting("runningIndicator", true) === true
  readonly property bool dimWhenClosed: root.setting("dimWhenClosed", true) === true
  readonly property bool cycleWindows: root.setting("cycleWindows", true) === true
  readonly property bool showAddButton: root.setting("showAddButton", true) === true

  // With nothing pinned and the + turned off the widget would be invisible, so
  // keep a trailing slot in that case purely as an affordance.
  readonly property bool showTrailing: root.showAddButton || root.pinned.length === 0

  readonly property int slotSize: root.iconSize + Style.spaceReal(9)

  readonly property string pickerPath: String(Qt.resolvedUrl("bin/taskbar-pick")).replace(/^file:\/\//, "")

  // Hyprland's toplevel objects notify on their own properties, but a list of
  // them does not re-emit when a member's class or title changes. Bumping a
  // serial on every window event gives the descriptor binding something to
  // depend on.
  property int windowSerial: 0
  property int entrySerial: 0

  readonly property string activeAddress: Hyprland.activeToplevel
    ? String(Hyprland.activeToplevel.address || "") : ""

  // Flatten live toplevels into the plain descriptors AppModel matches against.
  function windowDescriptors() {
    var serial = root.windowSerial // binding dependency, see above
    var out = []
    var values = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < values.length; i++) {
      var toplevel = values[i]
      if (!toplevel) continue
      var ipc = toplevel.lastIpcObject || {}
      out.push({
        address: String(toplevel.address || ""),
        appId: toplevel.wayland ? String(toplevel.wayland.appId || "") : "",
        cls: String(ipc["class"] || ""),
        title: String(toplevel.title || ""),
        toplevel: toplevel
      })
    }
    return out
  }

  readonly property var windows: root.windowDescriptors()

  function entryById(desktopId) {
    var serial = root.entrySerial // binding dependency
    var id = String(desktopId || "")
    if (!id) return null
    try {
      var exact = DesktopEntries.byId(id)
      if (exact) return exact
    } catch (e) { }
    try {
      return DesktopEntries.heuristicLookup(id)
    } catch (e) { }
    return null
  }

  function desktopEntry(record) {
    return root.entryById(record ? record.desktopId : "")
  }

  function iconSource(name) {
    if (root.appLibrary) return root.appLibrary.iconSource(name)
    var value = String(name || "")
    if (!value) return ""
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

  function labelFor(record) {
    if (record && record.label) return record.label
    var entry = root.desktopEntry(record)
    if (entry && entry.name) return String(entry.name)
    return String(record && record.desktopId || "")
  }

  // ------------------------------------------------------------- launch/focus

  function focusWindow(descriptor) {
    if (!descriptor) return
    var toplevel = descriptor.toplevel
    // activate() goes through the compositor's own foreign-toplevel handling,
    // which switches workspace for us and needs no dispatcher syntax.
    if (toplevel && toplevel.wayland && typeof toplevel.wayland.activate === "function") {
      toplevel.wayland.activate()
      return
    }
    if (descriptor.address && root.bar) {
      root.bar.run("hyprctl dispatch focuswindow " + root.bar.shellQuote("address:" + descriptor.address))
    }
  }

  function launch(record) {
    if (!record) return
    if (record.exec) {
      if (root.bar) root.bar.run(record.exec)
      return
    }
    if (!record.desktopId) return
    if (root.appLibrary) {
      // Goes through AppLibrary so the launch OSD behaves like the menu's.
      root.appLibrary.launch(record.desktopId, root.labelFor(record))
      return
    }
    if (root.bar) {
      root.bar.run("uwsm-app -- gtk-launch " + root.bar.shellQuote(record.desktopId + ".desktop"))
    }
  }

  function handlePress(record, button) {
    if (button === Qt.MiddleButton) {
      root.launch(record)
      return
    }
    if (button === Qt.RightButton) {
      root.promptActions(record)
      return
    }
    var matched = AppModel.windowsFor(record, root.windows)
    if (matched.length === 0) {
      root.launch(record)
      return
    }
    var index = AppModel.nextWindowIndex(matched, root.activeAddress, root.cycleWindows)
    root.focusWindow(matched[index])
  }

  // ----------------------------------------------------------------- editing

  // Write the whole list back through the shell's own config mutator, which
  // deep-clones, applies, and persists shell.json. The shell then pushes the
  // new settings back down, so there is exactly one direction of data flow.
  //
  // `omarchy bar set --json` would be the tidier public seam, but it cannot
  // carry this value: it forwards through `qs ipc call`, which splits every
  // argument on commas, so any array past one element arrives as extra
  // positional arguments and the call is rejected.
  function persist(records) {
    var payload = AppModel.serialize(records)
    var host = root.bar ? root.bar.shell : null
    if (!host || typeof host.mutateShellConfig !== "function") {
      console.warn("taskbar: no shell config mutator, cannot persist pins")
      return
    }

    host.mutateShellConfig(function(config) {
      var layout = config && config.bar ? config.bar.layout : null
      if (!layout) return
      var sections = ["left", "center", "right"]
      for (var s = 0; s < sections.length; s++) {
        var list = layout[sections[s]]
        if (!Array.isArray(list)) continue
        for (var i = 0; i < list.length; i++) {
          var entry = list[i]
          if (!entry) continue
          if (Util.canonicalWidgetId(String(entry.id || "")) === root.moduleName) {
            entry.apps = payload
            return
          }
        }
      }
      console.warn("taskbar: no layout entry for " + root.moduleName + ", pins not saved")
    })
  }

  // Best-effort window-class match for a newly pinned app, so the running
  // indicator works without the user ever learning what a window class is.
  // Returns "" when the id-derived default already covers the app.
  function smartMatch(desktopId) {
    var entry = root.entryById(desktopId)
    if (!entry) return ""

    var startupClass = String(entry.startupClass || "")
    if (startupClass) {
      if (AppModel.defaultCovers(desktopId, startupClass)) return ""
      return "^" + AppModel.escapeRegex(startupClass) + "$"
    }

    var webapp = AppModel.webappPattern(String(entry.execString || ""))
    if (webapp) {
      // The pattern is a regex, so probe it against the class it describes.
      var probe = webapp.replace(/\\/g, "")
      if (AppModel.defaultCovers(desktopId, probe)) return ""
      return webapp
    }
    return ""
  }

  function pinApp(desktopId) {
    var id = String(desktopId || "")
    if (!id) return "no id"
    if (AppModel.hasDesktopId(root.pinned, id)) return "already pinned"

    var record = { desktopId: id }
    var match = root.smartMatch(id)
    if (match) record.match = match

    var records = root.pinned.slice()
    records.push(record)
    root.persist(records)
    return "ok"
  }

  function unpinApp(desktopId) {
    var id = String(desktopId || "")
    var records = root.pinned.slice()
    for (var i = 0; i < records.length; i++) {
      if (records[i].desktopId === id) {
        records.splice(i, 1)
        root.persist(records)
        return "ok"
      }
    }
    return "not pinned"
  }

  // ------------------------------------------------------------------ picker

  function runPicker(kind, context, prompt, options) {
    if (pickerProc.running) return
    pickerProc.kind = kind
    pickerProc.context = context
    var command = Util.shellQuote(root.pickerPath) + " " + Util.shellQuote(prompt)
    for (var i = 0; i < options.length; i++) command += " " + Util.shellQuote(options[i])
    pickerProc.command = ["bash", "-lc", command]
    pickerProc.running = true
  }

  function promptAdd() {
    var rows = []
    if (root.appLibrary) {
      var sorted = root.appLibrary.sortedEntries("")
      for (var i = 0; i < sorted.length; i++) rows.push(sorted[i].entry)
    } else {
      var values = DesktopEntries.applications.values || []
      for (var j = 0; j < values.length; j++) rows.push(values[j])
    }

    var options = []
    for (var k = 0; k < rows.length; k++) {
      var entry = rows[k]
      if (!entry || entry.noDisplay) continue
      var id = String(entry.id || "")
      if (!id || AppModel.hasDesktopId(root.pinned, id)) continue
      options.push("\t" + String(entry.name || id) + "\t" + id)
    }

    if (options.length === 0) return
    root.runPicker("add", "", "Pin app", options)
  }

  function promptActions(record) {
    var index = AppModel.indexOfKey(root.pinned, record.key)
    if (index < 0) return

    var options = ["\tNew instance\tlaunch"]
    if (index > 0) options.push("\t" + (root.vertical ? "Move up" : "Move left") + "\tback")
    if (index < root.pinned.length - 1) options.push("\t" + (root.vertical ? "Move down" : "Move right") + "\tforward")
    options.push("\tUnpin\tunpin")

    root.runPicker("actions", record.key, root.labelFor(record), options)
  }

  // The menu returns "<label>\t<value>"; the value is the field we set.
  function onPicked(kind, context, raw) {
    var text = String(raw || "").trim()
    if (!text) return
    var parts = text.split("\t")
    var value = parts[parts.length - 1]
    if (!value) return

    if (kind === "add") {
      root.pinApp(value)
      return
    }
    if (kind === "actions") root.runAction(context, value)
  }

  function runAction(key, action) {
    var index = AppModel.indexOfKey(root.pinned, key)
    if (index < 0) return
    var records = root.pinned.slice()

    if (action === "launch") {
      root.launch(records[index])
      return
    }
    if (action === "unpin") {
      records.splice(index, 1)
      root.persist(records)
      return
    }
    if (action === "back" || action === "forward") {
      root.persist(AppModel.movedRecords(records, index, action === "back" ? -1 : 1))
    }
  }

  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  Process {
    id: pickerProc
    property string kind: ""
    property string context: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onPicked(pickerProc.kind, pickerProc.context, text)
    }
  }

  IpcHandler {
    target: "joeyvigil.taskbar"

    function pin(desktopId: string): string { return root.pinApp(desktopId) }
    function unpin(desktopId: string): string { return root.unpinApp(desktopId) }
    function list(): string { return JSON.stringify(AppModel.serialize(root.pinned)) }
    function add(): void { root.promptAdd() }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      // openwindow, closewindow, movewindow, windowtitle, activewindow[v2].
      if (String(event.name || "").indexOf("window") !== -1) root.windowSerial++
    }
  }

  Connections {
    target: root.appLibrary
    ignoreUnknownSignals: true
    function onAppsChanged() { root.entrySerial++ }
  }

  GridLayout {
    id: layout
    anchors.fill: parent
    columns: root.vertical ? 1 : Math.max(1, root.pinned.length + (root.showTrailing ? 1 : 0))
    columnSpacing: root.vertical ? 0 : root.gap
    rowSpacing: root.vertical ? root.gap : 0

    Repeater {
      model: root.pinned

      WidgetButton {
        id: slot
        required property var modelData

        readonly property var matched: AppModel.windowsFor(modelData, root.windows)
        readonly property bool running: matched.length > 0
        readonly property bool focused: {
          if (!running || root.activeAddress === "") return false
          for (var i = 0; i < matched.length; i++) {
            if (matched[i].address === root.activeAddress) return true
          }
          return false
        }

        readonly property var entry: root.desktopEntry(modelData)
        readonly property string iconName: {
          if (modelData.icon) return modelData.icon
          return entry && entry.icon ? String(entry.icon) : String(modelData.desktopId || "")
        }
        readonly property string appLabel: root.labelFor(modelData)

        bar: root.bar
        labelVisible: false
        hasVisualContent: true
        dimmed: root.dimWhenClosed && !running
        tooltipText: appLabel + (matched.length > 1 ? " (" + matched.length + " windows)" : "")
        fixedWidth: root.vertical ? root.barSize : root.slotSize
        fixedHeight: root.vertical ? root.slotSize : root.barSize

        onPressed: function(button) { root.handlePress(slot.modelData, button) }

        Image {
          id: iconImage
          visible: status === Image.Ready
          anchors.centerIn: parent
          // Leave room for the indicator so the icon stays optically centered.
          anchors.verticalCenterOffset: root.runningIndicator && !root.vertical ? -1 : 0
          anchors.horizontalCenterOffset: root.runningIndicator && root.vertical ? 1 : 0
          width: root.iconSize
          height: root.iconSize
          sourceSize.width: root.iconSize * 2
          sourceSize.height: root.iconSize * 2
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          source: root.iconSource(slot.iconName)
        }

        // Icon lookups fail for entries with no themed icon; a letter tile
        // keeps the slot readable instead of leaving a hole in the bar.
        Text {
          visible: iconImage.status !== Image.Ready
          anchors.centerIn: iconImage
          text: slot.appLabel.substring(0, 1).toUpperCase()
          color: slot.focused ? slot.activeColor : slot.foreground
          font.family: slot.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }

        Rectangle {
          visible: root.runningIndicator && slot.running
          readonly property int extent: slot.matched.length > 1 ? 10 : 5
          width: root.vertical ? 2 : extent
          height: root.vertical ? extent : 2
          radius: 1
          color: slot.focused ? slot.activeColor : slot.foreground
          x: root.vertical ? 2 : (slot.width - width) / 2
          y: root.vertical ? (slot.height - height) / 2 : slot.height - height - 3

          Behavior on color {
            ColorAnimation { duration: 160 }
          }
        }
      }
    }

    WidgetButton {
      id: trailing
      visible: root.showTrailing
      bar: root.bar
      text: root.showAddButton ? "\uf067" : "\uf009"
      fontSize: Style.font.bodySmall
      hasVisualContent: root.showTrailing
      pressable: root.showAddButton
      // Sits at full strength while there is nothing pinned, so a fresh widget
      // reads as an invitation rather than as decoration.
      dimmed: root.pinned.length > 0 && !tooltipHovered
      tooltipText: root.showAddButton
        ? "Pin an app"
        : "Taskbar: no apps pinned — add an \"apps\" list to this widget's shell.json entry"
      fixedWidth: root.vertical ? root.barSize : root.slotSize
      fixedHeight: root.vertical ? root.slotSize : root.barSize

      onPressed: function(button) { if (root.showAddButton) root.promptAdd() }
    }
  }
}
