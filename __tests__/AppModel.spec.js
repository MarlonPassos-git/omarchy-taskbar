const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const modelPath = path.join(__dirname, "..", "AppModel.js")
const modelSource = fs.readFileSync(modelPath, "utf8").replace(/^\.pragma library\s*/, "")
const AppModel = {}
vm.createContext(AppModel)
vm.runInContext(modelSource, AppModel, { filename: modelPath })

test("normalizes and serializes pinned applications", () => {
  const records = AppModel.normalizeApps([
    "obsidian",
    { desktopId: "code", label: "Editor", matchTitle: true }
  ])

  assert.equal(records[0].desktopId, "obsidian")
  assert.deepEqual(JSON.parse(JSON.stringify(AppModel.serialize(records))), [
    "obsidian",
    { desktopId: "code", label: "Editor", matchTitle: true }
  ])
})

test("matches windows by desktop id and reported class", () => {
  const record = AppModel.normalizeApp("obsidian", 0)
  const windows = [
    { address: "1", cls: "md.obsidian.Obsidian" },
    { address: "2", appId: "spotify" }
  ]

  const matches = AppModel.windowsFor(record, windows)

  assert.deepEqual(JSON.parse(JSON.stringify(matches.map(window => window.address))), ["1"])
})

test("cycles to the next matching window", () => {
  const windows = [{ address: "1" }, { address: "2" }]

  assert.equal(AppModel.nextWindowIndex(windows, "1", true), 1)
  assert.equal(AppModel.nextWindowIndex(windows, "2", true), 0)
  assert.equal(AppModel.nextWindowIndex(windows, "2", false), 0)
})

test("derives a Chromium web app class pattern", () => {
  const command = "omarchy-launch-webapp https://discord.com/channels/@me"

  const pattern = AppModel.webappPattern(command)

  assert.equal(pattern, "discord\\.com__channels")
})

test("normalizes a readable dedicated workspace name", () => {
  assert.equal(AppModel.normalizeWorkspaceName("  Project,   Notes\n"), "Project- Notes-")
})

test("builds a named workspace selector", () => {
  assert.equal(AppModel.workspaceTarget({ workspace: "Obsidian" }), "name:Obsidian")
  assert.equal(AppModel.workspaceTarget({ workspace: "" }), "")
})

test("builds workspace actions with window icons", () => {
  assert.equal(
    AppModel.workspaceActionOption({ workspace: "Obsidian" }),
    "󰖭\tRemove dedicated workspace\tworkspace-off"
  )
  assert.equal(
    AppModel.workspaceActionOption({ workspace: "" }),
    "󰖮\tUse dedicated workspace\tworkspace-on"
  )
})

test("plans every matching window into the app workspace", () => {
  const records = AppModel.normalizeApps([{ desktopId: "obsidian", workspace: "Obsidian" }])
  const windows = [
    { address: "1", cls: "md.obsidian.Obsidian", workspace: "3" },
    { address: "2", cls: "md.obsidian.Obsidian", workspace: "Obsidian" },
    { address: "3", cls: "md.obsidian.Obsidian", workspace: "4" },
    { address: "4", cls: "spotify", workspace: "5" }
  ]

  const moves = AppModel.workspaceMoves(records, windows, "3")

  assert.deepEqual(JSON.parse(JSON.stringify(moves)), [
    { address: "1", workspace: "name:Obsidian", follow: false },
    { address: "3", workspace: "name:Obsidian", follow: true }
  ])
})

test("updates workspace assignment without mutating the pin", () => {
  const records = AppModel.normalizeApps([{ desktopId: "obsidian", match: "Obsidian" }])

  const enabled = AppModel.updatedWorkspace(records, 0, "  Obsidian  ")
  const disabled = AppModel.updatedWorkspace(enabled, 0, "")

  assert.equal(records[0].workspace, "")
  assert.equal(enabled[0].workspace, "Obsidian")
  assert.equal(enabled[0].match, "Obsidian")
  assert.equal(disabled[0].workspace, "")
})

test("serializes the workspace assignment with the pinned app", () => {
  const records = AppModel.normalizeApps([{ desktopId: "obsidian", workspace: "Obsidian" }])

  assert.deepEqual(JSON.parse(JSON.stringify(AppModel.serialize(records))), [
    { desktopId: "obsidian", workspace: "Obsidian" }
  ])
})

test("escapes workspace values in the Hyprland Lua dispatcher", () => {
  const move = {
    address: "abc",
    workspace: "name:Bob's \"Notes\"\\Archive",
    follow: true
  }

  assert.equal(
    AppModel.workspaceDispatcher(move),
    "hl.dsp.window.move({ workspace = \"name:Bob's \\\"Notes\\\"\\\\Archive\", window = \"address:0xabc\", follow = true })"
  )
})

test("normalizes Quickshell window addresses for Hyprland", () => {
  assert.equal(AppModel.hyprlandAddressSelector("55a2701f33a0"), "address:0x55a2701f33a0")
  assert.equal(AppModel.hyprlandAddressSelector("0x55a2701f33a0"), "address:0x55a2701f33a0")
  assert.equal(AppModel.hyprlandAddressSelector(""), "")
})

test("quotes arbitrary text as a Lua string", () => {
  assert.equal(AppModel.luaQuoted("a\\b\"c\nd"), '"a\\\\b\\"c\\nd"')
})
