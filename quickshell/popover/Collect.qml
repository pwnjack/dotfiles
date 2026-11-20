import Quickshell.Io

// A Process that reports once its exit and both streams are in, since
// either stream can finish after the exit.
Process {
    id: proc
    signal done(int code, string out, string err)
    property int exitCode: -1
    property bool outDone: false
    property bool errDone: false
    function check() {
        if (exitCode >= 0 && outDone && errDone) done(exitCode, outText.text, errText.text);
    }
    onStarted: { exitCode = -1; outDone = false; errDone = false; }
    stdout: StdioCollector { id: outText; onStreamFinished: { proc.outDone = true; proc.check(); } }
    stderr: StdioCollector { id: errText; onStreamFinished: { proc.errDone = true; proc.check(); } }
    onExited: code => { exitCode = code; check(); }
}
