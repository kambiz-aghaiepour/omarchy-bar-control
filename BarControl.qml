import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar Control: one icon, one panel over the whole bar stack.
//
// Tabs: Plugins (enable/install glassy.bar + Bar Autohide), Glassy (every
// key of ~/.config/glassy.bar/config.json, applied live), Autohide (hide
// delay + detached shell restart), Layout (reorder any entry via the stock
// `omarchy bar move` plumbing). All mutations run through scripts/barctl-*
// so they are testable without the shell.
BarWidget {
  id: root
  moduleName: "io.github.kambiz.bar-control"

  property string statusLine: "idle"
  property string actionNote: ""
  readonly property bool busy: runner.running

  function script(name) {
    var url = Qt.resolvedUrl("scripts/" + name).toString()
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.slice(7)) : url
  }

  // Run a barctl script; every stdout line hits onLine, completion onDone.
  // A call while busy is queued (one deep), never dropped.
  property var queuedRun: null
  function run(exe, args, onLine, onDone) {
    if (root.busy) {
      queuedRun = [exe, args, onLine, onDone]
      return
    }
    runnerCmd = ["bash", "-c", 'exec "$@"', "bash", exe].concat(args || [])
    runnerOnLine = onLine
    runnerOnDone = onDone
    runnerOut = ""
    runner.running = true
  }

  property var runnerCmd: []
  property var runnerOnLine: null
  property var runnerOnDone: null
  property string runnerOut: ""

  Process {
    id: runner
    command: root.runnerCmd
    stdout: SplitParser {
      onRead: function(line) {
        root.runnerOut += line + "\n"
        if (root.runnerOnLine) root.runnerOnLine(String(line).trim())
      }
    }
    onExited: function(exitCode) {
      var cb = root.runnerOnDone
      root.runnerOnLine = null
      root.runnerOnDone = null
      if (cb) cb(exitCode, root.runnerOut)
      if (root.queuedRun) {
        var q = root.queuedRun
        root.queuedRun = null
        root.run(q[0], q[1], q[2], q[3])
      }
    }
  }

  function pluginAction(action, which, done) {
    // Optimistic: flip the label now; the refresh confirms.
    var post = action === "enable" || action === "install" ? "enabled"
      : action === "disable" ? "disabled" : "absent"
    var panel = panelLoader.item
    if (panel) {
      if (which === "glassy") panel.glassyState = post
      else if (which === "autohide") panel.autohideState = post
    }
    root.actionNote = "…"
    run(script("barctl-plugins"), [action, which || ""], null, function(code, out) {
      root.actionNote = code === 0 ? "ok" : "failed (" + action + ")"
      root.panelRefresh()
      if (done) done(code, out)
    })
  }

  function panelRefresh() {
    if (panelLoader.item && "refresh" in panelLoader.item) panelLoader.item.refresh()
  }

  // ---- Control panel (Panel.qml).

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true : false

  function openPanel() { if (panelLoader.item) panelLoader.item.open() }
  function closePanel() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function open() { openPanel() }
  function close() { closePanel() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.anchorItem = root
    target.hostWidget = root
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  onBarChanged: injectPanel()

  Component.onCompleted: panelRefresh()

  // ---- The widget.

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: String.fromCodePoint(0xF013)
    active: root.opened
    tooltipText: "Bar Control — plugins, glassy/autohide settings, layout order; click to open"
    onPressed: function(mouseButton) { root.togglePanel() }
  }

  // ---- Remote control: omarchy-shell io.github.kambiz.bar-control <method>

  ShellIpc {
    target: "io.github.kambiz.bar-control"
    function open(): void { root.openPanel() }
    function close(): void { root.closePanel() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.panelRefresh() }
    function status(): string { return root.statusLine }
  }
}
