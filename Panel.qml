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
    || report.mgdl <= alerts.lowAt || report.mgdl >= alerts.highAt)

  readonly property string label: {
    if (report) return fmt(report.mgdl) + " " + arrow(report.trend) + (stale ? " ?" : "")
    return error ? "⚠ glucose" : "…"
  }

  readonly property string helperPath: Qt.resolvedUrl("llu.py").toString().replace("file://", "")

  // ---- notifications ----------------------------------------------------------
  // Settings live in config.json (written by the helper) and arrive with each
  // reading. Thresholds are stored in mg/dL whatever unit is displayed.
  readonly property var alertDefaults: ({ enabled: true, lowOn: true, lowAt: 70, highOn: true,
    highAt: 250, fastOn: false, signalOn: false, repeat: 30 })
  property var alerts: alertDefaults
  property bool alertsLoaded: false
  property bool editingAlerts: false
  property var alertState: ({})      // kind -> time of last notification
  readonly property int signalLostMinutes: 30
  // Nerd Font (Material Design) glyphs, written as surrogate pairs.
  readonly property string glyphLow: "\uDB81\uDD8C"     // water drop
  readonly property string glyphHigh: "\uDB80\uDC26"    // alert
  readonly property string glyphDown: "\uDB81\uDF2E"    // arrow down
  readonly property string glyphUp: "\uDB81\uDF37"      // arrow up
  readonly property string glyphSignal: "\uDB81\uDDAA"  // wifi off

  readonly property bool showAlerts: editingAlerts && !showForm
  property bool editingAbout: false
  readonly property bool showAbout: editingAbout && !showForm && !showAlerts
  readonly property bool showMain: !showForm && !showAlerts && !showAbout

  // Secondary text: the bar's foreground at 75%, readable on the popup
  // background while still clearly lighter-weight than primary text.
  readonly property color dimText: {
    var c = bar ? bar.foreground : Commons.Color.foreground
    return Qt.rgba(c.r, c.g, c.b, 0.75)
  }

  readonly property string repoUrl: "https://github.com/aurora7795/omarchy-librelinkup"
  readonly property string licenseUrl: "https://opensource.org/license/mit"
  property string version: ""

  FileView {
    path: root.helperPath.replace(/llu\.py$/, "manifest.json")
    onLoaded: {
      try { root.version = String(JSON.parse(text()).version || "") } catch (e) {}
    }
  }

  function openLink(url) {
    openProc.command = ["xdg-open", url]
    openProc.running = false
    openProc.running = true
  }
  Process { id: openProc }

  function setAlert(key, value) {
    var a = Object.assign({}, alerts)
    a[key] = value
    alerts = a
    saveAlerts()
  }

  property bool alertsDirty: false
  function saveAlerts() {
    if (alertsSaveProc.running) { alertsDirty = true; return }
    alertsDirty = false
    alertsSaveProc.command = ["python3", "-I", helperPath, "--alerts"]
    alertsSaveProc.environment = ({ "LLU_ALERTS": JSON.stringify(alerts) })
    alertsSaveProc.running = true
  }

  Process {
    id: alertsSaveProc
    onExited: if (root.alertsDirty) root.saveAlerts()
  }

  // mg/dL <-> displayed unit for the threshold fields
  function thresholdText(mgdl) { return mmol ? (mgdl / 18.0182).toFixed(1) : String(Math.round(mgdl)) }
  function parseThreshold(text) {
    var v = parseFloat(String(text).replace(",", "."))
    if (isNaN(v) || v <= 0) return NaN
    return Math.round(mmol ? v * 18.0182 : v)
  }

  // Fire `kind` when `active` turns on, and again every `repeat` minutes while
  // it stays on (0 = once per episode). Turning off resets it.
  function evaluate(kind, active, headline, body, urgency, glyph) {
    var st = Object.assign({}, alertState)
    if (!active) {
      if (kind in st) { delete st[kind]; alertState = st }
      return
    }
    var now = Date.now()
    var last = st[kind]
    var every = alerts.repeat * 60000
    if (last !== undefined && (every <= 0 || now - last < every)) return
    st[kind] = now
    alertState = st
    sendAlert(headline, body, urgency, glyph)
  }

  function sendAlert(headline, body, urgency, glyph) {
    var proc = alertProcs.objectAt(nextAlertSlot)
    nextAlertSlot = (nextAlertSlot + 1) % 4
    if (!proc) return
    var cmd = ["omarchy-notification-send", "--app-name", "LibreLinkUp", "-u", urgency]
    if (glyph) cmd.push("-g", glyph)
    proc.command = cmd.concat([headline, body])
    proc.running = false
    proc.running = true
  }

  property int nextAlertSlot: 0
  Instantiator {
    id: alertProcs
    model: 4
    delegate: Process {}
  }

  function checkAlert() {
    if (!report) return
    if (!alerts.enabled) { if (Object.keys(alertState).length) alertState = ({}); return }
    var age = ageMinutes()
    // No fresh data: only the signal-lost alert can apply.
    evaluate("signal", alerts.signalOn && age >= signalLostMinutes,
      "No glucose data", "Last reading " + age + " min ago", "normal", glyphSignal)
    if (stale) {
      evaluate("low", false); evaluate("high", false); evaluate("fastDown", false); evaluate("fastUp", false)
      return
    }
    var v = report.mgdl
    var unit = (mmol ? "mmol/L" : "mg/dL")
    var body = fmt(v) + " " + unit + " " + arrow(report.trend)
    evaluate("low", alerts.lowOn && v <= alerts.lowAt, "Low glucose", body, "critical", glyphLow)
    evaluate("high", alerts.highOn && v >= alerts.highAt, "High glucose", body, "normal", glyphHigh)
    evaluate("fastDown", alerts.fastOn && report.trend === 1, "Falling fast", body, "normal", glyphDown)
    evaluate("fastUp", alerts.fastOn && report.trend === 5, "Rising fast", body, "normal", glyphUp)
  }

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
            if (r.alerts && !root.alertsLoaded) { root.alerts = r.alerts; root.alertsLoaded = true }
            if (root.saving) root.editingAccount = false
          } else {
            root.error = String(r.error || "unknown error")
            root.needsSetup = r.setup === true
          }
        } catch (e) {
          root.error = "no response from helper"
        }
        root.saving = false
        root.checkAlert()
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
      blocked: root.showForm || root.showAlerts
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
            color: root.dimText
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
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            visible: root.report !== null
            text: root.report && root.report.storage === "file"
              ? "No system keyring found: the password is kept in a private file (~/.config/librelinkup/config.json, mode 600)."
              : "The password is stored in your system keyring, not in a file."
            color: root.dimText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
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
          visible: root.showMain
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
              color: unitMouse.containsMouse ? root.bar.foreground : root.dimText
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
          visible: root.error !== "" ? (!root.showAlerts && !root.showAbout) : root.showMain
          x: Style.space(16)
          width: parent.width - Style.space(32)
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          color: root.error ? Commons.Color.urgent : root.dimText
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
          visible: root.report !== null && root.showMain
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
            var peak = 0, trough = 1000
            for (var j = 0; j < pts.length; j++) {
              if (pts[j].t < t0) continue
              peak = Math.max(peak, pts[j].mgdl)
              trough = Math.min(trough, pts[j].mgdl)
            }
            // Scale to the data so highs and lows are never clipped.
            var lo = Math.min(40, r.targetLow - 10, trough - 10)
            var hi = Math.max(300, r.targetHigh + 40, peak + 10)
            var padL = Style.space(34)
            function X(t) { return padL + Math.max(0, Math.min(1, (t - t0) / (now - t0))) * (width - padL) }
            function Y(v) { return height - (Math.max(lo, Math.min(hi, v)) - lo) / (hi - lo) * height }
            var fg = root.bar.foreground
            ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.10)
            ctx.fillRect(padL, Y(r.targetHigh), width - padL, Y(r.targetLow) - Y(r.targetHigh))
            // Axis ticks in the chosen unit (positions are always mg/dL).
            var ticks = root.mmol ? [4, 7, 10, 14, 20, 25] : [70, 120, 180, 250, 350, 450]
            ctx.font = Style.font.caption + "px " + root.bar.fontFamily
            ctx.textBaseline = "middle"
            ctx.lineWidth = 1
            for (var k = 0; k < ticks.length; k++) {
              var mg = root.mmol ? ticks[k] * 18.0182 : ticks[k]
              if (mg < lo || mg > hi) continue
              var y = Math.round(Y(mg)) + 0.5
              ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.18)
              ctx.beginPath(); ctx.moveTo(padL, y); ctx.lineTo(width, y); ctx.stroke()
              ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.8)
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
          width: parent.width - Style.space(32)
          horizontalAlignment: Text.AlignHCenter
          visible: root.showMain && root.report !== null && root.report.history.length > 1
          textFormat: Text.PlainText
          color: root.dimText
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

        Row {
          visible: root.showMain
          x: Style.space(16)
          spacing: Style.space(8)
          Button {
            text: "Account…"
            focusable: true
            onClicked: { root.editingAccount = true; emailField.forceActiveFocus() }
          }
          Button {
            text: root.alerts.enabled ? "Notifications…" : "Notifications (off)…"
            focusable: true
            onClicked: { root.editingAbout = false; root.editingAlerts = true }
          }
          Button {
            text: "About…"
            focusable: true
            onClicked: { root.editingAlerts = false; root.editingAbout = true }
          }
        }

        Column {
          id: aboutPanel
          visible: root.showAbout
          x: Style.space(16)
          width: parent.width - Style.space(32)
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            text: "LibreLinkUp for Omarchy" + (root.version !== "" ? "  v" + root.version : "")
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            text: "Shows your LibreLinkUp glucose reading in the bar."
            color: root.dimText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            id: repoLink
            textFormat: Text.PlainText
            text: "GitHub: aurora7795/omarchy-librelinkup"
            color: repoMouse.containsMouse ? root.bar.foreground : Commons.Color.accent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.underline: true
            MouseArea {
              id: repoMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openLink(root.repoUrl)
            }
          }
          Row {
            spacing: 0
            Text {
              textFormat: Text.PlainText
              text: "Copyright © 2026 Martin Bradford Gago · "
              color: root.dimText
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              textFormat: Text.PlainText
              text: "MIT License"
              color: licenseMouse.containsMouse ? root.bar.foreground : Commons.Color.accent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.underline: true
              MouseArea {
                id: licenseMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openLink(root.licenseUrl)
              }
            }
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            text: "Not a medical device. Do not use for treatment or dosing decisions. Not affiliated with or endorsed by Abbott. Uses the unofficial LibreView API."
            color: root.dimText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Button {
            text: "Done"
            focusable: true
            onClicked: root.editingAbout = false
          }
        }

        Column {
          id: alertsForm
          visible: root.showAlerts
          x: Style.space(16)
          width: parent.width - Style.space(32)
          spacing: Style.space(6)

          Text {
            textFormat: Text.PlainText
            text: "Notifications"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Toggle {
            width: parent.width
            label: "Notifications"
            description: "Turn all LibreLinkUp notifications on or off"
            checked: root.alerts.enabled
            onClicked: root.setAlert("enabled", !root.alerts.enabled)
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            enabled: root.alerts.enabled
            opacity: root.alerts.enabled ? 1 : 0.4

            Toggle {
              width: parent.width
              label: "Low glucose"
              description: "Critical notification at or below the level"
              checked: root.alerts.lowOn
              onClicked: root.setAlert("lowOn", !root.alerts.lowOn)
            }
            Row {
              x: Style.space(12)
              spacing: Style.space(8)
              visible: root.alerts.lowOn
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Alert at or below"
                color: root.dimText
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              TextField {
                id: lowField
                width: Style.space(70)
                text: root.thresholdText(root.alerts.lowAt)
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                onEditingFinished: {
                  var v = root.parseThreshold(text)
                  if (!isNaN(v)) root.setAlert("lowAt", Math.max(40, Math.min(120, v)))
                  text = Qt.binding(function() { return root.thresholdText(root.alerts.lowAt) })
                }
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.mmol ? "mmol/L" : "mg/dL"
                color: root.dimText
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Toggle {
              width: parent.width
              label: "High glucose"
              description: "Notification at or above the level"
              checked: root.alerts.highOn
              onClicked: root.setAlert("highOn", !root.alerts.highOn)
            }
            Row {
              x: Style.space(12)
              spacing: Style.space(8)
              visible: root.alerts.highOn
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Alert at or above"
                color: root.dimText
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              TextField {
                id: highField
                width: Style.space(70)
                text: root.thresholdText(root.alerts.highAt)
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                onEditingFinished: {
                  var v = root.parseThreshold(text)
                  if (!isNaN(v)) root.setAlert("highAt", Math.max(140, Math.min(400, v)))
                  text = Qt.binding(function() { return root.thresholdText(root.alerts.highAt) })
                }
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.mmol ? "mmol/L" : "mg/dL"
                color: root.dimText
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Toggle {
              width: parent.width
              label: "Rising / falling fast"
              description: "When the trend arrow is a double arrow (↑ or ↓)"
              checked: root.alerts.fastOn
              onClicked: root.setAlert("fastOn", !root.alerts.fastOn)
            }
            Toggle {
              width: parent.width
              label: "Signal lost"
              description: "No new reading for " + root.signalLostMinutes + " minutes"
              checked: root.alerts.signalOn
              onClicked: root.setAlert("signalOn", !root.alerts.signalOn)
            }

            Row {
              x: Style.space(12)
              spacing: Style.space(8)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Repeat every"
                color: root.dimText
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              TextField {
                id: repeatField
                width: Style.space(60)
                text: String(root.alerts.repeat)
                inputMethodHints: Qt.ImhDigitsOnly
                onEditingFinished: {
                  var v = parseInt(text)
                  if (!isNaN(v) && v >= 0) root.setAlert("repeat", Math.min(240, v))
                  text = Qt.binding(function() { return String(root.alerts.repeat) })
                }
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "min (0 = once)"
                color: root.dimText
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Button {
            text: "Done"
            focusable: true
            onClicked: root.editingAlerts = false
          }
        }

        Item { width: 1; height: Style.space(4) }
      }
    }
  }
}
