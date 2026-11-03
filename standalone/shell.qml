// Standalone entry point: runs Radio Atlas as its own Quickshell instance
// instead of an Omarchy shell panel. The installed layout puts this file next
// to RadioAtlas.qml, with the vendored qs.Commons and qs.Ui modules beside it.
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  RadioAtlas {
    id: radio

    // Closing the window ends this instance; the player keeps running on its
    // own and is controlled through MPRIS or `radio-atlas stop`.
    shell: QtObject {
      function hide(id) { Qt.quit() }
    }

    Component.onCompleted: {
      var action = Quickshell.env("RADIO_ATLAS_ACTION") || ""
      radio.open(JSON.stringify(action === "random" ? { action: "random" } : {}))
    }
  }

  IpcHandler {
    target: "radio-atlas"

    function open(): void { radio.open("{}") }
    function random(): void { radio.open(JSON.stringify({ action: "random" })) }
    function toggle(): void {
      if (radio.opened) radio.dismiss()
      else radio.open("{}")
    }
  }
}
