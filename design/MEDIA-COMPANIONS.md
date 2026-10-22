# Media companions

Media has a persistent, local-only companion choice: Calendar, To-do (Apple
Reminders), Timer, Focus, or Lyrics. The icon strip stays visible when the split
is closed so it is easy to reopen. The close button only changes presentation;
it does not reset a clock, stop playback, or delete a reminder.

Existing calendar/full-lyrics preferences are respected until the user explicitly
chooses a panel. An explicit close overrides those old visibility preferences
without erasing them. Choosing Lyrics enables lyric fetching through the existing
lyrics preference/provider. Calendar and Reminders use existing EventKit consent
and selected lists, with connect/privacy controls when access is missing.

Timer and Focus use the same shared models as the Focus tab. Selecting a task in
To-do links it to the focus goal; switch to the target icon to start it. Companion
switching never starts a timer automatically. Camera preview can appear alongside
Media only when no companion is open, avoiding a cramped third column.

Timer and Focus center their countdown across the companion width, show session
progress, and use the lower space for a useful footer: independent stopwatch
controls for Timer, today's completed focus sessions/minutes and a task shortcut
for Focus. These controls continue to use the existing shared models.

Cat eye glow is static and palette-derived, not an always-running shimmer. Gaze
and blink timing use independent cancellable tasks, with occasional double blinks.
Reduce Motion stops both animation tasks; disabling/hiding the mascot cancels them.
Wellness previews and scheduled banners use the same cat eyes/palette, inside a
small cat silhouette. The water reminder adds an animated glass; Reduce Motion
uses a static illustration. Connection popups center their icon/text group with
separate dismissal space rather than a trailing spacer pushing content left.

Verification: `sh Tests/run-media-companion-checks.sh` checks the production
selection resolver with an in-memory preference adapter. Clock behavior is covered
by `sh Tests/run-clock-checks.sh`. Live layout and animation still need checking
on the user's signed build; tests do not read personal calendar data.
