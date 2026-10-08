import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "dbarrios.unifi-wan"
  ipcTarget: "dbarrios.unifi-wan"

  readonly property int windowMs: 60000

  property var status: null
  property var history: []
  property string themeToml: ""
  property bool refreshing: false
  readonly property string script: Qt.resolvedUrl("unifi-wan-status").toString().replace("file://", "")
  readonly property color okColor: Model.themeColor(themeToml, "green") || "#4caf50"
  readonly property color badColor: Model.themeColor(themeToml, "red") || Color.urgent
  readonly property color upColor: Model.themeColor(themeToml, "accent") || Color.accent
  readonly property string iconRole: Model.iconRole(status)
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function apply(text) {
    if (!refreshHold.running) root.refreshing = false
    try {
      root.status = JSON.parse(text)
    } catch (e) {
      root.status = { state: "error", error: "Bad output from status script" }
    }
    root.history = Model.pushSample(root.history, root.status, Date.now(), root.windowMs)
  }

  function openDashboard() {
    if (root.status && root.status.host)
      Quickshell.execDetached(["xdg-open", "https://" + root.status.host + "/network/" + (root.status.site || "default") + "/dashboard"])
  }

  function handlePress(b) {
    if (b === Qt.MiddleButton) {
      root.refreshing = true
      refreshHold.restart()
      root.refresh()
    } else if (b === Qt.RightButton) {
      root.openDashboard()
    } else {
      root.toggle()
    }
  }

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  onOpenedChanged: if (opened) {
    root.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Process {
    id: statusProc
    command: [root.script]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(text)
    }
  }

  // Poll faster while the graph is visible so new router samples land sooner.
  Timer {
    interval: root.opened ? 2000 : 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Keeps the refresh marker visible long enough to notice.
  Timer {
    id: refreshHold
    interval: 600
    onTriggered: if (!statusProc.running) root.refreshing = false
  }

  // Slides the graph along between samples.
  Timer {
    interval: 1000
    running: root.opened
    repeat: true
    onTriggered: graph.requestPaint()
  }

  // Theme switches swap the colors file; Color.foreground changes with them.
  FileView {
    id: themeFile
    path: Color.currentThemePath + "/colors.toml"
    printErrors: false
    onLoaded: root.themeToml = text()
  }

  Connections {
    target: Color
    function onForegroundChanged() { themeFile.reload() }
  }

  // Vertical bars are too narrow for the rates; they keep the status icon and
  // leave the numbers to the tooltip and panel.
  Row {
    id: row
    anchors.fill: parent

    WidgetButton {
      id: iconButton
      bar: root.bar
      text: Model.icon(root.status)
      fontSize: Style.font.caption
      horizontalMargin: 2
      foreground: root.iconRole === "ok" ? root.okColor
                : root.iconRole === "bad" ? root.badColor
                : root.barForeground
      tooltipText: root.opened ? "" : Model.tooltip(root.status)
      onPressed: function(b) { root.handlePress(b) }
    }

    WidgetButton {
      id: labelButton
      bar: root.bar
      visible: !(root.bar && root.bar.vertical)
      text: root.refreshing ? "↻" : Model.label(root.status)
      fontSize: Style.font.caption
      horizontalMargin: 3
      active: root.iconRole === "bad"
      tooltipText: root.opened ? "" : Model.tooltip(root.status)
      onPressed: function(b) { root.handlePress(b) }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: row
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "o" || t === "O") root.openDashboard()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: root.status && root.status.isp ? root.status.isp : "UniFi WAN"
          meta: !root.status ? "Loading…"
              : root.status.state === "error" ? root.status.error
              : root.status.state === "up" ? "Connected"
              : root.status.state === "down" ? "All WAN links down" : "WAN up, no internet"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: Model.icon(root.status)
              color: iconButton.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        PanelSectionHeader {
          text: "THROUGHPUT · LAST 60 SECONDS"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(16)
          Legend { swatch: root.okColor; label: "↓ Download"; value: Model.rate(root.status ? root.status.down : null) + "b/s" }
          Legend { swatch: root.upColor; label: "↑ Upload"; value: Model.rate(root.status ? root.status.up : null) + "b/s" }
          Item { Layout.fillWidth: true }
        }

        Canvas {
          id: graph
          width: parent.width
          height: Style.space(120)

          readonly property real yMax: Model.axisMax(root.history)
          readonly property real labelGutter: Style.space(34)

          onYMaxChanged: requestPaint()
          Connections {
            target: root
            function onHistoryChanged() { graph.requestPaint() }
            function onThemeTomlChanged() { graph.requestPaint() }
          }

          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var left = labelGutter, top = 4, right = width, bottom = height - Style.space(14)
            var w = right - left, h = bottom - top
            var now = Date.now(), start = now - root.windowMs

            function xAt(t) { return left + Math.max(0, (t - start) / root.windowMs) * w }
            function yAt(v) { return bottom - Math.min(1, v / yMax) * h }

            ctx.font = Style.font.caption + "px '" + root.fontFamily + "'"
            ctx.textBaseline = "middle"
            ctx.lineWidth = 1
            ctx.strokeStyle = Qt.alpha(root.foreground, 0.12)
            ctx.fillStyle = root.dim
            var ticks = [0, 0.5, 1]
            for (var i = 0; i < ticks.length; i++) {
              var y = Math.round(yAt(yMax * ticks[i])) + 0.5
              ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(right, y); ctx.stroke()
              ctx.textAlign = "right"
              ctx.fillText(Model.rate(yMax * ticks[i]), left - Style.space(6), y)
            }
            ctx.textBaseline = "alphabetic"
            ctx.textAlign = "left"; ctx.fillText("60s", left, height - 1)
            ctx.textAlign = "right"; ctx.fillText("now", right, height - 1)

            var pts = root.history
            if (!pts.length) return

            function series(key, color, fill) {
              ctx.beginPath()
              for (var i = 0; i < pts.length; i++) {
                var x = xAt(pts[i].t), y = yAt(pts[i][key])
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
              }
              // Hold the latest reading out to "now".
              ctx.lineTo(right, yAt(pts[pts.length - 1][key]))
              ctx.strokeStyle = color
              ctx.lineWidth = Math.max(1.5, Style.space(2))
              ctx.lineJoin = "round"
              ctx.stroke()
              if (fill) {
                ctx.lineTo(right, bottom)
                ctx.lineTo(xAt(pts[0].t), bottom)
                ctx.closePath()
                ctx.fillStyle = Qt.alpha(color, 0.15)
                ctx.fill()
              }
            }
            series("down", root.okColor, true)
            series("up", root.upColor, false)
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.spacing.labelGap

          Repeater {
            model: Model.details(root.status)
            delegate: RowLayout {
              required property var modelData
              width: parent.width
              spacing: Style.space(12)
              Text {
                Layout.preferredWidth: Style.space(80)
                text: modelData[0]
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                Layout.fillWidth: true
                text: modelData[1]
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }
          }
        }

        Text {
          width: parent.width
          text: "R refresh · O open UniFi · Esc close"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }

  component Legend: RowLayout {
    id: legend
    property color swatch
    property string label
    property string value
    spacing: Style.space(6)
    Rectangle {
      implicitWidth: Style.space(10); implicitHeight: Style.space(3); radius: height / 2
      color: legend.swatch
      Layout.alignment: Qt.AlignVCenter
    }
    Text {
      text: legend.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      text: legend.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
