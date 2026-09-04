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
