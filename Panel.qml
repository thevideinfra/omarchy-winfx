pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "videinfra.omarchy-winfx"
  ipcTarget: "videinfra.omarchy-winfx"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("bin/omarchy-winfx").toString().replace(/^file:\/\//, ""))
  readonly property string repoUrl: "https://github.com/thevideinfra/omarchy-winfx"
  property string version: ""

  // ---- Display settings (shell.json, set from the gear view) ----
  readonly property string density: String(setting("density", "normal"))
  readonly property real densityScale: Model.densityScale(density)
  readonly property string fontSize: String(setting("fontSize", "normal"))
  readonly property bool showAccent: Model.settingBool(setting("showAccent", true), true)
  readonly property string accentChoice: String(setting("accent", "theme"))
  readonly property bool showHeaderInfo: Model.settingBool(setting("showHeaderInfo", true), true)
  property bool settingsOpen: false

  // The version shown in the header comes from this plugin's manifest, so it
  // cannot drift from the release.
  FileView {
    path: Qt.resolvedUrl("manifest.json")
    printErrors: false
    onLoaded: root.version = Model.manifestVersion(text())
  }

  AccentSource {
    id: accentSource
    choice: root.accentChoice
  }

  // The colour the panel highlights with: the theme's accent unless one is
  // picked in settings, or the neutral foreground when accents are off.
  readonly property color accent: Model.accentFor(showAccent, accentSource.value, bar.foreground)
  // Text shrinks half as fast as spacing so compact stays readable, then the
  // font size setting scales it on top.
  readonly property real fontScale: (0.5 + 0.5 * densityScale) * Model.fontSizeScale(fontSize)
  readonly property real fontTitle: Math.round(Style.font.title * fontScale)
  readonly property real fontBody: Math.max(8, Math.round(Style.font.body * fontScale))
  readonly property real fontCaption: Math.max(9, Math.round(Style.font.caption * fontScale))
  readonly property real fontDisplay: Math.round(Style.font.display * fontScale)
  // Every button shares one text size and one height; icons in buttons are larger than their labels.
  readonly property real controlHeight: Math.round(fontBody * 2.5)
  readonly property real fontGlyph: Math.round(fontBody * 1.7)

  // Style.space scaled by the chosen density.
  function sp(px) {
    return Style.space(px * densityScale)
  }

  function setSetting(key, value) {
    Quickshell.execDetached(["omarchy", "bar", "set", "videinfra.omarchy-winfx", key, JSON.stringify(value), "--json"])
  }

  // ---- Effect settings (the helper's own file; they drive the compositor) ----
  readonly property var defaults: ({ enabled: false, effect: "crumble", duration: 450, size: "medium", when: "close",
    sync: true, openEffect: "crumble", openDuration: 450, openSize: "medium" })
  property bool pEnabled: false
  property string pEffect: "crumble"
  property int pDuration: 450
  property string pSize: "medium"
  property string pWhen: "close"
  property bool pSync: true
  property string pOpenEffect: "crumble"
  property int pOpenDuration: 450
  property string pOpenSize: "medium"
  // Which direction the effect controls edit while closing and opening differ.
  property string editing: "close"
  property var saved: defaults
  property bool ready: false
  property bool loaded: false
  property bool busy: false
  property bool installed: false
  property bool backendLoaded: false
  property bool versionOk: true
  readonly property string installScript: decodeURIComponent(Qt.resolvedUrl("install.sh").toString().replace(/^file:\/\//, ""))
  property string errorText: ""
  property string backendText: "Checking backend…"
  readonly property var effects: [
    { key: "crumble", title: "Crumble", glyph: "▦", detail: "Small pieces fall away and fade." },
    { key: "shatter", title: "Shatter", glyph: "✦", detail: "Breaks like glass into jagged shards that tumble and fall." },
    { key: "dissolve", title: "Dissolve", glyph: "⋯", detail: "Fine blocks dissolve in a noise pattern." },
    { key: "pixelate", title: "Pixelate", glyph: "▩", detail: "Growing blocks fade into the desktop." },
    { key: "explode", title: "Explode", glyph: "✹", detail: "Chunks blast outward from a flash. Opening pulls them together." },
    { key: "build", title: "Build", glyph: "▤", detail: "Bricks drop away from the top down. Opening builds from the bottom up." },
    { key: "blinds", title: "Blinds", glyph: "☰", detail: "Strips slide off in alternating directions." },
    { key: "glitch", title: "Glitch", glyph: "▚", detail: "Bands jump, colours split and blocks drop out." },
    { key: "tv", title: "TV", glyph: "▬", detail: "Squashes to a bright line, then a dot, like an old TV switching off." },
    { key: "matrix", title: "Matrix", glyph: "⠿", detail: "Green digital rain sweeps down and wipes the window away." },
    { key: "default", title: "Default", glyph: "−", detail: "Use your existing Omarchy window animations." }
  ]
  // The direction the effect controls edit: with one direction picked it is that
  // one, with both synced it is closing (opening mirrors it), otherwise the
  // direction chosen in the selector.
  readonly property bool editOpen: pWhen === "open" || (pWhen === "both" && !pSync && editing === "open")
  readonly property bool synced: pWhen === "both" && pSync
  readonly property string curEffect: editOpen ? pOpenEffect : pEffect
  readonly property int curDuration: editOpen ? pOpenDuration : pDuration
  readonly property string curSize: editOpen ? pOpenSize : pSize
  readonly property bool curDefault: curEffect === "default"
  function setCur(key, value) {
    if (editOpen) {
      if (key === "effect") pOpenEffect = value
      else if (key === "duration") pOpenDuration = value
      else pOpenSize = value
    } else {
      if (key === "effect") pEffect = value
      else if (key === "duration") pDuration = value
      else pSize = value
    }
  }
  // Turning sync off starts opening from what closing has now.
  function setSync(on) {
    if (!on) { pOpenEffect = pEffect; pOpenDuration = pDuration; pOpenSize = pSize; editing = "close" }
    pSync = on
  }
  function setWhen(value) {
    pWhen = value
    if (value !== "both") editing = value
  }
  // The effects that would actually play, to know whether the backend is needed.
  function playing() {
    var list = []
    if (pWhen !== "open") list.push(pEffect)
    if (pWhen !== "close") list.push(synced ? pEffect : pOpenEffect)
    return list.filter(function(e) { return e !== "default" })
  }
  readonly property bool needsBackend: pEnabled && playing().length > 0
  readonly property bool dirty: JSON.stringify(shape(staged())) !== JSON.stringify(shape(saved))
  // A fresh `omarchy plugin add` has no loader or backend behind it. Offer to
  // install them instead of showing controls that cannot work yet.
  readonly property bool needsSetup: loaded && (!installed || (!ready && !saved.enabled))
  readonly property bool canInstall: needsSetup && versionOk
  readonly property bool controlsEnabled: loaded && !busy && !reader.running
  readonly property bool canApply: loaded && dirty && !busy && !reader.running && (!needsBackend || ready)

  // Same keys, same order, opening mirrored when synced: staged and saved compare equal when nothing changed.
  function shape(s) {
    var mirror = s.sync && s.when === "both"
    return [s.enabled, s.effect, s.duration, s.size, s.when, s.sync,
      mirror ? s.effect : s.openEffect, mirror ? s.duration : s.openDuration, mirror ? s.size : s.openSize]
  }
  function staged() {
    return { enabled: pEnabled, effect: pEffect, duration: pDuration, size: pSize, when: pWhen, sync: pSync,
      openEffect: pOpenEffect, openDuration: pOpenDuration, openSize: pOpenSize }
  }
  function stage(s) {
    pEnabled = s.enabled; pEffect = s.effect; pDuration = s.duration; pSize = s.size; pWhen = s.when; pSync = s.sync
    pOpenEffect = s.openEffect; pOpenDuration = s.openDuration; pOpenSize = s.openSize
    editing = s.when === "open" ? "open" : "close"
  }
  function reload() { if (!reader.running) reader.running = true }
  function apply() {
    if (!canApply) return
    busy = true
    errorText = ""
    writer.command = [helper, "apply", JSON.stringify(staged())]
    writer.running = true
  }
  // install.sh asks for sudo and shows hyprpm's output, so it runs in a
  // terminal that stays open until a key is pressed.
  function runInstall() {
    var args = [installScript]
    if (!backendLoaded) args.push("--backend")
    Quickshell.execDetached(["omarchy-launch-tui", "--app-id=org.omarchy.omarchy-winfx-install", "bash", "-c",
      "\"$@\"; code=$?; echo; read -r -n 1 -p 'Press any key to close'; exit $code", "install"].concat(args))
    close()
  }
  function selectEffect(delta) {
    var index = effects.findIndex(function(e) { return e.key === curEffect })
    setCur("effect", effects[(index + delta + effects.length) % effects.length].key)
  }
  function description() {
    for (var i = 0; i < effects.length; i++) if (effects[i].key === curEffect) return effects[i].detail
    return ""
  }
  onOpenedChanged: if (opened) { errorText = ""; settingsOpen = false; reload() }
  Component.onCompleted: reload()

  Process {
    id: reader
    command: [root.helper, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var result = JSON.parse(text)
          root.saved = result.settings
          root.stage(result.settings)
          root.ready = result.ready
          root.installed = result.installed
          root.backendLoaded = result.backend
          root.versionOk = result.version === result.target
          root.loaded = true
          root.backendText = !result.installed ? "Not installed yet"
            : result.version !== result.target ? "Requires Hyprland " + result.target
            : !result.backend ? "HyprWindowShade is not loaded"
            : "HyprWindowShade · ready"
        } catch (e) { root.loaded = false; root.ready = false; root.errorText = "Could not read settings" }
      }
    }
    stderr: StdioCollector { id: readError; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) { root.loaded = false; root.ready = false; root.errorText = readError.text.trim() || "Could not read settings" }
    }
  }

  Process {
    id: writer
    stderr: StdioCollector { id: writeError; waitForEnd: true }
    onExited: function(code) {
      root.busy = false
      if (code === 0) root.reload()
      else root.errorText = writeError.text.trim() || "Could not apply settings"
    }
  }

  Process {
    id: tester
    command: [root.helper, "preview"]
    stderr: StdioCollector { id: testError; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) root.errorText = testError.text.trim() || "Could not open test window"
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "▦"
    tooltipText: root.needsSetup ? "WinFX · click to set up" : "WinFX · window effects"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // Less padding than the shell's popups, to save space; the width gives up
    // the same amount so the content area keeps its size.
    padding: Style.space(8)
    readonly property int savedPadding: Math.max(0, Style.spacing.popupPadding - panel.padding)
    contentWidth: panel.fittedContentWidth(root.sp(380) - 2 * savedPadding)
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.apply()
      onMoveRequested: function(dx, dy) {
        if (root.controlsEnabled && !root.settingsOpen) root.selectEffect(dy !== 0 ? dy : dx)
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: panelColumn
        width: parent.width
        spacing: root.sp(14)

        // ---------- Hero: icon · title/status ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerSwitch.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: "▦"
            color: root.accent
            font.family: root.bar.fontFamily
            font.pixelSize: root.fontDisplay
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          // The switch owns enabling, mouse and keyboard alike.
          AccentSwitch {
            id: powerSwitch
            checked: root.pEnabled
            enabled: root.controlsEnabled && root.installed && (root.ready || root.pEnabled || root.playing().length === 0)
            opacity: enabled ? 1 : 0.4
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            onToggled: root.pEnabled = !root.pEnabled

            PanelToolTip {
              visible: powerSwitch.containsMouse
              text: root.pEnabled ? "Effects on" : "Effects off"
              fontFamily: root.bar.fontFamily
            }
          }

          // Opens the settings view in place of the panel content.
          Text {
            id: gearButton
            anchors.right: powerSwitch.left
            anchors.rightMargin: root.sp(12)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.settingsOpen ? "󰅖" : "󰒓"
            color: gearMouse.containsMouse || root.settingsOpen ? root.accent : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Math.round(root.fontTitle * 1.45)
            opacity: gearMouse.containsMouse || root.settingsOpen ? 1.0 : 0.85

            MouseArea {
              id: gearMouse
              anchors.fill: parent
              anchors.margins: -root.sp(4)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.settingsOpen = !root.settingsOpen
            }

            PanelToolTip {
              visible: gearMouse.containsMouse
              text: root.settingsOpen ? "Close settings" : "Panel settings"
              fontFamily: root.bar.fontFamily
            }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: root.sp(14)
            anchors.right: parent.right
            anchors.rightMargin: powerSwitch.width + gearButton.width + root.sp(24)
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.sp(2)

            // The name on the left; the version and a link to the repository on
            // the right of the same line, next to the gear.
            Item {
              width: parent.width
              implicitHeight: Math.max(titleText.implicitHeight, infoRow.implicitHeight)

              Text {
                id: titleText
                anchors.left: parent.left
                anchors.right: infoRow.visible ? infoRow.left : parent.right
                anchors.rightMargin: root.sp(8)
                anchors.verticalCenter: parent.verticalCenter
                text: "WinFX"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: root.fontTitle
                font.bold: true
                elide: Text.ElideRight
              }

              Row {
                id: infoRow
                visible: root.showHeaderInfo
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.sp(8)

                Rectangle {
                  visible: root.version !== ""
                  anchors.verticalCenter: parent.verticalCenter
                  width: versionText.implicitWidth + root.sp(10)
                  height: versionText.implicitHeight + root.sp(4)
                  radius: height / 2
                  color: Util.alpha(root.accent, 0.15)
                  border.width: 1
                  border.color: Util.alpha(root.accent, 0.45)

                  Text {
                    id: versionText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "v" + root.version
                    color: root.accent
                    font.family: root.bar.fontFamily
                    font.pixelSize: root.fontCaption
                    font.bold: true
                  }
                }

                // Opens the repository in the browser.
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: ""
                  color: repoMouse.containsMouse ? root.accent : root.bar.foreground
                  opacity: repoMouse.containsMouse ? 1.0 : 0.6
                  font.family: root.bar.fontFamily
                  font.pixelSize: root.fontBody

                  MouseArea {
                    id: repoMouse
                    anchors.fill: parent
                    anchors.margins: -root.sp(4)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.bar) root.bar.run("xdg-open " + root.bar.shellQuote(root.repoUrl))
                  }

                  PanelToolTip {
                    visible: repoMouse.containsMouse
                    text: "Open on GitHub"
                    fontFamily: root.bar.fontFamily
                  }
                }
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Window open and close effects"
              color: root.bar.foreground
              opacity: 0.55
              font.family: root.bar.fontFamily
              font.pixelSize: root.fontCaption
              elide: Text.ElideRight
            }
          }
        }

        // First run: nothing is installed yet, so offer to set it up.
        Column {
          width: parent.width
          spacing: root.sp(14)
          visible: !root.settingsOpen && root.needsSetup

          PanelSeparator { foreground: root.bar.foreground }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.canInstall
              ? "Window effects need a Hyprland loader and the HyprWindowShade backend. Install opens a terminal that sets up what is missing."
              : root.backendText
            color: root.bar.foreground
            opacity: 0.75
            wrapMode: Text.WordWrap
            font.family: root.bar.fontFamily
            font.pixelSize: root.fontBody
          }

          Text {
            width: parent.width
            visible: root.canInstall
            textFormat: Text.PlainText
            text: root.backendText
            color: root.bar.foreground
            opacity: 0.55
            wrapMode: Text.WordWrap
            font.family: root.bar.fontFamily
            font.pixelSize: root.fontCaption
          }

          ActionButton {
            width: parent.width
            visible: root.canInstall
            text: root.installed ? "Build backend" : "Install"
            primary: true
            onClicked: root.runInstall()
          }
        }

        // Everything below the header; the gear swaps it for the settings view.
        Column {
          width: parent.width
          spacing: root.sp(14)
          visible: !root.settingsOpen && !root.needsSetup

          PanelSeparator { foreground: root.bar.foreground }

          Column {
            width: parent.width
            spacing: root.sp(8)
            enabled: root.controlsEnabled

            SectionLabel {
              icon: "\uf021"
              text: "ANIMATE"
              hint: root.dirty ? "UNSAVED" : ""
            }

            Segmented {
              width: parent.width
              columns: 3
              choices: [
                { value: "close", label: "Closing" },
                { value: "open", label: "Opening" },
                { value: "both", label: "Both" }
              ]
              selected: root.pWhen
              onPicked: function(value) { root.setWhen(value) }
            }

            SettingSwitch {
              width: parent.width
              visible: root.pWhen === "both"
              label: "Same effect for both"
              checked: root.pSync
              onToggled: root.setSync(!root.pSync)
            }

            Segmented {
              width: parent.width
              visible: root.pWhen === "both" && !root.pSync
              columns: 2
              choices: [
                { value: "close", label: "Edit closing" },
                { value: "open", label: "Edit opening" }
              ]
              selected: root.editing
              onPicked: function(value) { root.editing = value }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          Column {
            width: parent.width
            spacing: root.sp(8)

            SectionLabel {
              icon: ""
              text: root.synced ? "EFFECT" : root.editOpen ? "OPENING EFFECT" : "CLOSING EFFECT"
            }

            Segmented {
              width: parent.width
              columns: 2
              enabled: root.controlsEnabled
              tall: true
              choices: root.effects.slice(0, root.effects.length - 1).map(function(e) { return { value: e.key, label: e.title, glyph: e.glyph } })
              selected: root.curEffect
              onPicked: function(value) { root.setCur("effect", value) }
            }

            Segmented {
              width: parent.width
              columns: 1
              enabled: root.controlsEnabled
              choices: [{ value: "default", label: "Default Omarchy animation", glyph: "⊘" }]
              selected: root.curEffect
              onPicked: function(value) { root.setCur("effect", value) }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.description()
              color: root.bar.foreground
              opacity: 0.6
              wrapMode: Text.WordWrap
              font.family: root.bar.fontFamily
              font.pixelSize: root.fontCaption
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          Column {
            width: parent.width
            spacing: root.sp(8)
            enabled: root.controlsEnabled && !root.curDefault
            opacity: enabled ? 1 : 0.4

            SectionLabel {
              icon: ""
              text: "DURATION"
              hint: root.curDuration + " ms"
            }

            Segmented {
              width: parent.width
              columns: 5
              choices: [
                { value: "less", label: "−" },
                { value: 250, label: "250" },
                { value: 450, label: "450" },
                { value: 750, label: "750" },
                { value: "more", label: "+" }
              ]
              selected: root.curDuration
              onPicked: function(value) {
                if (value === "less") root.setCur("duration", Math.max(150, root.curDuration - 50))
                else if (value === "more") root.setCur("duration", Math.min(1500, root.curDuration + 50))
                else root.setCur("duration", value)
              }
            }
          }

          Column {
            width: parent.width
            spacing: root.sp(8)
            enabled: root.controlsEnabled && !root.curDefault
            opacity: enabled ? 1 : 0.4

            SectionLabel {
              icon: ""
              text: "FRAGMENT SIZE"
            }

            Segmented {
              width: parent.width
              columns: 3
              choices: [
                { value: "small", label: "Small" },
                { value: "medium", label: "Medium" },
                { value: "large", label: "Large" }
              ]
              selected: root.curSize
              onPicked: function(value) { root.setCur("size", value) }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          Row {
            width: parent.width
            spacing: root.sp(7)

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: root.sp(6)
              height: width
              radius: width / 2
              color: root.ready ? root.accent : root.bar.foreground
              opacity: root.ready ? 1 : 0.4
            }

            Text {
              width: parent.width - root.sp(13)
              textFormat: Text.PlainText
              text: root.backendText
              color: root.bar.foreground
              opacity: 0.65
              wrapMode: Text.WordWrap
              font.family: root.bar.fontFamily
              font.pixelSize: root.fontCaption
            }
          }

          Text {
            width: parent.width
            visible: root.errorText !== ""
            textFormat: Text.PlainText
            text: root.errorText
            color: root.bar.foreground
            wrapMode: Text.WrapAnywhere
            font.family: root.bar.fontFamily
            font.pixelSize: root.fontCaption
          }

          Row {
            width: parent.width
            spacing: root.sp(6)
            readonly property real cell: (width - 2 * spacing) / 3

            ActionButton {
              width: parent.cell
              text: "Test"
              enabled: root.controlsEnabled && !tester.running && !root.dirty
              onClicked: { root.errorText = ""; tester.running = true }
            }

            ActionButton {
              width: parent.cell
              text: "Reset"
              enabled: root.controlsEnabled
              onClicked: root.stage(root.defaults)
            }

            ActionButton {
              width: parent.cell
              text: root.busy ? "Applying…" : "Apply"
              primary: root.canApply
              enabled: root.canApply
              onClicked: root.apply()
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.dirty ? "Apply changes before opening a test window." : "↑ ↓ choose  ·  Enter apply  ·  Esc close"
            color: root.bar.foreground
            opacity: 0.4
            wrapMode: Text.WordWrap
            font.family: root.bar.fontFamily
            font.pixelSize: root.fontCaption
          }
        }

        SettingsView {
          width: parent.width
          visible: root.settingsOpen
        }
      }
    }
  }

  // Replaces the panel content while the gear is on. Every change is saved
  // to shell.json straight away and read back through setting().
  component SettingsView: Column {
    spacing: root.sp(12)

    PanelSeparator { foreground: root.bar.foreground }

    Item {
      width: parent.width
      implicitHeight: settingsBack.implicitHeight

      Text {
        id: settingsBack
        textFormat: Text.PlainText
        text: "󰁍 Back"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: root.fontCaption
        font.bold: true
        opacity: backMouse.containsMouse ? 1.0 : 0.75

        MouseArea {
          id: backMouse
          anchors.fill: parent
          anchors.margins: -root.sp(4)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.settingsOpen = false
        }
      }
    }

    SectionLabel {
      icon: ""
      text: "DENSITY"
    }

    Segmented {
      width: parent.width
      columns: 3
      choices: [
        { value: "compact", label: "Compact" },
        { value: "normal", label: "Normal" },
        { value: "roomy", label: "Roomy" }
      ]
      selected: root.density
      onPicked: function(value) { root.setSetting("density", value) }
    }

    SectionLabel {
      icon: ""
      text: "FONT SIZE"
    }

    Segmented {
      width: parent.width
      columns: 3
      choices: [
        { value: "small", label: "Small" },
        { value: "normal", label: "Normal" },
        { value: "large", label: "Large" }
      ]
      selected: root.fontSize
      onPicked: function(value) { root.setSetting("fontSize", value) }
    }

    SectionLabel {
      icon: ""
      text: "ACCENT"
    }

    SettingSwitch {
      width: parent.width
      label: "Accent colours"
      checked: root.showAccent
      onToggled: root.setSetting("showAccent", !root.showAccent)
    }

    AccentPicker {
      width: parent.width
      enabled: root.showAccent
      opacity: root.showAccent ? 1 : 0.4
    }

    PanelSeparator { foreground: root.bar.foreground }

    SectionLabel {
      icon: ""
      text: "SHOW"
    }

    SettingSwitch {
      width: parent.width
      label: "Version & GitHub link"
      checked: root.showHeaderInfo
      onToggled: root.setSetting("showHeaderInfo", !root.showHeaderInfo)
    }
  }

  // A labelled on/off switch row for the settings view.
  component SettingSwitch: Item {
    id: settingRow
    property string label: ""
    property bool checked: false
    signal toggled()

    implicitHeight: Math.max(settingLabel.implicitHeight, settingToggle.implicitHeight)

    Text {
      id: settingLabel
      anchors.left: parent.left
      anchors.right: settingToggle.left
      anchors.rightMargin: root.sp(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: settingRow.label
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: root.fontBody
      elide: Text.ElideRight
    }

    AccentSwitch {
      id: settingToggle
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: settingRow.checked
      onToggled: settingRow.toggled()
    }
  }

  // On/off switch in the theme accent: accent track and knob when on, a dim
  // neutral track when off.
  component AccentSwitch: Item {
    id: sw
    property bool checked: false
    readonly property bool containsMouse: swMouse.containsMouse
    signal toggled()

    implicitWidth: root.sp(34)
    implicitHeight: root.sp(18)

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: sw.checked ? Util.alpha(root.accent, 0.3) : Util.alpha(root.bar.foreground, 0.1)
      border.width: 1
      border.color: sw.checked ? root.accent : Util.alpha(root.bar.foreground, 0.25)
      Behavior on color { ColorAnimation { duration: 120 } }

      Rectangle {
        width: parent.height - root.sp(6)
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: sw.checked ? parent.width - width - (parent.height - height) / 2 : (parent.height - height) / 2
        color: sw.checked ? root.accent : Qt.darker(root.bar.foreground, 1.4)
        Behavior on x { NumberAnimation { duration: 120 } }
        Behavior on color { ColorAnimation { duration: 120 } }
      }
    }

    MouseArea {
      id: swMouse
      anchors.fill: parent
      anchors.margins: -root.sp(3)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: sw.toggled()
    }
  }

  // Section title: a dim icon, then the bold title, and an
  // optional hint on the trailing edge.
  component SectionLabel: Item {
    id: section
    property string icon: ""
    property string text: ""
    property string hint: ""

    width: parent.width
    implicitHeight: sectionTitle.implicitHeight

    Row {
      spacing: root.sp(7)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: section.icon
        color: root.bar.foreground
        opacity: 0.65
        font.family: root.bar.fontFamily
        font.pixelSize: Math.round(root.fontCaption * 1.2)
      }

      Text {
        id: sectionTitle
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: section.text
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: root.fontCaption
        font.bold: true
        font.letterSpacing: 1.2
      }
    }

    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: section.hint
      color: root.accent
      font.family: root.bar.fontFamily
      font.pixelSize: root.fontCaption
    }
  }

  // Equal-width choice boxes in a grid; the chosen one is
  // tinted and outlined in the accent.
  component Segmented: Grid {
    id: segmented
    property var choices: []
    property var selected
    property bool tall: false
    signal picked(var value)

    spacing: root.sp(6)
    readonly property real cellWidth: (width - (columns - 1) * spacing) / columns

    Repeater {
      model: segmented.choices

      Rectangle {
        id: choice
        required property var modelData
        readonly property bool chosen: segmented.selected === modelData.value
        width: segmented.cellWidth
        implicitHeight: Math.round(root.controlHeight * (segmented.tall ? 1.4 : 1))
        radius: root.sp(7)
        color: chosen
          ? Util.alpha(root.accent, 0.12)
          : Util.alpha(root.bar.foreground, choiceMouse.containsMouse ? 0.09 : 0.05)
        border.width: chosen ? 2 : 1
        border.color: chosen ? root.accent : Util.alpha(root.bar.foreground, 0.12)
        opacity: segmented.enabled ? 1 : 0.4

        Row {
          anchors.centerIn: parent
          spacing: root.sp(8)

          // The icon sits in a fixed slot so every label in a grid lines up.
          Text {
            visible: !!choice.modelData.glyph
            anchors.verticalCenter: parent.verticalCenter
            width: root.fontGlyph * 1.2
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: choice.modelData.glyph || ""
            color: choice.chosen ? root.accent : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: root.fontGlyph
          }

          Text {
            id: choiceText
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: choice.modelData.label
            color: choice.chosen ? root.accent : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: root.fontBody
            font.bold: choice.chosen
          }
        }

        MouseArea {
          id: choiceMouse
          anchors.fill: parent
          enabled: segmented.enabled
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: segmented.picked(choice.modelData.value)
        }
      }
    }
  }

  // A push button in the same box style; `primary` tints it like a chosen
  // option.
  component ActionButton: Rectangle {
    id: action
    property string text: ""
    property bool primary: false
    signal clicked()

    implicitHeight: root.controlHeight
    radius: root.sp(7)
    color: primary
      ? Util.alpha(root.accent, 0.12)
      : Util.alpha(root.bar.foreground, actionMouse.containsMouse && enabled ? 0.09 : 0.05)
    border.width: primary ? 2 : 1
    border.color: primary ? root.accent : Util.alpha(root.bar.foreground, 0.12)
    opacity: enabled ? 1 : 0.4
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: if (enabled) clicked()

    Text {
      id: actionText
      anchors.centerIn: parent
      width: parent.width - root.sp(8)
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: action.text
      color: action.primary ? root.accent : root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: root.fontBody
      font.bold: action.primary
      elide: Text.ElideRight
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      enabled: action.enabled
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: action.clicked()
    }
  }

  // The theme's own accent, then the other colours of its palette, each drawn
  // in its real colour. The chosen one is ringed.
  component AccentPicker: Flow {
    id: picker
    spacing: root.sp(5)

    Repeater {
      model: accentSource.available

      Rectangle {
        id: swatch
        required property string modelData
        readonly property bool chosen: root.accentChoice === modelData
        readonly property bool isTheme: modelData === "theme"
        width: isTheme ? themeLabel.implicitWidth + root.sp(30) : root.sp(23)
        height: root.sp(23)
        radius: height / 2
        color: isTheme ? Util.alpha(root.bar.foreground, 0.06) : accentSource.colorOf(modelData)
        border.width: chosen ? 2 : 1
        border.color: chosen ? root.bar.foreground : Util.alpha(root.bar.foreground, isTheme ? 0.25 : 0.15)

        // The theme entry is a pill with a dot in the theme's own accent.
        Rectangle {
          visible: swatch.isTheme
          anchors.left: parent.left
          anchors.leftMargin: root.sp(7)
          anchors.verticalCenter: parent.verticalCenter
          width: root.sp(11)
          height: width
          radius: width / 2
          color: Color.accent
        }

        Text {
          id: themeLabel
          visible: swatch.isTheme
          anchors.right: parent.right
          anchors.rightMargin: root.sp(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Theme"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: root.fontCaption
          font.bold: swatch.chosen
        }

        MouseArea {
          id: swatchMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.setSetting("accent", swatch.modelData)
        }

        PanelToolTip {
          visible: swatchMouse.containsMouse
          text: swatch.isTheme ? "Theme accent" : swatch.modelData.charAt(0).toUpperCase() + swatch.modelData.slice(1)
          fontFamily: root.bar.fontFamily
        }
      }
    }
  }
}
