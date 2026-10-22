#!/bin/sh
# macOS companion for the opt-in MORIS status bridge. No network connection.
set -u
moris_script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case "${1:-}" in
    event|hook)
        moris_mode=$1
        moris_url=$(/usr/bin/osascript -l JavaScript "$moris_script_dir/moris-task-url.js" "$@" 2>/dev/null) || {
            if [ "$moris_mode" = hook ]; then exit 0; fi
            echo "MORIS: invalid event or missing MORIS_TASK_TOKEN." >&2
            exit 1
        }
        [ -n "$moris_url" ] || exit 0
        /usr/bin/open -g "$moris_url" >/dev/null 2>&1 || {
            if [ "$moris_mode" = hook ]; then exit 0; fi
            echo "MORIS: could not deliver event. Launch the built app once and enable the bridge." >&2
            exit 1
        }
        ;;
    run)
        # Only this explicit user-invoked wrapper runs commands. URL events never do.
        [ "$#" -ge 5 ] && [ "$4" = -- ] || {
            echo 'Usage: sh moris-task.sh run TASK_ID "Title" -- command [args...]' >&2
            exit 2
        }
        moris_id=$2
        moris_title=$3
        shift 4
        /bin/sh "$moris_script_dir/moris-task.sh" event "$moris_id" running "$moris_title" command || :
        "$@"
        moris_exit=$?
        if [ "$moris_exit" -eq 0 ]; then moris_state=completed; else moris_state=failed; fi
        /bin/sh "$moris_script_dir/moris-task.sh" event "$moris_id" "$moris_state" "$moris_title" command || :
        exit "$moris_exit"
        ;;
    *)
        echo 'Usage: sh moris-task.sh event ID STATE "Title" [command|claude]' >&2
        echo '       sh moris-task.sh run ID "Title" -- command [args...]' >&2
        echo '       sh moris-task.sh hook  (Claude Code hook JSON on stdin)' >&2
        exit 2
        ;;
esac
