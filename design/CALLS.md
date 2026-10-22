# MORIS Calls — experimental

This is an opt-in Accessibility prototype, not a system-wide telephony bridge.
The native macOS SDK marks CXCallObserver unavailable for macOS. No private
CallServices API, notification database, microphone monitoring, or screen capture
is used. There is no guarantee of observing every iPhone/FaceTime or third-party call.

The existing XPC helper, with its own Accessibility authorization, periodically
examines bounded window/control hierarchies of a fixed application allowlist.
Only window titles and button titles/descriptions are used to classify control
combinations. Non-call-context third-party windows are skipped before traversal.
Text-field values are not requested. Window titles and control labels are not
returned to the app or logged; only application, PID, and detected phase leave
the helper. No call history is persisted or sent to a server.

The allowlist covers FaceTime/Phone, WhatsApp, Zoom, Teams, Discord, Telegram and
Slack. These are candidate adapters, NOT a verified compatibility list. Incoming
calls require accept/decline controls and a call-window context; active calls
require explicit end/leave-call plus microphone/camera controls. Languages beyond
English and Indonesian, inaccessible/minimized windows, notification-hosted calls,
browser calls, and UI changes may not be detected. No caller identity is inferred.

Enable in Appearance → MORIS Calls · Experimental, explicitly grant the helper
Accessibility access, and test real incoming/answered/ended calls per application.
No automatic answer, decline, microphone, or camera actions exist. The only action
opens the source app. Detection pauses when the screen locks. Rebuilt ad-hoc apps
or helpers may require reauthorization.

Validation so far: synthetic classification fixtures and compilation. Real calls
have not been tested; do not market this as universal call support.
