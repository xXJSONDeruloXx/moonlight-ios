# Desktop Trackpad + Pan/Zoom plan

## Goal

Add a **separate desktop-oriented touch mode** to Moonlight iOS that keeps relative/trackpad mouse input for cursor movement, while adding **client-side pinch zoom + panning** of the streamed view.

This is intentionally **not** a rewrite of the existing Touchpad mode.

## Why a separate mode

Upstream Touchpad mode is gaming-oriented and currently uses:

- 1-finger drag for relative mouse movement
- 2-finger vertical movement for host scrolling
- 2-finger tap for right click

Trying to silently bolt view pan/zoom onto that mode creates gesture conflicts.

A separate mode lets us optimize for desktop/productivity use without regressing the existing mode.

## Proposed user-facing behavior

Add a third Touch Mode option:

1. **Touchpad**
2. **Desktop**
3. **Touchscreen**

### Desktop mode behavior

- **1 finger drag**: move host cursor with relative mouse input
- **1 finger tap**: left click
- **2 finger tap**: right click
- **2 finger vertical move at 1x zoom**: host scroll (same as today)
- **Pinch**: client-side zoom of the stream view
- **2 finger pan while zoomed in**: pan the zoomed client viewport
- **Zoom back to 1x**: returns 2-finger vertical movement to host scrolling

## Initial implementation scope

### Phase 1

- Persist a new `desktopTrackpadMode` setting
- Insert a new `Desktop` segment into the existing touch mode selector
- Reuse the existing relative touch handler with a mode-aware path
- Wrap the stream view in a `UIScrollView` for Desktop mode too
- Enable scroll view pinch-to-zoom in Desktop mode
- Only enable scroll view 2-finger panning when zoomed in
- Expose a small state flag from `StreamView` so the relative touch handler knows when view panning is active

### Phase 2

- Tune touch delivery latency for the scroll view wrapper
- Add a quick reset-to-1x affordance if needed
- Consider optional horizontal host scroll or alternate scroll gestures while zoomed

## Inspiration used

This plan borrows ideas from the `zwm` / VoidLink family, but keeps the implementation intentionally small and upstream-shaped:

- separate desktop-oriented behavior rather than replacing all touch modes
- pinch/pan on the client side instead of trying to infer authoritative host cursor position
- preserving base Moonlight relative mouse behavior wherever possible

## Non-goals for this branch

- portrait support
- native touch passthrough
- large settings UI redesign
- toolbox / overlay menus
- dynamic Jump Desktop-style auto-following viewport centered on authoritative host cursor state

## Validation plan

- build the iOS target after each major step
- verify touch mode selection persists
- verify existing Touchpad and Touchscreen modes still behave as before
- verify Desktop mode enables:
  - cursor movement
  - left click
  - right click
  - scroll at 1x zoom
  - pinch zoom
  - 2-finger pan while zoomed
