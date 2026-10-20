pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
    id: root
    moduleName: "videinfra.omarchy-effects"
    ipcTarget: "videinfra.omarchy-effects"
    implicitWidth: barButton.implicitWidth
    implicitHeight: barButton.implicitHeight

    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("bin/omarchy-effects").toString().replace(/^file:\/\//, ""))
    readonly property color accent: Commons.Color.accent
    property bool pEnabled: false
    property string pEffect: "crumble"
    property int pDuration: 450
    property string pSize: "medium"
    property var saved: ({ enabled: false, effect: "crumble", duration: 450, size: "medium" })
    property bool ready: false
    property bool loaded: false
    property bool busy: false
    property string errorText: ""
    property string backendText: "Checking backend…"
    readonly property var effects: [
        { key: "crumble", title: "Crumble", glyph: "\u25a6", detail: "Small pieces fall away and fade." },
        { key: "shatter", title: "Shatter", glyph: "\u2726", detail: "Fragments scatter outward and turn." },
        { key: "dissolve", title: "Dissolve", glyph: "\u22ef", detail: "Fine blocks dissolve in a noise pattern." },
        { key: "pixelate", title: "Pixelate", glyph: "\u25a6", detail: "Growing blocks fade into the desktop." },
        { key: "default", title: "Default", glyph: "\u2212", detail: "Use your existing Omarchy closing animation." }
    ]
    readonly property bool dirty: pEnabled !== saved.enabled || pEffect !== saved.effect
        || pDuration !== saved.duration || pSize !== saved.size
    readonly property bool canApply: loaded && dirty && !busy && !reader.running
        && (!pEnabled || pEffect === "default" || ready)

    function staged() { return { enabled: pEnabled, effect: pEffect, duration: pDuration, size: pSize } }
    function stage(s) { pEnabled = s.enabled; pEffect = s.effect; pDuration = s.duration; pSize = s.size }
    function reload() { if (!reader.running) reader.running = true }
    function apply() {
        if (!canApply) return
        busy = true
        errorText = ""
        writer.command = [helper, "apply", JSON.stringify(staged())]
        writer.running = true
    }
    function selectEffect(delta) {
        var index = effects.findIndex(function(e) { return e.key === pEffect })
        pEffect = effects[(index + delta + effects.length) % effects.length].key
    }
    function description() {
        for (var i = 0; i < effects.length; i++) if (effects[i].key === pEffect) return effects[i].detail
        return ""
    }
    onOpenedChanged: if (opened) { errorText = ""; reload() }

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
                    root.loaded = true
                    root.backendText = !result.installed ? "Run install.sh to finish setup"
                        : result.version !== "0.56.2" ? "Requires Hyprland 0.56.2"
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

    Ui.BarIconButton {
        id: barButton
        anchors.fill: parent
        bar: root.bar
        iconComponent: Component {
            Item {
                Text {
                    anchors.centerIn: parent
                    text: "\u25a6"
                    color: root.barForeground
                    font.family: Commons.Style.font.family
                    font.pixelSize: Commons.Style.font.body
                }
            }
        }
        tooltipText: "omarchy-effects · window closing effects"
        onPressed: function(b) { root.toggle() }
    }

    Ui.KeyboardPanel {
        id: popup
        anchorItem: barButton
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        padding: Commons.Style.space(12)
        contentWidth: popup.fittedContentWidth(Commons.Style.space(324))
        contentHeight: popup.fittedContentHeight(body.implicitHeight)

        Ui.PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onActivateRequested: root.apply()
            onMoveRequested: function(dx, dy) { if (!root.busy && root.loaded) root.selectEffect(dy !== 0 ? dy : dx) }
            onTabRequested: function(direction) { root.switchPanel(direction) }

            Column {
                id: body
                width: parent.width
                spacing: Commons.Style.space(12)

                Row {
                    width: parent.width
                    spacing: Commons.Style.space(10)
                    Text {
                        text: "\u25a6"
                        color: root.accent
                        font.family: Commons.Style.font.family
                        font.pixelSize: Commons.Style.font.title
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Column {
                        width: parent.width - Commons.Style.space(90)
                        spacing: Commons.Style.space(3)
                        Label { text: "omarchy-effects"; font.bold: true; font.pixelSize: Commons.Style.font.title }
                        Label { text: "WINDOW CLOSING · v0.1.0"; opacity: 0.5; font.pixelSize: Commons.Style.font.caption }
                    }
                    Choice {
                        width: Commons.Style.space(48)
                        height: Commons.Style.space(28)
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.pEnabled ? "ON" : "OFF"
                        selected: root.pEnabled
                        enabled: root.loaded && !root.busy && (root.ready || root.pEnabled || root.pEffect === "default")
                        onClicked: root.pEnabled = !root.pEnabled
                    }
                }
                Rule {}
                Section { text: "CLOSE EFFECT"; hint: root.dirty ? "UNSAVED" : "" }
                Grid {
                    width: parent.width
                    columns: 2
                    spacing: Commons.Style.space(6)
                    enabled: root.loaded && !root.busy && !reader.running
                    Repeater {
                        model: root.effects.slice(0, 4)
                        delegate: Choice {
                            required property var modelData
                            width: (parent.width - Commons.Style.space(6)) / 2
                            height: Commons.Style.space(52)
                            text: modelData.glyph + "  " + modelData.title
                            selected: root.pEffect === modelData.key
                            onClicked: root.pEffect = modelData.key
                        }
                    }
                }
                Choice {
                    width: parent.width
                    text: "\u2212  Default Omarchy animation"
                    selected: root.pEffect === "default"
                    enabled: root.loaded && !root.busy && !reader.running
                    onClicked: root.pEffect = "default"
                }
                Label {
                    width: parent.width
                    text: root.description()
                    wrapMode: Text.WordWrap
                    opacity: 0.6
                    font.pixelSize: Commons.Style.font.caption
                }
                Rule {}
                Section { text: "DURATION"; hint: root.pDuration + " ms" }
                Row {
                    width: parent.width
                    spacing: Commons.Style.space(6)
                    enabled: root.loaded && !root.busy && root.pEffect !== "default"
                    Choice { width: Commons.Style.space(32); text: "−"; enabled: root.pDuration > 150; onClicked: root.pDuration = Math.max(150, root.pDuration - 50) }
                    Repeater {
                        model: [250, 450, 750]
                        delegate: Choice {
                            required property int modelData
                            width: (parent.width - Commons.Style.space(88)) / 3
                            text: modelData + ""
                            selected: root.pDuration === modelData
                            onClicked: root.pDuration = modelData
                        }
                    }
                    Choice { width: Commons.Style.space(32); text: "+"; enabled: root.pDuration < 1500; onClicked: root.pDuration = Math.min(1500, root.pDuration + 50) }
                }
                Section { text: "FRAGMENT SIZE" }
                Row {
                    width: parent.width
                    spacing: Commons.Style.space(6)
                    enabled: root.loaded && !root.busy && root.pEffect !== "default"
                    Repeater {
                        model: ["small", "medium", "large"]
                        delegate: Choice {
                            required property string modelData
                            width: (parent.width - Commons.Style.space(12)) / 3
                            text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                            selected: root.pSize === modelData
                            onClicked: root.pSize = modelData
                        }
                    }
                }
                Rule {}
                Row {
                    width: parent.width
                    spacing: Commons.Style.space(7)
                    Rectangle { width: Commons.Style.space(5); height: width; radius: width/2; color: root.ready ? root.accent : Commons.Color.popups.text; opacity: root.ready ? 1 : 0.4; anchors.verticalCenter: parent.verticalCenter }
                    Label { width: parent.width - Commons.Style.space(12); text: root.backendText; wrapMode: Text.WordWrap; opacity: 0.65; font.pixelSize: Commons.Style.font.caption }
                }
                Label {
                    width: parent.width
                    visible: root.errorText !== ""
                    text: root.errorText
                    wrapMode: Text.WrapAnywhere
                    font.pixelSize: Commons.Style.font.caption
                }
                Row {
                    width: parent.width
                    spacing: Commons.Style.space(6)
                    Choice {
                        width: (parent.width - Commons.Style.space(12)) / 3
                        text: "Test window"
                        enabled: root.loaded && !root.busy && !tester.running && !root.dirty
                        onClicked: { root.errorText = ""; tester.running = true }
                    }
                    Choice {
                        width: (parent.width - Commons.Style.space(12)) / 3
                        text: "Reset"
                        enabled: root.loaded && !root.busy
                        onClicked: root.stage({ enabled: false, effect: "crumble", duration: 450, size: "medium" })
                    }
                    Choice {
                        width: (parent.width - Commons.Style.space(12)) / 3
                        text: root.busy ? "Applying…" : "Apply"
                        selected: root.canApply
                        enabled: root.canApply
                        onClicked: root.apply()
                    }
                }
                Label {
                    width: parent.width
                    text: root.dirty ? "Apply changes before opening a test window." : "↑ ↓ choose  ·  Enter apply  ·  Esc close"
                    opacity: 0.4
                    font.pixelSize: Commons.Style.font.caption
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    component Label: Text {
        textFormat: Text.PlainText
        color: Commons.Color.popups.text
        font.family: Commons.Style.font.family
        font.pixelSize: Commons.Style.font.body
    }
    component Rule: Rectangle {
        width: parent.width
        height: 1
        color: Commons.Util.alpha(Commons.Color.popups.text, 0.12)
    }
    component Section: Item {
        property string text: ""
        property string hint: ""
        width: parent.width
        implicitHeight: heading.implicitHeight
        Label { id: heading; text: parent.text; font.pixelSize: Commons.Style.font.caption; font.bold: true; font.letterSpacing: 1 }
        Label { anchors.right: parent.right; text: parent.hint; color: root.accent; font.pixelSize: Commons.Style.font.caption }
    }
    component Choice: Rectangle {
        id: choice
        property string text: ""
        property bool selected: false
        signal clicked()
        height: Commons.Style.space(32)
        radius: Commons.Style.space(5)
        color: selected ? Commons.Util.alpha(root.accent, 0.13) : Commons.Util.alpha(Commons.Color.popups.text, hover.containsMouse ? 0.09 : 0.04)
        border.width: 1
        border.color: selected ? root.accent : Commons.Util.alpha(Commons.Color.popups.text, 0.13)
        opacity: enabled ? 1 : 0.38
        Accessible.role: Accessible.Button
        Accessible.name: text
        Accessible.onPressAction: if (enabled) clicked()
        Label {
            anchors.centerIn: parent
            width: parent.width - Commons.Style.space(8)
            horizontalAlignment: Text.AlignHCenter
            text: choice.text
            color: choice.selected ? root.accent : Commons.Color.popups.text
            font.pixelSize: Commons.Style.font.caption
            elide: Text.ElideRight
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: choice.clicked()
        }
    }
}
