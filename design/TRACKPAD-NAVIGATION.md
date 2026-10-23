# Trackpad tab navigation

With MORIS expanded and the pointer inside its window, a two-finger horizontal
swipe moves to the next (left) or previous (right) tab in header order. The first
and last tabs do not wrap. Disabled Shelf is skipped. Media playback, timers and
focus sessions continue when switching presentation.

General → Gesture control → Swipe horizontally to switch tabs controls the
feature, alongside the existing master gesture switch and sensitivity setting.
It defaults on. No global event monitor or additional permission is used.

Only precise, phased trackpad scrolling participates. Each gesture moves at most
one tab; momentum cannot trigger navigation. Vertical and ambiguous diagonal
motions pass through. Native horizontal scroll areas and sliders retain scrolling.
Text editing, file dragging, popovers, task setup and active prompter reading block
tab switching. Reduce Motion disables the tab animation.

## Checks

Run `sh Tests/run-tab-swipe-checks.sh` for accumulator thresholds, direction,
vertical locking, diagonal rejection and one-switch-per-gesture checks.

Manual signed-build QA still required with a physical trackpad:

- Hover to expand; swipe left/right through each tab, including at both ends.
- Test natural scrolling on and off; physical swipe direction should stay the same.
- Fling quickly; momentum should not skip several tabs.
- Scroll calendar/list content vertically and Shelf horizontally.
- Edit text, drag Finder files, open the lyrics popover and run the prompter.
- Disable the toggle; confirm normal scrolling and tab buttons still work.
- Test secondary displays and Reduce Motion.
