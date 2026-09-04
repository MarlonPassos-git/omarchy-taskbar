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

test("normalizes a readable dedicated workspace name", () => {
  assert.equal(AppModel.normalizeWorkspaceName("  Project,   Notes\n"), "Project- Notes-")
})

test("builds a named workspace selector", () => {
  assert.equal(AppModel.workspaceTarget({ workspace: "Obsidian" }), "name:Obsidian")
  assert.equal(AppModel.workspaceTarget({ workspace: "" }), "")
})

test("plans every matching window into the app workspace", () => {
  const records = AppModel.normalizeApps([{ desktopId: "obsidian", workspace: "Obsidian" }])
  const windows = [
    { address: "0x1", cls: "md.obsidian.Obsidian", workspace: "3" },
    { address: "0x2", cls: "md.obsidian.Obsidian", workspace: "Obsidian" },
    { address: "0x3", cls: "md.obsidian.Obsidian", workspace: "4" },
    { address: "0x4", cls: "spotify", workspace: "5" }
  ]

  const moves = AppModel.workspaceMoves(records, windows, "0x3")

  assert.deepEqual(JSON.parse(JSON.stringify(moves)), [
    { address: "0x1", workspace: "name:Obsidian", follow: false },
    { address: "0x3", workspace: "name:Obsidian", follow: true }
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
    address: "0xabc",
    workspace: "name:Bob's \"Notes\"\\Archive",
    follow: true
  }

  assert.equal(
    AppModel.workspaceDispatcher(move),
    "hl.dsp.window.move({ workspace = \"name:Bob's \\\"Notes\\\"\\\\Archive\", window = \"address:0xabc\", follow = true })"
  )
})

test("quotes arbitrary text as a Lua string", () => {
  assert.equal(AppModel.luaQuoted("a\\b\"c\nd"), '"a\\\\b\\"c\\nd"')
})
