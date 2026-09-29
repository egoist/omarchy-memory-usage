import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "dev.egoist.memory-usage"
  ipcTarget: "dev.egoist.memory-usage"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property bool processLoading: false
  property bool processHasSnapshot: false
  property string processError: ""
  property var processRows: []

  readonly property var barIdentity: hostWidget || root
  readonly property var snapshot: hostWidget && hostWidget.memorySnapshot
    ? hostWidget.memorySnapshot
    : ({})
  readonly property string memoryError: hostWidget ? String(hostWidget.memoryError || "") : ""
  readonly property int processRosterSize: {
    var value = Number(setting("processCount", 5))
    return isFinite(value) ? Math.max(1, Math.min(10, Math.round(value))) : 5
  }
  readonly property string processScript: localPath(Qt.resolvedUrl("scripts/process-memory"))

  readonly property real totalBytes: Number(snapshot.totalBytes || 0)
  readonly property real usedBytes: Number(snapshot.usedBytes || 0)
  readonly property real appBytes: Number(snapshot.appBytes || 0)
  readonly property real kernelBytes: Number(snapshot.kernelBytes || 0)
  readonly property real cacheBytes: Number(snapshot.cacheBytes || 0)
  readonly property real freeBytes: Number(snapshot.freeBytes || 0)
  readonly property real swapTotalBytes: Number(snapshot.swapTotalBytes || 0)
  readonly property real swapUsedBytes: Number(snapshot.swapUsedBytes || 0)
  readonly property real swapInBytesPerSecond: Number(snapshot.swapInBytesPerSecond || 0)
  readonly property real swapOutBytesPerSecond: Number(snapshot.swapOutBytesPerSecond || 0)
  readonly property real pressurePercent: Math.max(0, Math.min(100, Number(snapshot.pressurePercent || 0)))
  readonly property real usedPercent: totalBytes > 0
    ? Math.max(0, Math.min(100, usedBytes * 100 / totalBytes))
    : 0

  readonly property color appColor: "#168cfa"
  readonly property color kernelColor: "#f05a9d"
  readonly property color cacheColor: "#ffc11a"
  // Text on the popup takes the popup's own text colour. barForeground is
  // tuned for the bar, and can be dark when the popup behind the text is
  // dark too (a transparent bar over a light wallpaper).
  readonly property color panelForeground: Color.popups.text
  readonly property color freeColor: Qt.rgba(panelForeground.r, panelForeground.g, panelForeground.b, 0.22)
  readonly property color pressureColor: Color.accent

  readonly property var memorySegments: [
    { value: appBytes, color: appColor },
    { value: kernelBytes, color: kernelColor },
    { value: cacheBytes, color: cacheColor },
    { value: freeBytes, color: freeColor }
  ]
  readonly property var breakdownRows: [
    { label: "Applications", value: appBytes, color: appColor },
    { label: "Kernel", value: kernelBytes, color: kernelColor },
    { label: "Cache", value: cacheBytes, color: cacheColor },
    { label: "Free", value: freeBytes, color: freeColor }
  ]

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try { return decodeURIComponent(value) } catch (error) { return value }
  }

  function open() {
    processError = ""
    processLoading = !processHasSnapshot
    root.controller.show()
    Qt.callLater(root.refreshProcesses)
  }

  function close() {
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refreshProcesses() {
    if (!processMemory.running) processMemory.running = true
  }

  function updateProcesses(raw) {
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      processRows = Array.isArray(parsed) ? parsed : []
      processError = ""
      processHasSnapshot = true
      processLoading = false
    } catch (error) {
      if (!processHasSnapshot) {
        processRows = []
        processError = "Could not read process memory"
        processHasSnapshot = true
      }
      processLoading = false
    }
  }

  function formatBytes(bytes) {
    var value = Number(bytes)
    if (!isFinite(value) || value < 0) value = 0
    if (value < 1024) return Math.round(value) + " B"
    if (value < 1024 * 1024)
      return (value / 1024).toFixed(value < 10 * 1024 ? 1 : 0) + " KB"
    if (value < 1024 * 1024 * 1024)
      return (value / (1024 * 1024)).toFixed(value < 100 * 1024 * 1024 ? 1 : 0) + " MB"
    return (value / (1024 * 1024 * 1024)).toFixed(1) + " GB"
  }

  function formatRate(bytesPerSecond) {
    return formatBytes(bytesPerSecond) + "/s"
  }

  function normalizedAppName(value) {
    return String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "")
  }

  function desktopEntryForProcess(processName) {
    var needle = normalizedAppName(processName)
    if (needle.length < 2) return null

    var entries = DesktopEntries.applications.values || []
    var bestEntry = null
    var bestScore = 0

    for (var index = 0; index < entries.length; index++) {
      var entry = entries[index]
      if (!entry) continue

      var id = normalizedAppName(entry.id).replace(/desktop$/, "")
      var name = normalizedAppName(entry.name)
      var icon = normalizedAppName(entry.icon)
      var score = 0

      if (needle === id || needle === name || needle === icon) score = 100
      else if (needle.length >= 4 && (id.indexOf(needle) >= 0 || name.indexOf(needle) >= 0 || icon.indexOf(needle) >= 0)) score = 80
      else if (id.length >= 4 && needle.indexOf(id) >= 0) score = 70

      if (score > bestScore) {
        bestScore = score
        bestEntry = entry
      }
    }

    return bestEntry
  }

  function processDisplayName(processName) {
    var entry = desktopEntryForProcess(processName)
    return entry && entry.name ? String(entry.name) : String(processName || "Unknown")
  }

  function processIconSource(processName) {
    var entry = desktopEntryForProcess(processName)
    var appLibrary = root.bar && root.bar.shell ? root.bar.shell.appLibrary : null
    if (entry && appLibrary && typeof appLibrary.iconSource === "function")
      return appLibrary.iconSource(entry.icon)

    if (entry && entry.icon) {
      var entryIcon = Quickshell.iconPath(String(entry.icon), true)
      if (entryIcon) return entryIcon
    }

    var processIcon = Quickshell.iconPath(String(processName || ""), true)
    if (processIcon) return processIcon
    return Quickshell.iconPath("application-x-executable", true)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refreshProcesses()
      }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(8)

        Row {
          width: parent.width
          height: Style.space(142)

          Item {
            width: parent.width / 2
            height: parent.height

            Canvas {
              id: pressureRing
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              width: Style.space(104)
              height: width
              property real progress: root.pressurePercent / 100
              property color trackColor: root.freeColor
              property color ringColor: root.pressureColor

              onProgressChanged: requestPaint()
              onTrackColorChanged: requestPaint()
              onRingColorChanged: requestPaint()
              onWidthChanged: requestPaint()
              onHeightChanged: requestPaint()
              onPaint: {
                var context = getContext("2d")
                context.clearRect(0, 0, width, height)
                var ringWidth = Style.spaceReal(8)
                var radius = Math.max(0, Math.min(width, height) / 2 - ringWidth / 2)
                var start = -Math.PI / 2
                context.lineWidth = ringWidth
                context.lineCap = "butt"

                context.beginPath()
                context.strokeStyle = trackColor
                context.arc(width / 2, height / 2, radius, start, start + Math.PI * 2)
                context.stroke()

                if (progress > 0) {
                  context.beginPath()
                  context.strokeStyle = ringColor
                  context.arc(width / 2, height / 2, radius, start, start + Math.PI * 2 * Math.min(1, progress))
                  context.stroke()
                }
              }
            }

            Text {
              anchors.horizontalCenter: pressureRing.horizontalCenter
              anchors.verticalCenter: pressureRing.verticalCenter
              anchors.verticalCenterOffset: -Style.space(4)
              text: root.totalBytes > 0 ? Math.round(root.pressurePercent) + "%" : "--"
              color: root.panelForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.space(25)
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              anchors.horizontalCenter: pressureRing.horizontalCenter
              anchors.verticalCenter: pressureRing.verticalCenter
              anchors.verticalCenterOffset: Style.space(20)
              text: "PRESSURE"
              color: root.panelForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              text: "PSI · 10 second average"
              color: Qt.darker(root.panelForeground, 1.5)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Item {
            width: parent.width / 2
            height: parent.height

            Canvas {
              id: memoryRing
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              width: Style.space(104)
              height: width
              property real total: root.totalBytes
              property var segments: root.memorySegments
              property color trackColor: root.freeColor

              onTotalChanged: requestPaint()
              onSegmentsChanged: requestPaint()
              onTrackColorChanged: requestPaint()
              onWidthChanged: requestPaint()
              onHeightChanged: requestPaint()
              onPaint: {
                var context = getContext("2d")
                context.clearRect(0, 0, width, height)
                var ringWidth = Style.spaceReal(8)
                var radius = Math.max(0, Math.min(width, height) / 2 - ringWidth / 2)
                var start = -Math.PI / 2
                var fullCircle = Math.PI * 2
                var gap = 0.02
                context.lineWidth = ringWidth
                context.lineCap = "butt"

                context.beginPath()
                context.strokeStyle = trackColor
                context.arc(width / 2, height / 2, radius, start, start + fullCircle)
                context.stroke()

                if (total <= 0) return
                for (var index = 0; index < segments.length; index++) {
                  var segment = segments[index]
                  var sweep = Math.max(0, Number(segment.value || 0)) / total * fullCircle
                  if (sweep > gap) {
                    context.beginPath()
                    context.strokeStyle = segment.color
                    context.arc(width / 2, height / 2, radius, start + gap / 2, start + sweep - gap / 2)
                    context.stroke()
                  }
                  start += sweep
                }
              }
            }

            Text {
              anchors.horizontalCenter: memoryRing.horizontalCenter
              anchors.verticalCenter: memoryRing.verticalCenter
              anchors.verticalCenterOffset: -Style.space(4)
              text: root.totalBytes > 0 ? Math.round(root.usedPercent) + "%" : "--"
              color: root.panelForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.space(25)
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              anchors.horizontalCenter: memoryRing.horizontalCenter
              anchors.verticalCenter: memoryRing.verticalCenter
              anchors.verticalCenterOffset: Style.space(20)
              text: "MEMORY"
              color: root.panelForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              text: root.totalBytes > 0
                ? root.formatBytes(root.usedBytes) + " of " + root.formatBytes(root.totalBytes)
                : (root.memoryError !== "" ? root.memoryError : "Reading memory…")
              color: Qt.darker(root.panelForeground, 1.5)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Math.max(1, Style.space(1))
          color: root.panelForeground
          opacity: 0.12
        }

        Repeater {
          model: root.breakdownRows

          delegate: Item {
            required property var modelData
            width: contentColumn.width
            height: Style.space(22)

            Rectangle {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(9)
              height: width
              radius: width / 2
              color: modelData.color
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              color: root.panelForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.formatBytes(modelData.value)
              color: root.panelForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              horizontalAlignment: Text.AlignRight
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Math.max(1, Style.space(1))
          color: root.panelForeground
          opacity: 0.12
        }

        Item {
          width: parent.width
          height: Style.space(22)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "TOP PROCESSES"
            color: root.appColor
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(7)
            height: width
            radius: width / 2
            color: root.appColor
            opacity: root.processLoading ? 0.45 : 0.9

            SequentialAnimation on opacity {
              running: root.opened && root.processLoading
              loops: Animation.Infinite
              NumberAnimation { to: 0.25; duration: 450 }
              NumberAnimation { to: 0.9; duration: 450 }
            }
          }
        }

        Text {
          visible: root.processRows.length === 0
          width: parent.width
          height: Style.space(46)
          text: root.processError !== ""
            ? root.processError
            : (root.processLoading ? "Reading process memory…" : "No process memory data")
          color: Qt.darker(root.panelForeground, 1.35)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }

        Repeater {
          model: root.processRows.slice(0, root.processRosterSize)

          delegate: Item {
            required property var modelData
            width: contentColumn.width
            height: Style.space(27)

            Item {
              id: processIconSlot
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(22)
              height: parent.height

              Image {
                id: processIcon
                anchors.centerIn: parent
                width: Style.space(18)
                height: width
                fillMode: Image.PreserveAspectFit
                source: root.processIconSource(modelData.name)
                asynchronous: true
              }

              Text {
                anchors.centerIn: parent
                visible: processIcon.status !== Image.Ready
                text: "󰣆"
                color: root.panelForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
              }
            }

            Text {
              anchors.left: processIconSlot.right
              anchors.leftMargin: Style.space(7)
              anchors.right: processPercentLabel.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: root.processDisplayName(modelData.name)
                + (Number(modelData.processCount || 0) > 1 ? "  ·  " + modelData.processCount : "")
              color: root.panelForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              id: processPercentLabel
              anchors.right: processMemoryLabel.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(56)
              text: Number(modelData.percent || 0).toFixed(1) + "%"
              color: Qt.darker(root.panelForeground, 1.25)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignRight
            }

            Text {
              id: processMemoryLabel
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(82)
              text: root.formatBytes(modelData.rssBytes)
              color: root.panelForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              horizontalAlignment: Text.AlignRight
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Math.max(1, Style.space(1))
          color: root.panelForeground
          opacity: 0.12
        }

        Item {
          width: parent.width
          height: Style.space(22)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Swap in"
            color: root.panelForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.formatRate(root.swapInBytesPerSecond)
            color: root.panelForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }

        Item {
          width: parent.width
          height: Style.space(22)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Swap out"
            color: root.panelForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.formatRate(root.swapOutBytesPerSecond)
            color: root.panelForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }

        Rectangle {
          width: parent.width
          height: Math.max(1, Style.space(1))
          color: root.panelForeground
          opacity: 0.12
        }

        Item {
          width: parent.width
          height: Style.space(22)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "SWAP"
            color: root.appColor
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.swapTotalBytes > 0
              ? root.formatBytes(root.swapUsedBytes) + " of " + root.formatBytes(root.swapTotalBytes)
              : "Not configured"
            color: root.panelForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }

        Text {
          width: parent.width
          text: "Processes are grouped RSS · R to refresh"
          color: Qt.darker(root.panelForeground, 1.5)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }

  Process {
    id: processMemory
    command: [root.processScript]

    onRunningChanged: {
      if (running) root.processLoading = !root.processHasSnapshot
      else root.processLoading = false
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.processHasSnapshot) {
        root.processRows = []
        root.processError = "Could not read process memory"
        root.processHasSnapshot = true
      }
      root.processLoading = false
    }

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateProcesses(text)
    }
  }

  Timer {
    interval: 2000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshProcesses()
  }
}
