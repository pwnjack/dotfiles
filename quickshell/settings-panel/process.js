import Gio from "gi://Gio"

// No GTK/Astal imports: these helpers exist only while a request is running.
export function execAsync(args) {
    return new Promise((resolve, reject) => {
        try {
            const child = Gio.Subprocess.new(args, Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE)
            child.communicate_utf8_async(null, null, (proc, result) => {
                try {
                    const [, stdout, stderr] = proc.communicate_utf8_finish(result)
                    if (!proc.get_successful()) throw new Error(stderr.trim() || `${args[0]} failed`)
                    resolve(stdout.trim())
                } catch (error) { reject(error) }
            })
        } catch (error) { reject(error) }
    })
}

// execInput(args, input): like execAsync, with `input` written to stdin (the
// only way a password reaches a child: never argv, never the environment).
export function execInput(args, input) {
    return new Promise((resolve, reject) => {
        try {
            const child = Gio.Subprocess.new(args, Gio.SubprocessFlags.STDIN_PIPE | Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE)
            child.communicate_utf8_async(input, null, (proc, result) => {
                try {
                    const [, stdout, stderr] = proc.communicate_utf8_finish(result)
                    if (!proc.get_successful()) throw new Error(stderr.trim().split("\n").pop() || `${args[0]} failed`)
                    resolve(stdout.trim())
                } catch (error) { reject(error) }
            })
        } catch (error) { reject(error) }
    })
}
