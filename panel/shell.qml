// Claude usage details panel. Opened by the claude-usage-tray icon:
//   qs -c claude-usage ipc call panel toggle <monitor> <cursor-y>
// Data: ~/.cache/claude-usage/state.json (written by ~/.local/bin/claude-usage-tray).
// Colours follow Caelestia's current scheme (~/.local/state/caelestia/scheme.json).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

ShellRoot {
    id: root

    property bool open: false
    property string monitor: ""
    property int cursorY: -1
    readonly property real qtScale: Number(Quickshell.env("QT_SCALE_FACTOR")) || 1
    property var st: ({})
    property var pal: ({})
    property int hovered: -1

    readonly property string home: Quickshell.env("HOME")
    readonly property string font: gsf.status === FontLoader.Ready ? gsf.name : "Inter"

    function c(key, fallback) {
        return pal[key] ? "#" + pal[key] : fallback;
    }

    function fmtTokens(n) {
        if (n >= 1e9) return (n / 1e9).toFixed(1) + "B";
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M";
        if (n >= 1e3) return (n / 1e3).toFixed(1) + "k";
        return String(n);
    }

    function fmtReset(iso) {
        if (!iso) return "";
        const t = new Date(iso);
        const mins = Math.round((t - new Date()) / 60000);
        const rel = mins < 60 ? `${mins} min` : mins < 1440 ? `${Math.floor(mins / 60)} h ${mins % 60} min`
                                                            : `${Math.floor(mins / 1440)} d ${Math.floor(mins % 1440 / 60)} h`;
        const sameDay = t.toDateString() === new Date().toDateString();
        return `resets ${Qt.formatDateTime(t, sameDay ? "HH:mm" : "ddd HH:mm")} (in ${rel})`;
    }

    function sevColour(sev) {
        if (st.stale) return c("outline", "#7f849c");
        if (sev === "critical") return c("error", "#f38ba8");
        if (sev === "warning") return "#fab387";
        return c("primary", "#cba6f7");
    }

    function dayTotal(d) {
        return d ? d.input + d.output + d.cache_write + d.cache_read : 0;
    }

    // Breakdown shown under the chart: hovered day, else the whole week.
    readonly property var days: st.history ? st.history.days : []
    readonly property var focusDay: {
        if (hovered >= 0 && days[hovered]) return days[hovered];
        const sum = { input: 0, output: 0, cache_write: 0, cache_read: 0 };
        for (const d of days) for (const k in sum) sum[k] += d[k];
        return sum;
    }
    readonly property real maxDay: Math.max(1, ...days.map(dayTotal))

    FontLoader {
        id: gsf
        source: "file:///etc/xdg/quickshell/caelestia/assets/google-sans-flex/GoogleSansFlex-VariableFont_GRAD,ROND,opsz,slnt,wdth,wght.ttf"
    }

    FileView {
        id: stateFile
        path: root.home + "/.cache/claude-usage/state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.st = JSON.parse(text()); } catch (e) {}
        }
    }

    FileView {
        id: schemeFile
        path: root.home + "/.local/state/caelestia/scheme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.pal = JSON.parse(text()).colours; } catch (e) {}
        }
    }

    // The tray writes state.json with an atomic rename, which a file watch can miss.
    Timer {
        interval: 15000
        running: root.open
        repeat: true
        triggeredOnStart: true
        onTriggered: stateFile.reload()
    }

    IpcHandler {
        target: "panel"

        function toggle(monitor: string, y: int): void {
            if (root.open) {
                root.open = false;
                return;
            }
            root.monitor = monitor;
            root.cursorY = y;
            stateFile.reload();
            schemeFile.reload();
            root.open = true;
        }

        function close(): void {
            root.open = false;
        }
    }

    PanelWindow {
        id: win

        visible: root.open
        screen: Quickshell.screens.find(s => s.name === root.monitor) ?? Quickshell.screens[0]
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "claude-usage"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusiveZone: 0  // sit beside Caelestia's bar instead of reserving space

        anchors.left: true
        anchors.top: true
        margins.left: 10
        margins.top: {
            const h = implicitHeight, sh = screen ? screen.height : 1080;
            // cursorY is in compositor pixels; under QT_SCALE_FACTOR the panel's units are that much larger
            const y = root.cursorY < 0 ? (sh - h) / 2 : root.cursorY / root.qtScale - 60;
            return Math.max(10, Math.min(sh - h - 10, y));
        }

        implicitWidth: 400
        implicitHeight: body.implicitHeight + 40

        HyprlandFocusGrab {
            windows: [win]
            active: win.visible
            onCleared: root.open = false
        }

        Rectangle {
            anchors.fill: parent
            radius: 20
            color: root.c("surfaceContainer", "#1e1e2e")
            border.color: root.c("outlineVariant", "#45475a")
            border.width: 1

            focus: true
            Keys.onEscapePressed: root.open = false

            ColumnLayout {
                id: body
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: root.st.plan ? `Claude usage (${root.st.plan})` : "Claude usage"
                        font.family: root.font
                        font.pointSize: 13
                        font.weight: Font.DemiBold
                        color: root.c("onSurface", "#cdd6f4")
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: {
                            if (!root.st.updated) return "no data yet";
                            const t = Qt.formatDateTime(new Date(root.st.updated), "HH:mm");
                            return root.st.stale ? `stale · as of ${t}` : `updated ${t}`;
                        }
                        font.family: root.font
                        font.pointSize: 9
                        color: root.st.stale ? "#fab387" : root.c("onSurfaceVariant", "#a6adc8")
                    }
                }

                Text {
                    visible: !!root.st.error
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.st.error ?? ""
                    font.family: root.font
                    font.pointSize: 9
                    color: "#fab387"
                }

                // ---------------------------------------------------------- limits
                Repeater {
                    model: root.st.limits ?? []

                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 5

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: modelData.label
                                font.family: root.font
                                font.pointSize: 10.5
                                font.weight: Font.Medium
                                color: root.c("onSurface", "#cdd6f4")
                            }
                            Text {
                                text: root.fmtReset(modelData.resets_at)
                                font.family: root.font
                                font.pointSize: 8.5
                                color: root.c("onSurfaceVariant", "#a6adc8")
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(modelData.percent) + "%"
                                font.family: root.font
                                font.pointSize: 10.5
                                font.weight: Font.DemiBold
                                color: root.sevColour(modelData.severity)
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 8
                            radius: 4
                            color: root.c("surfaceContainerHighest", "#313244")
                            Rectangle {
                                width: parent.width * Math.min(1, modelData.percent / 100)
                                height: parent.height
                                radius: 4
                                color: root.sevColour(modelData.severity)
                            }
                        }
                    }
                }

                Text {
                    visible: (root.st.breakdown ?? []).some(r => r.percent > 0)
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: "Weekly use by product: " + (root.st.breakdown ?? []).filter(r => r.percent > 0)
                          .map(r => `${r.name} ${r.percent}%`).join(" · ")
                    font.family: root.font
                    font.pointSize: 8.5
                    color: root.c("onSurfaceVariant", "#a6adc8")
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: root.c("outlineVariant", "#45475a")
                }

                // ---------------------------------------------------------- weekly tokens
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Tokens this week"
                        font.family: root.font
                        font.pointSize: 10.5
                        font.weight: Font.Medium
                        color: root.c("onSurface", "#cdd6f4")
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "Claude Code on this PC"
                        font.family: root.font
                        font.pointSize: 8.5
                        color: root.c("onSurfaceVariant", "#a6adc8")
                    }
                }

                RowLayout {
                    id: chart
                    Layout.fillWidth: true
                    Layout.preferredHeight: 130
                    spacing: 8

                    Repeater {
                        model: root.days

                        Item {
                            id: col
                            required property var modelData
                            required property int index
                            readonly property date start: new Date(modelData.start)
                            readonly property bool future: start > new Date()
                            readonly property bool today: start <= new Date() && new Date() - start < 86400000

                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Text {
                                id: amount
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: bar.top
                                anchors.bottomMargin: 3
                                visible: root.dayTotal(col.modelData) > 0
                                text: root.fmtTokens(root.dayTotal(col.modelData))
                                font.family: root.font
                                font.pointSize: 7.5
                                color: root.c("onSurfaceVariant", "#a6adc8")
                            }

                            Rectangle {
                                id: bar
                                anchors.bottom: label.top
                                anchors.bottomMargin: 5
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.7
                                height: Math.max(3, (parent.height - label.height - 24) * root.dayTotal(col.modelData) / root.maxDay)
                                radius: 4
                                opacity: col.future ? 0.35 : 1
                                color: root.hovered === col.index ? root.c("primary", "#cba6f7")
                                     : root.dayTotal(col.modelData) > 0 ? root.c("primaryContainer", "#7171ac")
                                     : root.c("surfaceContainerHighest", "#313244")
                            }

                            Text {
                                id: label
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Qt.formatDateTime(col.start, "ddd")
                                font.family: root.font
                                font.pointSize: 8.5
                                font.weight: col.today ? Font.Bold : Font.Normal
                                color: col.today ? root.c("primary", "#cba6f7") : root.c("onSurfaceVariant", "#a6adc8")
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onContainsMouseChanged: {
                                    if (containsMouse) root.hovered = col.index;
                                    else if (root.hovered === col.index) root.hovered = -1;
                                }
                            }
                        }
                    }
                }

                Text {
                    text: {
                        if (root.hovered < 0 || !root.days[root.hovered]) return "Whole week (hover a day for its numbers)";
                        const s = new Date(root.days[root.hovered].start);
                        const e = new Date(s.getTime() + 86400000);
                        return `${Qt.formatDateTime(s, "ddd d MMM HH:mm")} to ${Qt.formatDateTime(e, "ddd HH:mm")}`;
                    }
                    font.family: root.font
                    font.pointSize: 8.5
                    color: root.c("onSurfaceVariant", "#a6adc8")
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: [
                            { key: "input", name: "Input", hint: "new prompt text" },
                            { key: "output", name: "Output", hint: "Claude's replies, incl. thinking" },
                            { key: "cache_write", name: "Cache write", hint: "context stored for reuse" },
                            { key: "cache_read", name: "Cache read", hint: "context reused (cheap)" }
                        ]

                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: row.implicitHeight

                            RowLayout {
                                id: row
                                anchors.left: parent.left
                                anchors.right: parent.right
                                Text {
                                    Layout.preferredWidth: 80
                                    text: modelData.name
                                    font.family: root.font
                                    font.pointSize: 9.5
                                    color: root.c("onSurface", "#cdd6f4")
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.hint
                                    font.family: root.font
                                    font.pointSize: 8
                                    color: root.c("outline", "#7f849c")
                                }
                                Text {
                                    text: root.fmtTokens(root.focusDay[modelData.key] ?? 0)
                                    font.family: root.font
                                    font.pointSize: 9.5
                                    font.weight: Font.Medium
                                    color: root.c("onSurface", "#cdd6f4")
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Total"
                        font.family: root.font
                        font.pointSize: 9.5
                        font.weight: Font.DemiBold
                        color: root.c("onSurface", "#cdd6f4")
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root.fmtTokens(root.dayTotal(root.focusDay))
                        font.family: root.font
                        font.pointSize: 9.5
                        font.weight: Font.DemiBold
                        color: root.c("primary", "#cba6f7")
                    }
                }

                Text {
                    visible: !!(root.st.history && root.st.history.session)
                    text: root.st.history && root.st.history.session
                          ? "Current 5-hour window: " + root.fmtTokens(Object.values(root.st.history.session).reduce((a, b) => a + b, 0)) + " tokens"
                          : ""
                    font.family: root.font
                    font.pointSize: 8.5
                    color: root.c("onSurfaceVariant", "#a6adc8")
                }
            }
        }
    }
}
