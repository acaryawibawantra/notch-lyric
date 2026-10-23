# MORIS productivity — stage one

## Current release status: Tasks on hold

MORIS Tasks is hidden and disabled via `MorisTaskFeature.isEnabled = false`.
The tab (including swipe navigation), task popups, badges and URL-event delivery
are unavailable. Startup disables a previously enabled pairing preference; old
tokens remain stored but cannot submit events while the release gate is off.
Implementation and companion scripts remain for future work. The manual setup
below is a developer reference, not currently available end-user functionality.
Keep Awake remains independent and accessible through the app menu.

## Keep Awake

Tasks tab and menu-bar shortcut. Uses a public IOKit PreventUserIdleSystemSleep
assertion, 30/60/120 minutes or until explicitly stopped. Finite sessions include
an OS-level release timeout as well as the UI deadline. No default-on/login
restoration. The app releases its assertion on Stop and normal termination; macOS
also owns process-lifetime assertion cleanup. Manual sleep, lid closure, battery
and thermal policy still apply. The display can dim/sleep. Task events never
enable Keep Awake automatically.

## Local tasks — actual events, not account discovery

Task records are memory-only, max 50. User opt-in and a per-install UUID pairing
token are required for the `moris://task` URL handler. The token is stored locally
in preferences, not an OpenAI/Anthropic credential. Any local sender with the
token can submit labels, so source labels are NOT verified account identities.
No commands, approval actions, external navigation, or privileged actions exist
in the event payload. Reset pairing invalidates previous senders. Disabling clears
records and notices. No account files, credentials, transcripts, chat bodies, or
provider usage are read by MORIS.

Events require an ID, source (`command` or `claude`), title, state, current
millisecond `sentAt`, and token. Reject malformed, stale (>5 min), duplicate and
out-of-order events. State-changing/new events are limited to 60/min; same-state
heartbeats do not produce repeated popups. Terminal/waiting events get a 5-second
cat popup when the notch is idle and unlocked, behind call/calendar/wellness
priorities. Busy/locked displays do not replay old popups later; unread records
remain in Tasks. Preview is explicitly labeled and not added to real records.

## Set up (manual, opt-in)

1. Build/launch MORIS once so macOS registers its URL scheme.
2. Tasks → gear → enable paired local task events → Copy pairing token.
3. In your terminal, set `MORIS_TASK_TOKEN` to that copied value. Do not paste it
   into public repos or send it to a provider. Prefer your private shell/session
   configuration over a literal command saved in shared shell history.
4. Use the companion below. It uses macOS's built-in JXA formatter and `open -g`;
   no Python, jq, server, or network listener is required.

```sh
# Supply MORIS_TASK_TOKEN privately in this shell's environment first.
sh scripts/moris-task.sh run release-build "Build project" -- make
sh scripts/moris-task.sh event draft-review waiting "Review needed" command
```

The `run` wrapper executes ONLY the command explicitly supplied by its terminal
caller, preserves argument boundaries, forwards command output and exit status,
and emits running/completed/failed. The MORIS app itself never executes a command
from an event. If interrupted/killed, a final event may not arrive; MORIS does not
invent completion, progress percentages, or time estimates.

### Claude Code CLI hook

`scripts/moris-claude-hooks.example.json` is a template, NOT installed automatically.
Replace the absolute script path, merge into the desired Claude Code hook settings
without overwriting existing entries, and start Claude Code from the terminal
environment containing MORIS_TASK_TOKEN. Do not assume a Dock-launched Claude
Desktop app inherits terminal environment variables or supports this CLI hook.

The hook script reads JSON from stdin, forwards ONLY session ID, generic title
`Claude Code turn`, state and timestamp. It never reads `transcript_path`, prompt
text or assistant messages. UserPromptSubmit/PostToolUse → running, Stop → completed
TURN (not proof the whole requested project is finished), StopFailure → failed,
permission/elicitation Notification → waiting. Idle reminders and unknown hooks
are ignored. Hooks fail softly and never block or auto-approve a Claude action.
See https://code.claude.com/docs/en/hooks for supported hook configuration.

## Not included yet

Codex desktop/cloud task discovery, account sign-in, usage/quota bars, multiple
Personal/Work profiles, interactive approval responses, authenticated provider
identity, task cancellation, or restoration of running tasks after MORIS restarts.
These require a separate real connector; sample percentages must not be shipped
as live data.

## Verification

`sh Tests/run-productivity-checks.sh`: fake power assertions (no sleep settings
changed), isolated preferences and synthetic URLs (no app launched).
`node Tests/TaskBridgeChecks.cjs`: encoding and hook mappings, including the actual
JXA formatter on generated JSON. It does NOT run the delivery script, open a URL,
run a wrapped command, configure hooks, or access an account. Signed-build manual
testing is still needed for LaunchServices delivery and the actual IOKit assertion
on the user's Mac.
