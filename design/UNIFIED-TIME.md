# Unified time tools

The Focus tab exposes only Focus and Stopwatch through one segmented picker.
Focus is the single countdown, with an optional goal and the to-do list beside it;
it can be used as an ordinary timer without choosing a task.
Media has one Time tools shortcut with the same picker. The last selected mode
is shared using the existing `notchLyric.toolsSection` preference: legacy
`Clocks` and `Timer` map to Focus and `Focus` keeps its meaning. A legacy Focus split is
migrated to the shared time panel without resetting its session.

Selection changes only presentation. Timer, focus session, and stopwatch keep
their independent deadlines, pause state, completion handling, and persistence.
Closing Media's split does not stop any clock.
An old utility timer that was already active remains controllable through a
temporary Previous timer row until it completes or is stopped. No new utility
timer can be started from this panel; new countdowns use Focus.

The full tab keeps Apple Reminders tasks in its right column in both modes.
The Media split uses the same controls in a narrow layout. The summary is a
single line, not another card. The time controls can scroll when constrained,
so completion actions cannot be clipped off at the bottom.

## Visual direction

The Nusa Focus preview (https://rama2555.github.io/nusa/) is a visual reference,
not an imported asset. Focus now uses a native vector countdown dial with a soft
coral gradient, large rounded digits, a small circular reset, and pill controls.
Breaks use mint. The full tab places the dial beside the time; Media uses a
smaller dial. The previous rectangular blue surface and linear progress bar
are removed. Reduce Motion disables dial interpolation; Reduce Transparency
removes its radial glow. No independent animation timer or image assets are used.

Manual QA after running the latest build:

1. Start Focus without choosing a task, switch to Stopwatch, start it, then return.
   Both advance independently.
2. Open Media's time split. Its selected mode matches the Focus tab.
3. Close the split and reopen it. No running session is reset.
4. Start/pause/resume a Focus session, then complete it and start its break.
5. Check goal editing, duration selection, Reminders selection, and manual use
   without connecting Reminders.
6. Confirm all controls fit in both layouts with Reduce Motion enabled.
