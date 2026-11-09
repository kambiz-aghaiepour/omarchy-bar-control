import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Control panel for Bar Control. Tabs:
//   Plugins — enable/disable/install glassy.bar and Bar Autohide
//   Glassy  — every ~/.config/glassy.bar/config.json key, applied on change
//   Autohide — hideDelayMs + detached shell restart (needed to apply it)
//   Layout  — reorder any bar entry via scripts/barctl-layout (omarchy bar move)
// Data comes from the barctl scripts through hostWidget.run(); the panel
// holds no state of its own beyond the last read values.
Panel {
  id: root

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget ? hostWidget : root

  readonly property color fg: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color dim: Qt.alpha(fg, 0.55)
  readonly property color accent: Color.accent

  // Loaded state
  property string glassyState: "?"
  property string autohideState: "?"
    property var g: ({})
  property int autohideMs: 200
  property var layoutRows: []
  property int revision: 0

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }
  function status() { return root.opened ? "open" : "closed" }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  property string tab: "plugins"
  readonly property var tabNames: [["plugins", "Plugins"], ["glassy", "Glassy"], ["autohide", "Autohide"], ["layout", "Layout"]]

  // Palette for the glassy color rows; lastCustom remembers the last picked
  // hex per key so unchecking "theme default" restores it.
  readonly property var palette: [
    "#1e1e2e", "#181825", "#11111b", "#313244", "#585b70",
    "#cdd6f4", "#bac2de", "#a6adc8", "#f5e0dc", "#f9e2af",
    "#a6e3a1", "#94e2d5", "#89dceb", "#74c7ec", "#89b4fa",
    "#b4befe", "#f38ba8", "#eba0ac", "#fab387", "#ffd580"
  ]
  property var lastCustom: ({})
  // Loader refs for the revision-recreate; ids are not reliably visible
  // from root-scope signal handlers, so the panes register themselves.
  property var glassyPaneRef: null
  property var autohidePaneRef: null

  function refresh() {
    hostWidget.run(hostWidget.script("barctl-plugins"), ["status"], null, function(code, out) {
      var m = {}
      var lines = out.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var parts = lines[i].split(" ")
        if (parts.length === 2 && parts[0] !== "") m[parts[0]] = parts[1]
      }
      glassyState = m.glassy || "absent"
      autohideState = m.autohide || "absent"
      hostWidget.run(hostWidget.script("barctl-glassy"), ["get"], null, function(code2, out2) {
        var gg = {}
        var ls = out2.split("\n")
        for (var j = 0; j < ls.length; j++) {
          var eq = ls[j].indexOf("=")
          if (eq > 0) gg[ls[j].slice(0, eq)] = ls[j].slice(eq + 1)
        }
        g = gg
        hostWidget.run(hostWidget.script("barctl-autohide"), ["get"], null, function(code3, out3) {
          var v = parseInt(out3.trim(), 10)
          autohideMs = v >= 0 && v <= 5000 ? v : 200
          loadLayout(function() { revision++ })
          hostWidget.statusLine = "ok"
        })
      })
    })
  }

  function loadLayout(after) {
    hostWidget.run(hostWidget.script("barctl-layout"), ["list"], null, function(code, out) {
      var rows = []
      var ls = out.split("\n")
      for (var i = 0; i < ls.length; i++) {
        var p = ls[i].split("|")
        if (p.length === 3 && p[2] !== "") rows.push({ sec: p[0], idx: parseInt(p[1], 10), id: p[2] })
      }
      layoutRows = rows
      if (after) after()
    })
  }

  function setGlassy(key, value) {
    var n = {}
    for (var k in g) n[k] = g[k]
    n[key] = String(value)
    g = n
    hostWidget.run(hostWidget.script("barctl-glassy"), ["set", key, String(value)], null, function(code, out) {
      if (code !== 0) { hostWidget.actionNote = "glassy set failed: " + key; return }
      hostWidget.actionNote = "glassy " + key + " = " + value + "  (applied live)"
      hostWidget.run(hostWidget.script("barctl-glassy"), ["get"], null, function(code2, out2) {
        var gg = {}
        var ls = out2.split("\n")
        for (var j = 0; j < ls.length; j++) {
          var eq = ls[j].indexOf("=")
          if (eq > 0) gg[ls[j].slice(0, eq)] = ls[j].slice(eq + 1)
        }
        g = gg
        revision++
      })
    })
  }

  function setAutohide(v) {
    if (!(v >= 0 && v <= 5000)) return
    hostWidget.run(hostWidget.script("barctl-autohide"), ["set", String(Math.round(v))], null, function(code) {
      hostWidget.actionNote = code === 0 ? "hideDelayMs saved (restart shell to apply)" : "autohide set failed"
    })
  }

  function moveEntry(id, dir) {
    hostWidget.run(hostWidget.script("barctl-layout"), ["move", id, dir], null, function(code, out) {
      if (code !== 0) { hostWidget.actionNote = "move failed"; loadLayout(null); return }
      var rows = []
      var ls = out.split("\n")
      for (var i = 0; i < ls.length; i++) {
        var p = ls[i].split("|")
        if (p.length === 3 && p[2] !== "") rows.push({ sec: p[0], idx: parseInt(p[1], 10), id: p[2] })
      }
      layoutRows = rows
    })
  }

  function restartShell() {
    hostWidget.run(hostWidget.script("barctl-restart-shell"), [], null, function(code) {
      hostWidget.actionNote = code === 0 ? "shell restarting…" : "restart failed"
    })
  }

  function gv(key, fallback) {
    var v = g[key]
    return (v === undefined || v === "") ? fallback : v
  }
  function gn(key, fallback) {
    var v = parseFloat(g[key])
    return isNaN(v) ? fallback : v
  }
  function gb(key, fallback) {
    var v = g[key]
    return v === undefined || v === "" ? fallback : v === "true"
  }

  component Tab: Rectangle {
    id: tabRoot
    property string label: ""
    property string key: ""
    width: tabLabel.implicitWidth + 20
    height: 24
    radius: 5
    color: root.tab === key ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25)
                            : (mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05))
    border.width: 1
    border.color: root.tab === key ? Color.accent : Qt.rgba(1, 1, 1, 0.12)
    Text {
      id: tabLabel
      anchors.centerIn: parent
      text: parent.label
      color: root.tab === parent.key ? root.fg : root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.tab = tabRoot.key
    }
  }

  component Header: Text {
    property string label: ""
    text: label
    width: parent ? parent.width : 0
    color: root.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  component FieldRow: Row {
    property string label: ""
    spacing: Style.space(8)
    width: parent ? parent.width : 0

    Text {
      width: 150
      text: parent.label
      anchors.verticalCenter: parent.verticalCenter
      color: root.fg
      elide: Text.ElideRight
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  component Mini: Rectangle {
    id: miniRoot
    property string glyph: ""
    property var action: null
    property bool enabled2: true
    width: 22
    height: 20
    radius: 4
    color: m.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.14)
    opacity: enabled2 ? 1 : 0.4
    Text {
      anchors.centerIn: parent
      text: miniRoot.glyph
      color: root.fg
      font.pixelSize: 11
      font.family: Style.font.family
    }
    MouseArea {
      id: m
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (miniRoot.enabled2 && miniRoot.action) miniRoot.action()
    }
  }

  component Act: Rectangle {
    id: actRoot
    property string label: ""
    property var action: null
    property bool danger: false
    width: actLabel.implicitWidth + 20
    height: 24
    radius: 5
    color: press.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
    border.width: 1
    border.color: danger ? Qt.rgba(1, 0.6, 0.4, 0.5) : Qt.rgba(1, 1, 1, 0.14)
    Text {
      id: actLabel
      anchors.centerIn: parent
      text: actRoot.label
      color: root.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    MouseArea {
      id: press
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (actRoot.action) actRoot.action()
    }
  }

  component MiniCheck: Rectangle {
    id: checkRoot
    property bool on: false
    width: 13; height: 13; radius: 3
    color: on ? root.accent : "transparent"
    border.width: 1; border.color: root.accent
    Text {
      visible: checkRoot.on
      anchors.centerIn: parent
      text: "✓"; color: "#11111b"; font.pixelSize: 9; font.bold: true
      font.family: Style.font.family
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: if (checkRoot.action) checkRoot.action()
    }
    property var action: null
  }

  // One color setting: current swatch + hex, theme-default check, palette.
  component ColorRow: Column {
    id: crow
    property string ckey: ""
    property string clabel: ""
    width: parent ? parent.width : 0
    spacing: Style.space(4)

    readonly property string cur: root.gv(ckey, "")

    Row {
      spacing: Style.space(6)
      Text {
        width: 140
        text: crow.clabel
        anchors.verticalCenter: parent.verticalCenter
        color: root.fg
        elide: Text.ElideRight
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
      Rectangle {
        width: 14; height: 14; radius: 3
        anchors.verticalCenter: parent.verticalCenter
        color: crow.cur === "" ? "transparent" : crow.cur
        border.width: 1; border.color: root.fg
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: 86; elide: Text.ElideRight
        text: crow.cur
        color: root.dim; font.pixelSize: 10; font.family: Style.font.family
      }
      MiniCheck {
        anchors.verticalCenter: parent.verticalCenter
        on: crow.cur === ""
        action: function() {
          if (crow.cur !== "") {
            var n = {}
            for (var k in root.lastCustom) n[k] = root.lastCustom[k]
            n[crow.ckey] = crow.cur
            root.lastCustom = n
            root.setGlassy(crow.ckey, "")
          } else {
            var lc = root.lastCustom[crow.ckey]
            if (lc) root.setGlassy(crow.ckey, lc)
          }
        }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "theme default"
        color: root.dim; font.pixelSize: 10; font.family: Style.font.family
      }
    }

    Flow {
      width: parent.width
      spacing: 4
      Repeater {
        model: root.palette
        Rectangle {
          width: 16; height: 16; radius: 3
          color: modelData
          border.width: modelData === crow.cur ? 2 : 1
          border.color: modelData === crow.cur ? root.accent : Qt.rgba(1, 1, 1, 0.25)
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var n = {}
              for (var k in root.lastCustom) n[k] = root.lastCustom[k]
              n[crow.ckey] = modelData
              root.lastCustom = n
              root.setGlassy(crow.ckey, modelData)
            }
          }
        }
      }
    }
  }

  component StateDot: Rectangle {
    property string state: ""
    width: 8; height: 8; radius: 4
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    color: state === "active" ? Color.accent
      : state === "enabled" ? "#7dcfff"
      : state === "disabled" ? "#e0af68"
      : "#565f89"
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: contentColumn.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(8)

        Item { width: 1; height: Style.space(2) }

        Row {
          width: parent.width
          spacing: Style.space(6)
          Text {
            text: "Bar Control"
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
          Item { width: 1; height: 1 }
          Repeater {
            model: root.tabNames
            Tab { label: modelData[1]; key: modelData[0] }
          }
        }

        Text {
          width: parent.width
          text: hostWidget ? hostWidget.actionNote : ""
                          + ""
          visible: hostWidget && hostWidget.actionNote !== ""
          color: root.dim
          wrapMode: Text.WordWrap
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        // ---- Plugins tab

        Column {
          width: parent.width
          visible: root.tab === "plugins"
          spacing: Style.space(8)

          Column {
            width: parent.width
            spacing: Style.space(4)
            Row {
              spacing: Style.space(6)
              StateDot { state: root.glassyState; anchors.verticalCenter: parent.verticalCenter }
              Text { text: "Glassy Bar (glassy.bar)"; color: root.fg; font.pixelSize: Style.font.body; font.family: Style.font.family }
            }
            Text {
              width: parent.width
              text: {
                var s = "state: " + root.glassyState
                return s
              }
              color: root.dim; font.pixelSize: Style.font.caption; font.family: Style.font.family
            }
            Toggle {
              width: parent.width
              label: "Enabled"
              description: "Off = unloaded (settings kept); the stock bar returns while Glassy is off"
              visible: root.glassyState !== "absent"
              checked: root.glassyState === "enabled" || root.glassyState === "active"
              onClicked: {
                var enabling = !(root.glassyState === "enabled" || root.glassyState === "active")
                hostWidget.pluginAction(enabling ? "enable" : "disable", "glassy")
              }
            }

            Row {
              spacing: Style.space(6)
              Act {
                label: "Remove"
                visible: root.glassyState !== "absent"
                danger: true
                action: function() { root.hostWidget.pluginAction("remove", "glassy") }
              }
            }
          }

          Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

          Column {
            width: parent.width
            spacing: Style.space(4)
            Row {
              spacing: Style.space(6)
              StateDot { state: root.autohideState; anchors.verticalCenter: parent.verticalCenter }
              Text { text: "Bar Autohide (ericvrp.bar-autohide)"; color: root.fg; font.pixelSize: Style.font.body; font.family: Style.font.family }
            }
            Toggle {
              width: parent.width
              label: "Enabled"
              description: "Off = unloaded (settings kept)"
              visible: root.autohideState !== "absent"
              checked: root.autohideState === "enabled" || root.autohideState === "active"
              onClicked: {
                var enabling = !(root.autohideState === "enabled" || root.autohideState === "active")
                hostWidget.pluginAction(enabling ? "enable" : "disable", "autohide")
              }
            }

            Row {
              spacing: Style.space(6)
              Act {
                label: "Remove"
                visible: root.autohideState !== "absent"
                danger: true
                action: function() { hostWidget.pluginAction("remove", "autohide") }
              }
              Act {
                label: "Install"
                visible: root.autohideState === "absent"
                action: function() { hostWidget.pluginAction("install", "autohide") }
              }
            }
          }

          Text {
            width: parent.width
            text: "Disable keeps the plugin installed (state is preserved; re-enable anytime). Remove uninstalls it — for Glassy that hands the bar back to stock omarchy.bar; re-install brings your settings back."
            color: root.dim
            wrapMode: Text.WordWrap
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        // ---- Glassy tab

        Column {
          width: parent.width
          visible: root.tab === "glassy"
          spacing: Style.space(6)

            Loader {
              id: glassyPane
              width: parent.width
              Component.onCompleted: root.glassyPaneRef = glassyPane
              sourceComponent: root.revision > 0 ? glassyPaneComp : undefined
            }
        }

        Component {
          id: glassyPaneComp
          Column {
            width: glassyPane.width
            spacing: Style.space(6)
          Header { label: "Geometry" }

          FieldRow {
            label: "Position"
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.gv("position", "") === "" ? "theme" : root.gv("position", "")
              color: root.fg; font.pixelSize: Style.font.caption; font.family: Style.font.family
              width: 60
            }
            Act {
              anchors.verticalCenter: parent.verticalCenter
              label: "cycle"
              action: function() {
                var opts = ["", "top", "right", "bottom", "left"]
                var cur = root.gv("position", "")
                var i = (opts.indexOf(cur) + 1) % opts.length
                root.setGlassy("position", opts[i])
              }
            }
          }

          FieldRow {
            label: "Width (full | px | %)"
            TextField {
              anchors.verticalCenter: parent.verticalCenter
              id: widthField
              width: 90
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              text: root.gv("width", "full")
              onVisibleChanged: if (visible) text = root.gv("width", "full")
              onAccepted: root.setGlassy("width", text.trim())
            }
          }

          FieldRow {
            label: "Margin edge (px)"
            NumberField {
              anchors.verticalCenter: parent.verticalCenter
              fieldWidth: 72
              from: 0; to: 64; stepSize: 1
              value: root.gn("margin_edge", 8)
              onModified: function(v) { root.setGlassy("margin_edge", v) }
            }
          }

          FieldRow {
            label: "Margin sides (px)"
            NumberField {
              anchors.verticalCenter: parent.verticalCenter
              fieldWidth: 72
              from: 0; to: 64; stepSize: 1
              value: root.gn("margin_sides", 8)
              onModified: function(v) { root.setGlassy("margin_sides", v) }
            }
          }

          FieldRow {
            label: "Padding"
            NumberField {
              id: paddingF
              anchors.verticalCenter: parent.verticalCenter
              fieldWidth: 72
              from: 0; to: 64; stepSize: 1
              value: root.gn("padding", 8)
              onModified: function(v) { root.setGlassy("padding", v) }
            }
          }

          FieldRow {
            label: "Corner radius"
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: 60
              text: root.gv("radius", "pill")
              color: root.fg; font.pixelSize: Style.font.caption; font.family: Style.font.family
            }
            Act {
              anchors.verticalCenter: parent.verticalCenter
              label: "cycle"
              action: function() {
                var opts = ["pill", 0, 4, 8, 12, 16, 24]
                var cur = root.gv("radius", "pill")
                var curStr = String(cur)
                var i = 0
                for (var k = 0; k < opts.length; k++) if (String(opts[k]) === curStr) { i = k; break }
                i = (i + 1) % opts.length
                root.setGlassy("radius", opts[i])
              }
            }
          }

          Header { label: "Colors & transparency" }

          FieldRow {
            label: "Background opacity (%)"
            NumberField {
              id: opacityF
              anchors.verticalCenter: parent.verticalCenter
              fieldWidth: 72
              from: 0; to: 100; stepSize: 5
              value: Math.round(root.gn("opacity", 0) * 100)
              onModified: function(v) { root.setGlassy("opacity", v / 100) }
            }
          }

          ColorRow { ckey: "background"; clabel: "Background color" }

          ColorRow { ckey: "foreground"; clabel: "Foreground (text/icons)" }

          Header { label: "Effects" }

          Toggle {
            width: parent.width
            label: "Blur behind the bar"
            checked: root.gb("blur", false)
            onClicked: root.setGlassy("blur", !root.gb("blur", false))
          }
          Toggle {
            width: parent.width
            label: "Split per section"
            checked: root.gb("split", false)
            onClicked: root.setGlassy("split", !root.gb("split", false))
          }

          FieldRow {
            label: "Border width (px)"
            NumberField {
              anchors.verticalCenter: parent.verticalCenter
              fieldWidth: 72
              from: 0; to: 8; stepSize: 1
              value: root.gn("border_width", 1)
              onModified: function(v) { root.setGlassy("border_width", v) }
            }
          }

          FieldRow {
            label: "Border opacity (%)"
            NumberField {
              anchors.verticalCenter: parent.verticalCenter
              fieldWidth: 72
              from: 0; to: 100; stepSize: 5
              value: Math.round(root.gn("border_opacity", 0.3) * 100)
              onModified: function(v) { root.setGlassy("border_opacity", v / 100) }
            }
          }

          FieldRow {
            label: "Shadow depth (px)"
            NumberField {
              anchors.verticalCenter: parent.verticalCenter
              fieldWidth: 72
              from: 0; to: 64; stepSize: 1
              value: root.gn("shadow_depth", 10)
              onModified: function(v) { root.setGlassy("shadow_depth", v) }
            }
          }

          FieldRow {
            label: "Shadow opacity (%)"
            NumberField {
              anchors.verticalCenter: parent.verticalCenter
              fieldWidth: 72
              from: 0; to: 100; stepSize: 5
              value: Math.round(root.gn("shadow_opacity", 0.9) * 100)
              onModified: function(v) { root.setGlassy("shadow_opacity", v / 100) }
            }
          }

          FieldRow {
            label: "Shadow tint (%)"
            NumberField {
              anchors.verticalCenter: parent.verticalCenter
              fieldWidth: 72
              from: 0; to: 100; stepSize: 5
              value: Math.round(root.gn("shadow_tint", 0.22) * 100)
              onModified: function(v) { root.setGlassy("shadow_tint", v / 100) }
            }
          }

          Row {
            spacing: Style.space(6)
            Act {
              label: "Reload from disk"
              action: function() { root.refresh() }
            }
          }

          Text {
            width: parent.width
            text: "Every change writes ~/.config/glassy.bar/config.json and the bar applies it live — no save or restart needed. Percent fields are 0–100 (50 = 0.50). Colors: click a swatch; theme default restores the theme."
            color: root.dim; wrapMode: Text.WordWrap
            font.family: Style.font.family; font.pixelSize: Style.font.caption
          }          }
        }

        // ---- Autohide tab

        Column {
          width: parent.width
          visible: root.tab === "autohide"
          spacing: Style.space(8)

            Loader {
              id: autohidePane
              width: parent.width
              Component.onCompleted: root.autohidePaneRef = autohidePane
              sourceComponent: root.revision > 0 ? autohidePaneComp : undefined
            }
        }

        Component {
          id: autohidePaneComp
          Column {
            width: autohidePane.width
            spacing: Style.space(8)
          Row {
            spacing: Style.space(6)
            StateDot { state: root.autohideState; anchors.verticalCenter: parent.verticalCenter }
            Text {
              text: "plugin: " + root.autohideState
              color: root.dim; font.pixelSize: Style.font.caption; font.family: Style.font.family
              anchors.verticalCenter: parent.verticalCenter
            }
            Act {
              anchors.verticalCenter: parent.verticalCenter
              label: root.autohideState === "disabled" ? "Enable" : "Disable"
              visible: root.autohideState !== "absent"
              action: function() {
                var enabling = root.autohideState === "disabled"
                hostWidget.pluginAction(enabling ? "enable" : "disable", "autohide")
              }
            }
          }

          FieldRow {
            label: "Hide delay (ms, 0–5000)"
            NumberField {
              anchors.verticalCenter: parent.verticalCenter
              fieldWidth: 84
              from: 0; to: 5000; stepSize: 50
              value: root.autohideMs
              onModified: function(v) { root.setAutohide(v) }
            }
          }

          Text {
            width: parent.width
            text: "Written to the ericvrp.bar-autohide entry in shell.json. The delay applies after a shell restart."
            color: root.dim; wrapMode: Text.WordWrap
            font.family: Style.font.family; font.pixelSize: Style.font.caption
          }

          Act { label: "Restart shell now"; action: function() { root.restartShell() } }

          Text {
            width: parent.width
            text: "The restart is detached; this panel closes with the shell and the bar returns in ~2 s."
            color: root.dim; wrapMode: Text.WordWrap
            font.family: Style.font.family; font.pixelSize: Style.font.caption
          }          }
        }

        // ---- Layout tab

        Column {
          width: parent.width
          visible: root.tab === "layout"
          spacing: Style.space(3)

          Text {
            width: parent.width
            text: "◀ previous section · ▶ next section · ▲▼ reorder within section. Changes apply live via omarchy bar move."
            color: root.dim; wrapMode: Text.WordWrap
            font.family: Style.font.family; font.pixelSize: Style.font.caption
          }

          Repeater {
            model: root.layoutRows
            delegate: Row {
              required property var modelData
              width: parent.width
              spacing: Style.space(4)

              Rectangle {
                width: (modelData.idx === 0) ? 90 : 0
                height: 1
                color: "transparent"
              }

              Text {
                visible: modelData.idx === 0
                width: 74
                text: modelData.sec
                color: root.accent
                font.pixelSize: 10
                font.bold: true
                font.family: Style.font.family
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                width: 150
                text: modelData.id
                color: root.fg
                elide: Text.ElideMiddle
                font.pixelSize: 11
                font.family: Style.font.family
                anchors.verticalCenter: parent.verticalCenter
              }

              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Mini {
                  glyph: "▲"; enabled2: modelData.idx > 0
                  action: function() { root.moveEntry(modelData.id, "up") }
                }
                Mini {
                  glyph: "▼"
                  enabled2: modelData.idx < (root.sectionCount(modelData.sec) - 1)
                  action: function() { root.moveEntry(modelData.id, "down") }
                }
                Mini {
                  glyph: "◀"
                  action: function() { root.moveEntry(modelData.id, "left") }
                }
                Mini {
                  glyph: "▶"
                  action: function() { root.moveEntry(modelData.id, "right") }
                }
              }
            }
          }
        }

        Item { width: 1; height: Style.space(2) }
      }
    }
  }

  // Field internals don't follow external value/text changes, and programmatic
  // writes would re-trigger onModified -> setGlassy. Instead, recreate the two
  // field-bearing panes on every revision bump (end of each refresh): fresh
  // bindings evaluate against the loaded config.
  Connections {
    target: root
    function onRevisionChanged() {
      if (root.revision <= 0) return
      var gp = root.glassyPaneRef
      if (gp && gp.sourceComponent) {
        var g = gp.sourceComponent
        gp.sourceComponent = undefined
        gp.sourceComponent = g
      }
      var ap = root.autohidePaneRef
      if (ap && ap.sourceComponent) {
        var a = ap.sourceComponent
        ap.sourceComponent = undefined
        ap.sourceComponent = a
      }
    }
  }

  function sectionCount(sec) {
    var n = 0
    for (var i = 0; i < layoutRows.length; i++) if (layoutRows[i].sec === sec) n++
    return n
  }

  onOpenedChanged: if (opened && hostWidget) { hostWidget.actionNote = ""; refresh() }
}
