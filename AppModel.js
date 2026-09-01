.pragma library

// Pure helpers for the taskbar widget: turning shell.json entries into pinned
// app records, and deciding which open windows belong to which record.
//
// Deliberately free of QML globals so it can stay a `.pragma library` shared
// across every bar instance. The widget hands in plain window descriptors
// ({ address, appId, cls, title }) rather than live Hyprland objects.

// Settings arriving from shell.json have round-tripped through a QML
// `property var`, which stores JS arrays as QVariantList. Reading one back
// yields an array-*like* sequence wrapper that fails Array.isArray, so guard
// on duck-typed length instead and hand back a genuine array.
function toArray(value) {
  if (value === null || value === undefined) return []
  if (Array.isArray(value)) return value
  if (typeof value === "string") return []
  if (typeof value.length !== "number") return []
  var out = []
  for (var i = 0; i < value.length; i++) out.push(value[i])
  return out
}

function escapeRegex(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

// "org.telegram.desktop" -> "desktop" is useless as a match, but for ids like
// "com.mitchellh.ghostty" the trailing segment is what Hyprland reports. Keep
// both and let the matcher try either.
function idVariants(desktopId) {
  var id = String(desktopId || "")
  if (!id) return []
  var variants = [id]
  var parts = id.split(".")
  var tail = parts[parts.length - 1]
  if (parts.length > 1 && tail.length > 2 && tail !== "desktop") variants.push(tail)
  return variants
}

// A record's `match` is a user-supplied regex when present, otherwise an
// alternation over the desktop id variants. Anchored on word boundaries the
// same way omarchy-launch-or-focus does, so "code" does not match "codes".
function buildPattern(record) {
  if (record.match) return record.match
  var variants = idVariants(record.desktopId)
  if (variants.length === 0) return ""
  var escaped = []
  for (var i = 0; i < variants.length; i++) escaped.push(escapeRegex(variants[i]))
  return "(" + escaped.join("|") + ")"
}

function matcherFor(record) {
  var pattern = buildPattern(record)
  if (!pattern) return null
  try {
    return new RegExp("\\b" + pattern + "\\b", "i")
  } catch (e) {
    // A bad user regex should disable that one button, not break the bar.
    return null
  }
}

// Accepts either a bare string ("chromium") or a full object. Everything the
// widget reads later is present on the returned record, so the QML side never
// has to re-check for undefined.
function normalizeApp(entry, index) {
  var record = null

  if (typeof entry === "string") {
    record = { desktopId: entry }
  } else if (entry && typeof entry === "object") {
    record = {
      desktopId: String(entry.desktopId || entry.id || ""),
      match: String(entry.match || ""),
      exec: String(entry.exec || ""),
      icon: String(entry.icon || ""),
      label: String(entry.label || entry.tooltip || ""),
      matchTitle: entry.matchTitle === true
    }
  }

  if (!record) return null

  record.desktopId = String(record.desktopId || "")
  record.match = String(record.match || "")
  record.exec = String(record.exec || "")
  record.icon = String(record.icon || "")
  record.label = String(record.label || "")
  record.matchTitle = record.matchTitle === true

  // Nothing to launch and nothing to match against — drop it rather than
  // rendering a dead button.
  if (!record.desktopId && !record.exec && !record.match) return null

  record.key = record.desktopId || record.match || record.exec || ("app-" + index)
  return record
}

function normalizeApps(list) {
  var entries = toArray(list)
  var out = []
  for (var i = 0; i < entries.length; i++) {
    var record = normalizeApp(entries[i], i)
    if (record) out.push(record)
  }
  return out
}

function windowMatches(record, matcher, window) {
  if (!matcher || !window) return false
  if (matcher.test(String(window.appId || ""))) return true
  if (matcher.test(String(window.cls || ""))) return true
  if (record.matchTitle && matcher.test(String(window.title || ""))) return true
  return false
}

// Returns the subset of `windows` belonging to this record, in the order the
// compositor reported them so cycling is stable between clicks.
function windowsFor(record, windows) {
  var matcher = matcherFor(record)
  if (!matcher) return []
  var all = toArray(windows)
  var out = []
  for (var i = 0; i < all.length; i++) {
    if (windowMatches(record, matcher, all[i])) out.push(all[i])
  }
  return out
}

// Index of the window to focus. Without cycling that is always the first
// match; with cycling, a click while one of the app's windows is focused
// advances to the next one and wraps.
function nextWindowIndex(windows, activeAddress, cycle) {
  if (!windows.length) return -1
  if (!cycle || !activeAddress) return 0
  for (var i = 0; i < windows.length; i++) {
    if (windows[i].address === activeAddress) return (i + 1) % windows.length
  }
  return 0
}
