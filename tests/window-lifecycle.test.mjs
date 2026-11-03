import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { linkShellUi } from "./shell-fixture.mjs"

// The window is an ordinary toplevel: the compositor decides placement and
// size, so opening must not wait on any compositor-specific setup.
const source = fs.readFileSync(new URL("../RadioAtlas.qml", import.meta.url), "utf8")
const sizing = source.match(/  readonly property int preferredWidth: .*\n  readonly property int preferredHeight: .*\n/)[0]
const lifecycle = source.match(/  function (?:open|openWindow|close|dismiss)\([\s\S]*?\n  \}/g).join("\n")
const windowSignals = source.match(/    onVisibleChanged: \{[\s\S]*?\n    \}/)[0]
const minimumSize = source.match(/    minimumSize: (.*)/)[1]
const shellDirectory = process.env.OMARCHY_SHELL_DIR || "/usr/share/omarchy/shell"
const directory = fs.mkdtempSync(path.join(os.tmpdir(), "radio-atlas-window-lifecycle-"))

try {
  linkShellUi(directory, shellDirectory)
  fs.cpSync(fileURLToPath(new URL("./qml-imports/Quickshell", import.meta.url)),
    path.join(directory, "Quickshell"), { recursive: true })
  fs.writeFileSync(path.join(directory, "tst_window_lifecycle.qml"), `
import QtQuick
import QtTest
import qs.Commons

TestCase {
  id: root
  name: "WindowLifecycle"
  ${sizing}
  property bool opened: false
  property bool helpVisible: false
  property bool outputMenuOpen: false
  property var manifest: null
  property int dismissals: 0
  property var shell: QtObject {
    function hide(id) { root.dismissals++ }
  }
  property int stateLoads: 0
  property int worldExpansionMisses: 0
  property var worldStations: [{}]
  property string fetchError: ""
  property int randomRequests: 0
  property int worldRequests: 0
  function loadState() { stateLoads++ }
  function showWorld() { worldRequests++ }
  function tuneRandom() { randomRequests++ }
  function scheduleWorldExpansion(delay) {}
  ${lifecycle}
  QtObject {
    id: panel
    property bool visible: false
    property size minimumSize: ${minimumSize}
    ${windowSignals}
  }
  Item { id: keyCatcher }
  QtObject { id: globe; function stopKineticRotation(clear) {} }
  QtObject { id: worldExpandProcess; property bool running: false }
  Timer { id: worldExpandTimer }

  function init() {
    close()
    stateLoads = 0
    dismissals = 0
    randomRequests = 0
    worldRequests = 0
    worldStations = [{}]
    Style.fontBaseSize = 12
    Style.spacingScale = 1
    Style.spacingScaleWithFont = true
  }

  function test_requestedSizeFollowsSpacingScale_data() {
    return [
      { tag: "default-font", font: 12, width: 1180, height: 760, minWidth: 800, minHeight: 560 },
      { tag: "larger-font", font: 18, width: 1770, height: 1140, minWidth: 1200, minHeight: 840 }
    ]
  }
  function test_requestedSizeFollowsSpacingScale(data) {
    Style.fontBaseSize = data.font
    compare(preferredWidth, data.width)
    compare(preferredHeight, data.height)
    compare(panel.minimumSize.width, data.minWidth)
    compare(panel.minimumSize.height, data.minHeight)
  }
  function test_openMapsImmediately() {
    open("{}")
    compare(panel.visible, true, "No compositor setup may delay mapping")
    compare(opened, true)
    compare(stateLoads, 1)
    compare(randomRequests, 0)
  }
  function test_randomPayloadTunesOnOpen() {
    worldStations = []
    open('{"action":"random"}')
    compare(panel.visible, true)
    compare(worldRequests, 1, "Random tuning needs the world list")
    compare(randomRequests, 1)
  }
  function test_invalidPayloadOpensWorld_data() {
    return [{ tag: "null", payload: "null" }, { tag: "malformed", payload: "{" },
      { tag: "empty", payload: "" }]
  }
  function test_invalidPayloadOpensWorld(data) {
    worldStations = []
    open(data.payload)
    compare(panel.visible, true)
    compare(worldRequests, 1, "Invalid payloads must still complete normal startup")
    compare(randomRequests, 0)
  }
  function test_summonWhileOpenKeepsWindowVisible() {
    open("{}")
    open('{"action":"random"}')
    compare(panel.visible, true)
    compare(randomRequests, 1)
    compare(dismissals, 0)
  }
  function test_closeHidesWithoutDismissingHost() {
    open("{}")
    close()
    compare(panel.visible, false)
    compare(opened, false)
    compare(dismissals, 0, "close() is the host's own request")
  }
  function test_compositorCloseDismisses() {
    open("{}")
    panel.visible = false
    compare(opened, false)
    compare(dismissals, 1, "A window closed by the compositor must tell the host")
  }
  function test_dismissWithoutHostOnlyCloses() {
    shell = null
    open("{}")
    dismiss()
    compare(panel.visible, false)
    compare(opened, false)
  }
}
`)
  const result = spawnSync("/usr/lib/qt6/bin/qmltestrunner", ["-platform", "offscreen", "-import", directory, "-input", directory], {
    env: { ...process.env, QT_QUICK_BACKEND: "software", QT_NO_XDG_DESKTOP_PORTAL: "1", QT_QPA_PLATFORMTHEME: "" },
    stdio: "inherit",
  })
  if (result.error) throw result.error
  assert.equal(result.status, 0, "Window lifecycle tests failed")
} finally {
  fs.rmSync(directory, { recursive: true, force: true })
}
