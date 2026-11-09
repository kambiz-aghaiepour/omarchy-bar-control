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

  function flushQueued() {
    if (!root.queuedRun || root.busy) return
    var q = root.queuedRun
    root.queuedRun = null
    root.run(q[0], q[1], q[2], q[3])
  }

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
      // running is still true inside onExited; flush the queue next event loop pass
      if (root.queuedRun) Qt.callLater(root.flushQueued)
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

  // A bar rebuild (any layout move) destroys this widget along with the
  // open panel. barctl-layout leaves a one-shot reopen note; the fresh
  // instance consumes it and reopens the panel on the same tab, so
  // rearranging widgets doesn't kick the user out of the panel.
  property string reopenTab: ""
  property var reopenStamp: 0

  Process {
    id: reopenProc
    command: ["bash", "-c", 'exec "$@"', "bash", root.script("barctl-layout"), "take"]
    stdout: SplitParser {
      onRead: function(line) {
        var s = String(line).trim()
        if (s === "") return
        if (root.reopenTab === "") root.reopenTab = s
        else if (!root.reopenStamp) root.reopenStamp = parseFloat(s) || 0
      }
    }
    onExited: function() {
      var age = root.reopenStamp > 0 ? Date.now() / 1000 - root.reopenStamp : 999
      if (root.reopenTab !== "" && age >= 0 && age < 20) reopenTimer.restart()
      else root.reopenTab = ""
    }
  }

  Timer {
    id: reopenTimer
    interval: 450
    onTriggered: {
      root.openPanel()
      var panel = panelLoader.item
      if (panel && "tab" in panel) panel.tab = root.reopenTab
      root.reopenTab = ""
    }
  }

  Component.onCompleted: { panelRefresh(); reopenProc.running = true }

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
    function tab(name: string): void {
      if (panelLoader.item && "tab" in panelLoader.item) panelLoader.item.tab = name
    }
    function status(): string { return root.statusLine }
  }
}
