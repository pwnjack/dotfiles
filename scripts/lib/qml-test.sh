#!/bin/bash
#
# Runs a Qt Quick test directory offscreen. Sourced, never executed.
#

# qml_test <what> <input dir> [qmltestrunner args...] -- in a private HOME/XDG tree.
# Prints `skip: ...` and returns 0 when qmltestrunner is missing; QML_TESTRUNNER
# points it elsewhere. Prefix assignments (TZ=..., QML_XHR_ALLOW_FILE_READ=1) reach the runner.
qml_test() {
    local what=$1 input=$2 runner=${QML_TESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}
    shift 2
    [[ -x $runner ]] || { echo "skip: $what QML tests (qmltestrunner is not installed)"; return 0; }
    (
        runtime=$(mktemp -d) || exit 1
        trap 'rm -rf "$runtime"' EXIT
        # Keep the application's tracked default font when Qt's theme plugin reads
        # the private config, so isolation does not change label/geometry checks.
        mkdir -p "$runtime/config/qt6ct"
        cp "${BASH_SOURCE[0]%/*}/../../defaults/qt6ct/qt6ct.conf" "$runtime/config/qt6ct/"
        QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software HOME="$runtime" XDG_CONFIG_HOME="$runtime/config" \
            XDG_CACHE_HOME="$runtime/cache" XDG_STATE_HOME="$runtime/state" XDG_RUNTIME_DIR="$runtime" \
            "$runner" -input "$input" "$@"
    )
}
