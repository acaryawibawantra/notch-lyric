# Finishing pass: Media and Shelf

## Media

One `MediaNotchGradient` surface behind the entire expanded Media layout replaces
the isolated blurred album-art glow. Album tint gently fades to black at all four
edges, including the header/camera edge. The shell's existing shape clips it.
The surface has no stroke, no interaction and no timer/continuous animation.
Changes of album tint crossfade; Reduce Motion disables that transition and
Reduce Transparency falls back to black. The existing Lighting effect setting
controls this surface. Compact/transparent lyrics keep their separate styling.

Paused artwork stays almost full-size and legible. Its dark overlay is clipped
to the artwork and ignores hit testing, so it cannot block the music-app button.

## Shelf and AirDrop

- Remove duplicate card padding and use 12-point section spacing.
- Widen the share target to 96 points; use the native SF AirDrop symbol.
- Use a short fade rather than a spring for drag-target feedback, honoring Reduce Motion.
- Spinner only while preparing dropped items. File selection and active sharing
  have distinct labels; busy sharing disables additional share requests.
- Retain status text while the file picker/share UI is open, then expire it.
- Keep originals and Shelf entries intact when sharing through our own target.

## Verification and remaining manual QA

`Tests/run-media-surface-checks.sh` renders the production surface at 640- and
720-point widths with four tints, tests visible-but-subtle center color, black
edges and the opaque fallback. It does not change system accessibility settings.
Existing Shelf, native drag target, timeout, sharing lifecycle, selection,
conversion, spectrum, gesture, prompter and task-hold checks remain applicable.

On a signed build, verify Media with and without split mode, pause/resume, album
changes and Reduce Motion/Transparency. Verify Finder → Shelf, Paste URL → Links,
Shelf → other apps, then Finder/Shelf → AirDrop. Open the file picker, cancel,
retry, choose a recipient, and accept/cancel on a second Apple device. Automated
tests do not transfer real files; actual AirDrop delivery remains a manual check.
