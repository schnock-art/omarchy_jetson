import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// No windows, playback, recording or volume writes: exercise the same service
// used by Quattro and verify its default output can be read.
ShellRoot {
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    Timer {
        interval: 5000
        running: true
        onTriggered: {
            const sink = Pipewire.defaultAudioSink;
            if (!sink || !sink.audio) {
                console.error("AUDIO_PROBE_FAILED: no default output");
                Qt.exit(1);
                return;
            }
            console.log("AUDIO_PROBE_OK", sink.name,
                        "volume", sink.audio.volume, "muted", sink.audio.muted);
            Qt.quit();
        }
    }
}
