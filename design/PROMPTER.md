# MORIS Prompter — first stage

Independent MORIS implementation of a notch-integrated text teleprompter. The feature idea
is informed by https://github.com/jpomykala/NotchPrompter (README and license only).
No code, assets, or product branding from that project is included. Its published
license restricts commercial reuse and relicensing; do not import its source into
MORIS without a separate compatible authorization.

## Included

- Prompter tab: paste/edit a script, up to 50,000 Unicode characters.
- Local UserDefaults draft, font size (18–42 pt), speed (10–100 points/second).
- Reading mode uses MORIS's existing notch window and silhouette at 640×310,
  with a reserved, blank camera band. No additional floating window or gap.
- Play/pause, replay, reset, manual scroll; Space, arrows and Escape while this
  panel has keyboard focus only. No global keyboard monitoring or Accessibility.
- Reading preferences and display controls; only displays with an active MORIS
  notch are offered. Enable the existing all-displays setting to use multiple
  displays. The reader stays attached to its notch, so background dragging is off.
- Hover-out does not dismiss reading. Edit returns to the script editor; close
  pauses reading and returns to the ordinary collapsed notch.
- End-of-script pause. No resumed autoplay after launch, lock, display change,
  closing the panel, or a long clock gap caused by sleep/main-thread stalls.
- Local editor focus protection: typing prevents the notch auto-closing. Floating
  lyrics yield while the reading panel is open to avoid competing text layers.

## Explicitly not included

No voice activation/speech tracking, microphone recording, AI rewriting, file
imports, mirroring, or guarantee of exclusion from screenshots/screen recording.
Text can be captured by other apps; the UI says this explicitly. No script upload
or cloud sync. Existing media/call/calendar permissions are not needed to read a
script. Clear removes the draft text from the saved snapshot.

## Verification

`sh Tests/run-prompter-checks.sh` extracts the production model into a test harness
with an isolated preference suite and fake clock, with real-time ticking disabled.
This checks boundaries, Unicode limits, playback transitions, persistence and
sleep recovery. Signed-build manual QA remains necessary for native text layout,
keyboard focus, different displays, Spaces, full-screen apps, and recording tools.
`sh Tests/run-prompter-viewport-checks.sh` also hosts the production AppKit text
viewport in an offscreen fixture window (never shown), checking document sizing,
manual seeking, last-line reachability, and short-script layout reset. It does not
inspect or operate any user windows.
`sh Tests/run-prompter-dock-checks.sh` exercises the production presentation
controller using inactive fixture windows and small notch-state adapters. It
checks targeting, read/edit/close transitions, paused display switching, retained
script text, and repeated dismissal without showing or activating any window.
