import QtQuick
import "Format.js" as Format

// View mode's timeline: the whole edit laid end to end as one filmstrip,
// with the playhead over it. Press anywhere to jump there, and drag to scrub:
// the preview follows the pointer, silently, so a place is quick to find.
// Nothing here edits. "t" is seconds along the sequence.
Item {
    id: root
    implicitHeight: 64
    // Time runs left to right in every language, so the timeline isn't mirrored.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    readonly property var timeline: backend.timeline
    readonly property var clips: timeline.clips
    readonly property real durationSec: timeline.duration
    property real playheadSec: 0
    property color accent: "#FFD60A"
    // Held down on the bar, so playback must not move the playhead.
    readonly property bool interacting: area.pressed

    readonly property int frameW: 3
    readonly property real frameRadius: theme.radius
    readonly property color trackColor: "#1c1c1e"
    // The same decode size as the edit bar's, so both share cached frames.
    readonly property int thumbHeight: 140

    signal scrubStarted()
    signal scrub(real seconds)
    signal scrubEnded()

    readonly property real stripWidth: Math.max(width - 2 * frameW, 1)
    readonly property real pxPerSec: durationSec > 0 ? stripWidth / durationSec : 0
    function xForTime(t) { return frameW + t * pxPerSec }
    function timeForX(x) {
        if (durationSec <= 0) return 0
        return Math.max(0, Math.min(1, (x - frameW) / stripWidth)) * durationSec
    }
    // Seconds of source per filmstrip frame, on the edit bar's ladder.
    readonly property real frameStep: {
        var wanted = (height - 2 * frameW) * 16 / 9 / Math.max(pxPerSec, 0.001)
        var steps = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800]
        for (var i = 0; i < steps.length; ++i) if (steps[i] >= wanted) return steps[i]
        return 3600
    }

    Rectangle {
        id: track
        anchors.fill: parent
        radius: root.frameRadius
        color: root.trackColor
    }

    // Each clip's frames, side by side in play order.
    Item {
        id: strip
        anchors.fill: parent
        anchors.margins: root.frameW
        clip: true
        Repeater {
            model: root.clips.length
            Item {
                id: clipItem
                required property int index
                // Briefly past the end while the clip count changes.
                readonly property var c: root.clips[index] || { source: 0, in: 0, out: 0, start: 0, end: 0 }
                readonly property var video: backend.videos[c.source]
                x: Math.round(c.start * root.pxPerSec)
                width: Math.round(c.end * root.pxPerSec) - x
                height: parent.height
                clip: true
                readonly property int first: Math.floor(c.in / root.frameStep)
                readonly property int count: video ? Math.max(0, Math.ceil(c.out / root.frameStep) - first) : 0
                Repeater {
                    model: clipItem.count
                    Image {
                        required property int index
                        readonly property real time: (clipItem.first + index) * root.frameStep
                        x: Math.round((time - clipItem.c.in) * root.pxPerSec)
                        width: Math.ceil(root.frameStep * root.pxPerSec) + 1
                        height: clipItem.height
                        sourceSize.height: root.thumbHeight
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        source: "image://thumbs/" + clipItem.video.thumbKey + "/" + Math.round(time * 1000)
                    }
                }
                // A hairline where one clip gives way to the next.
                Rectangle {
                    visible: clipItem.index > 0
                    width: 1; height: parent.height
                    color: root.trackColor
                }
            }
        }
    }

    // A rounded frame over the strip, so its corners don't poke out.
    Rectangle {
        anchors.fill: parent
        radius: root.frameRadius
        color: "transparent"
        border.color: area.containsMouse || area.pressed ? "#3a3a3e" : "#2c2c2f"
        border.width: root.frameW
    }

    // Where the pointer is, while it hovers: a faint line to aim with.
    Rectangle {
        visible: area.containsMouse && !area.pressed && root.durationSec > 0
        x: Math.round(root.xForTime(root.timeForX(area.mouseX))) - 1
        y: root.frameW
        width: 2; height: root.height - 2 * root.frameW
        color: "white"; opacity: 0.45
    }

    // The playhead: thick enough to grab by eye, outlined so it reads on any frame.
    Rectangle {
        visible: root.durationSec > 0
        x: Math.round(root.xForTime(Math.min(root.playheadSec, root.durationSec))) - width / 2
        y: 0
        width: 4; height: root.height
        radius: 2
        color: root.accent
        border.color: "#0e0e10"; border.width: 1
    }

    // The time under the pointer, above the bar.
    Rectangle {
        readonly property real at: area.pressed ? root.playheadSec : root.timeForX(area.mouseX)
        visible: root.durationSec > 0 && (area.containsMouse || area.pressed)
        width: timeLabel.implicitWidth + 20; height: 28
        radius: Math.min(4, theme.radius); color: "#2c2c2f"
        x: Math.max(0, Math.min(root.width - width, root.xForTime(at) - width / 2))
        y: -height - 8
        Text {
            id: timeLabel
            anchors.centerIn: parent
            color: "white"
            text: Format.fmt(parent.at)
            font.pixelSize: 14
            font.family: "monospace"
            font.weight: Font.DemiBold
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.durationSec > 0
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        // The window moves the playhead, which comes back in through playheadSec.
        function seek(x) { root.scrub(root.timeForX(x)) }
        onPressed: mouse => { root.scrubStarted(); seek(mouse.x) }
        onPositionChanged: mouse => { if (pressed) seek(mouse.x) }
        onReleased: root.scrubEnded()
        onCanceled: root.scrubEnded()
    }
}
