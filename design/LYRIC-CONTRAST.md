# Live lyrics and compact spectrum

Music-only and dual music/clock activity now share CompactMusicSpectrum. Bars are
native layers, directly rendered, rather than an NSViewRepresentable inside a
SwiftUI mask. Default bars are white; optional album tint has a brightness floor.
Reduce Motion uses a static waveform. This remains a decorative playback indicator,
not microphone/audio-spectrum analysis.

Media's Live lyrics shortcut offers transparent/black styles and a live toggle,
plus optional adaptive contrast. Selecting a background enables live lyrics and
the existing lyric provider. Preferences use the same existing style keys.

Adaptive contrast is OFF by default. Explicit opt-in explains Screen Recording
permission before requesting it. With access, visible transparent lyrics sample
a cropped region behind the text every two seconds using ScreenCaptureKit, with
MORIS itself excluded. Only a 64×16 in-memory image is averaged. No screenshot,
recording, audio, window title, or page text is stored or uploaded. Sampling stops
for hidden lyrics, black mode, session lock, Reduce Transparency, or disabled
preferences. Results from cancelled captures are ignored.

Linear sRGB luminance selects black/white text, with hysteresis to reduce flicker.
A contrasting outline helps on mixed backgrounds and is the no-permission/error
fallback. This is best effort, not a guarantee for every image or rapidly moving
page. OS Screen Recording permission is broader than this crop; users can revoke
it in System Settings. Permission activation may require a relaunch.

Tests: run-lyric-contrast-checks.sh uses generated pixel fixtures and display
geometry only; it never captures the user's screen or requests permission.
run-spectrum-checks.sh checks native bars using an offscreen view. Signed-build
manual QA is still needed for capture authorization, actual bright/dark pages,
Retina displays, and the compact notch's final composition.

Live lyrics owns a per-notch interaction hold from the button press through the
popover's dismissal. Nested permission dialogs own a separate hold, so closing
one surface cannot release another. All close paths consult the view model's
holds; hover-out updates pointer state immediately, cancels stale close work, and
re-arms ordinary auto-close when the final hold is released outside the notch.
View removal releases its owners. Tests/run-notch-interaction-checks.sh checks
owner independence, nested holds and idempotent cleanup without opening UI.
