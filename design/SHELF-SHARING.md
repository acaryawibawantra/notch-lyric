# Shelf sharing and explicit paste

## User workflow

- Keep: drag Finder files/folders or a browser URL into the Shelf tray.
- Paste: copy Finder items, a complete HTTP(S) link, or text; click Paste in Shelf.
  Cmd-V also works after clicking Shelf, unless a text field is being edited.
  Pasted URL text is classified as Links; other text becomes Notes.
- Copied PNG/TIFF bitmap images (including clipboard screenshots) are supported
  by Paste/Cmd-V. A PNG copy is created with transparency preserved. Raw bitmap
  data wins over a browser source URL; original file URLs still win over Finder
  preview bitmaps. Decode is limited to 32 MB encoded / 25 MP to bound memory.
- Send: drop onto the separate AirDrop/share target, or select items and use Share.
  AirDrop opens macOS's recipient UI, not an automatic background transfer.
  The sender still needs to choose a recipient and the recipient may need to accept.
- Items dragged from Shelf to its own share target remain on Shelf, even with
  auto-remove enabled. Starting a share is not proof of delivery.

## Fixes

AirDrop is registered by its native service identifier rather than relying solely
on discovery with a mixed URL/text probe or a localized title. File representations
are loaded before URL/text fallbacks. Mixed file/text batches retain all entries.
Plain text is materialized as an app-owned text file when the target does not
support raw text. Temporary share files are removed only by completion/cancellation
callbacks, never immediately after `perform` returns.

Sharing services, pickers, delegates and security-scoped file access remain retained
until their lifecycle callbacks. The old unconditional two-second teardown is gone.
No anchor and concurrent-share cases have feedback and balanced interaction holds.
Drop preparation also holds the notch open. Header and context-menu sharing use
the same service. Original Finder files are never removed by this flow.

Clipboard reads occur only in response to Paste/Cmd-V. Clipboard tests use a
private named pasteboard, not the user's general clipboard.

## File picker and native drag destination

Clicking the share tile opens a retained, asynchronous standalone NSOpenPanel,
explicitly above the notch window's main-menu level. It activates the app and
brings the panel to the front rather than entering a blocking `runModal` loop.
The tile says “Choose files…” while selection is open; it is not a transfer spinner.
Drop preparation alone uses the spinner.

The tile has a native NSDraggingDestination rather than competing nested SwiftUI
drop handlers. It snapshots file URLs, web URLs and text from the drag pasteboard
before the source drag ends. Dragging selected Shelf items resolves only those
items' security-scoped bookmarks; external drops no longer scan every Shelf
bookmark, including unrelated offline volumes. Direct sharing activates MORIS so
the user-requested recipient UI is not left behind Finder.

Item-provider URL/text/data requests have an eight-second per-representation
deadline and an exactly-once completion gate. Late callbacks cannot resume an
expired continuation twice. This does not bypass macOS file permissions or
accelerate downloads from iCloud/network storage.

## Internal Shelf drag

The expanded panel no longer installs ancestor mouse-drag recognizers that can
consume events belonging to the native Shelf drag source. Trackpad scroll-based
open/close and tab gestures remain. A drag-session snapshot records the actual
items being dragged, independent of later selection changes. Native URL/string
pasteboard writers replace synthetic file-URL strings. Missing files are not
silently turned into text. The notch cannot hover-close while an internal drag
is active; after completion, normal hover and sharing lifetime rules resume.

AirDrop's symbol is probed for availability. Unsupported systems use the service
image or an available share symbol instead of rendering a blank circle.

## Verification

- `sh Tests/run-shelf-drop-checks.sh`: file/folder references, Unicode, URL text,
  private clipboard paste, mixed item kinds and empty clipboard.
- `sh Tests/run-shelf-sharing-checks.sh`: mixed share payload, callback lifecycle
  beyond two seconds, success/failure/cancellation and independent interaction holds.
  Does not perform a real share or discover nearby recipients.
- Existing shelf, image conversion and notch interaction regression checks.
- `sh Tests/run-share-target-checks.sh`: production native receiver with a private
  pasteboard, source-pasteboard expiry, enabled/disabled state and click dispatch.
- Drop checks include a provider that never responds and a late callback; no
  real file picker, nearby-device scan or AirDrop transfer is performed by tests.

Manual signed-build QA with a second Apple device is still required: drag Finder
files directly to AirDrop, drag selected Shelf files to AirDrop with auto-remove
on, wait more than two seconds in the recipient picker, accept/cancel/fail a share,
then repeat with a browser link. Test Wi-Fi/Bluetooth off and receiving disabled;
MORIS does not change these settings or promise delivery when AirDrop is unavailable.
