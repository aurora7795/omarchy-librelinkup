import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "aurora7795.librelinkup"

  function injectPanel() {
    var t = panelLoader.item
    if (!t) return
    if ("bar" in t) t.bar = root.bar
    if ("settings" in t) t.settings = root.settings
    if ("anchorItem" in t) t.anchorItem = button
    if ("hostWidget" in t) t.hostWidget = root
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function refresh() { if (panelLoader.item) panelLoader.item.refresh() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  // WidgetButton sizes itself to its text; BarIconButton is fixed to one icon
  // slot and lets a longer label spill over its neighbours.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: panelLoader.item ? panelLoader.item.label : "…"
    fontSize: Style.bar.iconFont
    active: panelLoader.item ? panelLoader.item.urgentReading : false
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else if (panelLoader.item) panelLoader.item.toggle()
    }
  }
}
