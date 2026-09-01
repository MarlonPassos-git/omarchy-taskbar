import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "AppModel.js" as AppModel

// Pinned application launcher for the Omarchy bar.
//
// Each pinned entry is one icon. Clicking launches the app, or focuses it when
// it already has a window, so the strip doubles as a switcher. Windows are
// matched to entries by app id / window class, which is also what drives the
// running indicator under each icon.
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

  // Always render at least one slot so an unconfigured widget still shows an
  // affordance instead of collapsing to zero width.
  readonly property var slots: root.pinned.length > 0 ? root.pinned : [{ key: "__empty__", placeholder: true }]

  readonly property int slotSize: root.iconSize + Style.spaceReal(9)

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

  function desktopEntry(record) {
    var serial = root.entrySerial // binding dependency
    var id = String(record && record.desktopId || "")
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

  function iconSource(name) {
    if (root.appLibrary) return root.appLibrary.iconSource(name)
    var value = String(name || "")
    if (!value) return ""
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

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

  function labelFor(record) {
    if (record && record.label) return record.label
    var entry = root.desktopEntry(record)
    if (entry && entry.name) return String(entry.name)
    return String(record && record.desktopId || "")
  }

  function handlePress(record, button) {
    if (button === Qt.RightButton) {
      root.launch(record)
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

  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

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
    columns: root.vertical ? 1 : root.slots.length
    columnSpacing: root.vertical ? 0 : root.gap
    rowSpacing: root.vertical ? root.gap : 0

    Repeater {
      model: root.slots

      WidgetButton {
        id: slot
        required property var modelData

        readonly property bool placeholder: modelData.placeholder === true
        readonly property var matched: placeholder ? [] : AppModel.windowsFor(modelData, root.windows)
        readonly property bool running: matched.length > 0
        readonly property bool focused: {
          if (!running || root.activeAddress === "") return false
          for (var i = 0; i < matched.length; i++) {
            if (matched[i].address === root.activeAddress) return true
          }
          return false
        }

        readonly property var entry: placeholder ? null : root.desktopEntry(modelData)
        readonly property string iconName: {
          if (placeholder) return ""
          if (modelData.icon) return modelData.icon
          return entry && entry.icon ? String(entry.icon) : String(modelData.desktopId || "")
        }
        readonly property string appLabel: placeholder ? "" : root.labelFor(modelData)

        bar: root.bar
        labelVisible: placeholder
        hasVisualContent: true
        pressable: !placeholder
        text: placeholder ? "\uf009" : ""
        dimmed: placeholder || (root.dimWhenClosed && !running)
        tooltipText: placeholder
          ? "Taskbar: no apps pinned yet — add an \"apps\" list to this widget's shell.json entry"
          : (appLabel + (matched.length > 1 ? " (" + matched.length + " windows)" : ""))
        fixedWidth: root.vertical ? root.barSize : root.slotSize
        fixedHeight: root.vertical ? root.slotSize : root.barSize

        onPressed: function(button) { root.handlePress(slot.modelData, button) }

        Image {
          id: iconImage
          visible: !slot.placeholder && status === Image.Ready
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
          source: slot.placeholder ? "" : root.iconSource(slot.iconName)
        }

        // Icon lookups fail for entries with no themed icon; a letter tile
        // keeps the slot readable instead of leaving a hole in the bar.
        Text {
          visible: !slot.placeholder && iconImage.status !== Image.Ready
          anchors.centerIn: iconImage
          text: slot.appLabel.substring(0, 1).toUpperCase()
          color: slot.focused ? slot.activeColor : slot.foreground
          font.family: slot.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }

        Rectangle {
          id: indicator
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
  }
}
