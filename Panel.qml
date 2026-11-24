import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "aurora7795.librelinkup"
  ipcTarget: "aurora7795.librelinkup"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- data -------------------------------------------------------------
  property var report: null      // last good helper result
  property string error: ""
  property bool needsSetup: false
  property bool editingAccount: false
  property bool saving: false
  readonly property bool showForm: editingAccount || (report === null && needsSetup)
  // The unit picked in the popup (stored in config.json by the helper) wins
  // over the shell.json default.
  property string unitChoice: ""
  readonly property bool mmol: (unitChoice || String(setting("unit", "mgdl"))).toLowerCase() === "mmol"

  function toggleUnit() {
    unitChoice = mmol ? "mgdl" : "mmol"
    unitProc.command = ["python3", "-I", helperPath, "--unit", unitChoice]
    unitProc.running = false
    unitProc.running = true
  }

  Process { id: unitProc }
  readonly property int intervalSec: Math.max(60, Number(setting("intervalSec", 60)) || 60)
  readonly property var arrows: ["", "↓", "↘", "→", "↗", "↑"]

  function fmt(mgdl) {
    if (mgdl === null || mgdl === undefined) return "—"
    return root.mmol ? (mgdl / 18.0182).toFixed(1) : String(Math.round(mgdl))
  }
  function arrow(t) { return arrows[Math.max(1, Math.min(5, Number(t) || 3))] }
  function ageMinutes() {
    if (!report || !report.t) return -1
    return Math.max(0, Math.round((Date.now() / 1000 - report.t) / 60))
  }
  readonly property bool stale: report !== null && ageMinutes() > 15
  readonly property bool urgentReading: report !== null && (report.isHigh || report.isLow
    || report.mgdl < 70 || report.mgdl > 250)

  readonly property string label: {
    if (report) return fmt(report.mgdl) + " " + arrow(report.trend) + (stale ? " ?" : "")
    return error ? "⚠ glucose" : "…"
  }

  readonly property string helperPath: Qt.resolvedUrl("llu.py").toString().replace("file://", "")

  function refresh() {
    if (proc.running) return
    proc.command = ["python3", "-I", helperPath]
    proc.environment = ({})
    proc.running = true
  }

  // Credentials travel in the child's environment, never on the command line.
  function saveAccount(email, password) {
    if (proc.running) return
    root.saving = true
    root.error = ""
    proc.command = ["python3", "-I", helperPath, "--save"]
    proc.environment = ({ "LLU_EMAIL": email, "LLU_PASSWORD": password })
    proc.running = true
  }

  Process {
    id: proc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var r = JSON.parse(String(text || "").trim())
          if (r.ok) {
            root.report = r; root.error = ""; root.needsSetup = false
            if (r.unit && root.unitChoice === "") root.unitChoice = r.unit
            if (root.saving) root.editingAccount = false
          } else {
            root.error = String(r.error || "unknown error")
            root.needsSetup = r.setup === true
          }
        } catch (e) {
          root.error = "no response from helper"
        }
        root.saving = false
      }
    }
  }

  Timer {
    interval: root.intervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // ---- open/close (same contract as first-party panels) -------------------
  function open() { root.controller.show(); root.refresh() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      implicitHeight: col.implicitHeight
      anchors.fill: parent
      blocked: root.showForm
      onCloseRequested: root.close()
      onTextKey: function(t) { if (t === "r") root.refresh() }

      Column {
        id: col
        width: parent.width
        spacing: Style.space(12)

        Column {
          id: form
          visible: root.showForm
          x: Style.space(16)
          width: parent.width - Style.space(32)
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            text: "LibreLinkUp account"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            text: "Use the follower account that the Libre app shares with, not the sensor owner's login."
            color: Commons.Color.muted
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          TextField {
            id: emailField
            width: parent.width
            placeholderText: "Email"
            enabled: !root.saving
            onAccepted: passwordField.forceActiveFocus()
          }
          TextField {
            id: passwordField
            width: parent.width
            password: true
            placeholderText: "Password"
            enabled: !root.saving
            onAccepted: submitButton.clicked()
          }
          Row {
            spacing: Style.space(8)
            Button {
              id: submitButton
              text: root.saving ? "Signing in…" : "Sign in"
              focusable: true
              onClicked: {
                if (root.saving) return
                root.saveAccount(emailField.text, passwordField.text)
                passwordField.text = ""
              }
            }
            Button {
              visible: root.report !== null
              text: "Cancel"
              focusable: true
              onClicked: { root.editingAccount = false; passwordField.text = "" }
            }
          }
        }

        Row {
          visible: !root.showForm
          x: Style.space(16)
          spacing: Style.space(12)
          Text {
            textFormat: Text.PlainText
            text: root.report ? root.fmt(root.report.mgdl) : "—"
            color: root.urgentReading ? Commons.Color.urgent : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: 56
            font.bold: true
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
              textFormat: Text.PlainText
              text: root.report ? root.arrow(root.report.trend) : ""
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
            }
            Text {
              textFormat: Text.PlainText
              text: (root.mmol ? "mmol/L" : "mg/dL") + " ⇄"
              color: unitMouse.containsMouse ? root.bar.foreground : Commons.Color.muted
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              MouseArea {
                id: unitMouse
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleUnit()
              }
            }
          }
        }

        Text {
          visible: root.error !== "" || !root.showForm
          x: Style.space(16)
          width: parent.width - Style.space(32)
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          color: root.error ? Commons.Color.urgent : Commons.Color.muted
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          text: root.error
            ? root.error
            : (root.report ? (root.ageMinutes() <= 0 ? "just now" : root.ageMinutes() + " min ago")
                + (root.stale ? " (stale)" : "") : "loading…")
        }

        Canvas {
          id: graph
          x: Style.space(16)
          width: parent.width - Style.space(32)
          height: Style.space(140)
          visible: root.report !== null && !root.showForm
          Connections {
            target: root
            function onReportChanged() { graph.requestPaint() }
            function onMmolChanged() { graph.requestPaint() }
          }
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var r = root.report
            if (!r || !r.history || r.history.length < 2) return
            var pts = r.history
            var now = Date.now() / 1000
            var t0 = now - 12 * 3600
            var lo = Math.min(40, r.targetLow - 10), hi = Math.max(300, r.targetHigh + 40)
            var padL = Style.space(34)
            function X(t) { return padL + Math.max(0, Math.min(1, (t - t0) / (now - t0))) * (width - padL) }
            function Y(v) { return height - (Math.max(lo, Math.min(hi, v)) - lo) / (hi - lo) * height }
            var fg = root.bar.foreground
            ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.10)
            ctx.fillRect(padL, Y(r.targetHigh), width - padL, Y(r.targetLow) - Y(r.targetHigh))
            // Axis ticks in the chosen unit (positions are always mg/dL).
            var ticks = root.mmol ? [4, 7, 10, 14] : [70, 120, 180, 250]
            ctx.font = Style.font.caption + "px " + root.bar.fontFamily
            ctx.textBaseline = "middle"
            ctx.lineWidth = 1
            for (var k = 0; k < ticks.length; k++) {
              var mg = root.mmol ? ticks[k] * 18.0182 : ticks[k]
              if (mg < lo || mg > hi) continue
              var y = Math.round(Y(mg)) + 0.5
              ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.18)
              ctx.beginPath(); ctx.moveTo(padL, y); ctx.lineTo(width, y); ctx.stroke()
              ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.65)
              ctx.fillText(String(ticks[k]), 0, y)
            }
            ctx.strokeStyle = fg
            ctx.lineWidth = 2
            ctx.beginPath()
            var started = false
            for (var i = 0; i < pts.length; i++) {
              if (pts[i].t < t0) continue
              if (!started) { ctx.moveTo(X(pts[i].t), Y(pts[i].mgdl)); started = true }
              else ctx.lineTo(X(pts[i].t), Y(pts[i].mgdl))
            }
            ctx.stroke()
          }
        }

        Text {
          x: Style.space(16)
          visible: root.report !== null && root.report.history.length > 1
          textFormat: Text.PlainText
          color: Commons.Color.muted
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          text: {
            if (!root.report) return ""
            var v = root.report.history.map(function(p) { return p.mgdl })
            var sum = 0
            for (var i = 0; i < v.length; i++) sum += v[i]
            return "Range " + root.fmt(Math.min.apply(null, v)) + "–" + root.fmt(Math.max.apply(null, v))
              + "   Avg " + root.fmt(sum / v.length) + "   (last 12 h)"
          }
        }

        Button {
          visible: !root.showForm
          x: Style.space(16)
          text: "Account…"
          focusable: true
          onClicked: { root.editingAccount = true; emailField.forceActiveFocus() }
        }

        Item { width: 1; height: Style.space(4) }
      }
    }
  }
}
