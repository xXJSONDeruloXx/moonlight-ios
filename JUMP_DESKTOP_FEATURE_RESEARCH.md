# Jump Desktop-style feature feasibility research for Moonlight iOS

_Last updated: 2026-03-15_

## Scope

Investigate how feasible it would be to bring the following Jump Desktop-like capabilities to the upstream Moonlight iOS client:

1. **Portrait use on iPhone**
2. **Trackpad mode that is friendlier for desktop productivity**
3. **Keyboard toggle + richer keyboard accessory bar**
4. **Any prior art in upstream Moonlight, Moonlight forks, or related Moonlight clients**

This note focuses on **upstream Moonlight iOS**, relevant open issues/PRs, and the most relevant forks I found:

- upstream Moonlight iOS: https://github.com/moonlight-stream/moonlight-ios
- VoidLink / Fried Fish fork: https://github.com/The-Fried-Fish/VoidLink-previously-moonlight-zwm
- moonlight-ios-NE: https://github.com/TimmyOVO/moonlight-ios-NE
- Moonlight Android: https://github.com/moonlight-stream/moonlight-android
- Moonlight Qt: https://github.com/moonlight-stream/moonlight-qt
- Artemis / Moonlight Noir (Android fork): https://github.com/ClassicOldSong/moonlight-android

---

## Executive summary

### Short version

- **Portrait support** is **feasible** and there is already strong prior art.
  - Upstream is currently landscape-only by plist.
  - Open PRs/forks show this is achievable.
  - The real work is not the plist change itself; it is **live resize / rotation / overlay / on-screen-controls handling**.

- **A richer keyboard bar** is the **lowest-risk first feature**.
  - Upstream already has a 3-finger keyboard toggle and an accessory toolbar.
  - It currently lacks arrow keys, function keys, paging, and a more desktop-focused layout.
  - There is already an open PR adding **Fn and arrow keys**.

- **Native touch / multitouch passthrough** is **protocol-feasible**.
  - Moonlight already has the necessary protocol path (`LiSendTouchEvent`) in other clients / forks.
  - The main blocker is **gesture arbitration / keyboard invocation**, not raw protocol support.

- **Jump Desktop-style zoomed trackpad viewport** is the hardest item.
  - Upstream maintainer commentary is basically correct: current Moonlight trackpad mode is built around **relative mouse deltas**, not authoritative host cursor position.
  - That means Jump’s “zoomed view that follows the cursor until edges, then keeps cursor moving” is **not a clean drop-in extension** of today’s relative trackpad mode.
  - It is still possible, but it should almost certainly be implemented as a **separate desktop-oriented mode**, not as a silent change to the existing gaming-oriented relative mouse mode.

### Recommended implementation order

1. **Keyboard/accessory bar improvements**
2. **Portrait support (likely iPhone-first, then broader rotation/window resizing)**
3. **Native touch passthrough with an alternative keyboard invocation path**
4. **A separate “desktop trackpad zoom” or “pan/zoom” mode**

---

## 1. What upstream Moonlight iOS does today

### 1.1 Orientation: upstream is intentionally landscape-only

Upstream plist:

- `Limelight/Limelight-Info.plist`

Current upstream declares only:

- `UIInterfaceOrientationLandscapeLeft`
- `UIInterfaceOrientationLandscapeRight`

for both iPhone and iPad.

That means **portrait is blocked at the app configuration level** before any streaming UI logic even runs.

### 1.2 Touch modes: upstream has two main touch models

Relevant files:

- `Limelight/Input/RelativeTouchHandler.m`
- `Limelight/Input/AbsoluteTouchHandler.m`
- `Limelight/Input/StreamView.m`
- `Limelight/ViewControllers/StreamFrameViewController.m`

#### Relative touch / “trackpad mode”

`RelativeTouchHandler.m` currently implements a fairly simple laptop-trackpad-like mouse emulation:

- **1 finger drag** → `LiSendMouseMoveEvent(deltaX, deltaY)`
- **1 finger tap** → left click
- **2 finger tap** → right click
- **2 finger vertical movement** → vertical wheel scroll (`LiSendHighResScrollEvent`)
- **long press** → start left drag

Important limitation:

- It only sends **relative mouse deltas**, not authoritative cursor position feedback from the host.
- There is **no client-side viewport zoom/pan** in relative mode.
- There is **no pinch gesture** in upstream relative mode.
- There is **no horizontal scroll** gesture in upstream relative mode.

#### Absolute touch / “touchscreen mode”

`AbsoluteTouchHandler.m` directly updates cursor position via:

- `updateCursorLocation:`
- `LiSendMousePositionEvent(...)`

This mode also supports a `UIScrollView` wrapper in `StreamFrameViewController.m`, but only when absolute touch mode is enabled.

### 1.3 Zoom/pan exists only for absolute touch mode

`Limelight/ViewControllers/StreamFrameViewController.m`:

- creates a `UIScrollView`
- enables zoom/pan only if `_settings.absoluteTouchMode` is true
- puts `_streamView` inside the scroll view

So today:

- **Absolute touch mode**: can zoom/pan the stream view client-side
- **Relative touch / trackpad mode**: cannot zoom/pan the stream view client-side

That split is central to the feasibility question.

### 1.4 Keyboard toggle already exists, but the accessory bar is basic

`Limelight/Input/StreamView.m` currently already has:

- **3-finger tap** to show/hide software keyboard
- a keyboard accessory toolbar with:
  - Done
  - Windows / Meta
  - Escape
  - Tab
  - Shift
  - Control
  - Alt
  - Delete

This means Moonlight iOS already has the structural scaffolding for a Jump-style keyboard enhancement.

What is missing vs your desired Jump-style workflow:

- no **arrow-key page**
- no **function-key page**
- no **keyboard glyph/page switcher**
- no richer desktop editing/navigation cluster
- no configurable gesture count in upstream

### 1.5 Upstream suppresses iOS’s built-in 3-finger editing gestures

`Limelight/Input/KeyboardInputField.m` disables iOS’s 3-finger editing interaction menu, and `StreamView.m` filters `kbProductivity.*` gesture recognizers.

So upstream already knows 3-finger gestures are special and conflict-prone.

---

## 2. Gaps vs the target Jump Desktop experience

## Desired behavior vs upstream status

| Feature | Upstream Moonlight iOS status | Notes |
|---|---|---|
| Portrait streaming on iPhone | **Missing** | Blocked by plist + resize/rotation handling |
| Relative/trackpad mouse mode | **Present** | Basic implementation exists |
| Two-finger vertical scroll in trackpad mode | **Present** | Implemented today |
| Two-finger horizontal scroll in trackpad mode | **Missing** | Not present upstream |
| Pinch-to-zoom display in trackpad mode | **Missing** | Explicitly not supported upstream |
| Pan around a zoomed viewport while staying in trackpad mode | **Missing** | This is the hard part |
| 3-finger keyboard toggle | **Present** | Already implemented |
| Keyboard accessory bar | **Present** | Limited first page only |
| Arrow key toolbar page | **Missing** | Open feature requests / PR exists |
| Function key toolbar page | **Missing** | PR exists |
| Native multi-touch passthrough | **Missing in upstream iOS** | Open PR / strong fork prior art |
| Configurable keyboard gesture count | **Missing in upstream iOS** | Present in VoidLink |
| Better gesture arbitration / desktop-oriented touch UX | **Missing** | Forks explore this |

---

## 3. Public Jump Desktop reference points

I could not fully scrape Jump’s support KB because their support site is behind Cloudflare, but two useful public sources were still available.

### 3.1 App Store description for Jump Desktop

App Store track ID:

- `364876095`
- title: **Jump Desktop (RDP, VNC, Fluid)**
- version observed: **9.8.0**

Publicly listed features include:

- **Full mouse support via touch gestures**:
  - left / right / middle click
  - dragging
  - scrolling
  - precision pointer movement
- **Advanced Bluetooth keyboard support**
  - shortcuts
  - function keys
  - arrow keys
  - macros for keys missing from Apple keyboards
- **Multiple monitor support**
- **External display support as a true monitor**
- **Multi-touch redirection support on Windows 8+**

This lines up closely with the feature gap you described.

### 3.2 Your gesture notes match known Jump Desktop behavior

From your description, the target UX includes:

- trackpad semantics with one-finger pointer movement
- tap / double-tap / long-tap / quick-tap-and-drag patterns
- two-finger scroll
- pinch to zoom
- three-finger tap to show keyboard
- toolbar page(s) for:
  - Esc / Tab / Shift / Control / Option / Command
  - arrow keys and navigation keys
  - function keys

That is a **desktop productivity touch model**, not just a gaming touch model.

A key design implication:

> Jump Desktop is optimized much more aggressively for desktop/remoting productivity, while upstream Moonlight iOS intentionally prioritizes game-friendly relative mouse behavior.

That philosophical difference shows up directly in upstream comments and open issues.

---

## 4. Relevant upstream Moonlight iOS issues and PRs

### 4.1 Portrait / rotation / external display

- **#401 – Portrait Mode**  
  https://github.com/moonlight-stream/moonlight-ios/issues/401
- **#605 – Provides support for portrait screens**  
  https://github.com/moonlight-stream/moonlight-ios/issues/605
- **#441 – iOS Default Landscape Orientation**  
  https://github.com/moonlight-stream/moonlight-ios/issues/441
- **PR #608 – Enable external display support on iPad by allowing the OS to control the window shape and size**  
  https://github.com/moonlight-stream/moonlight-ios/pull/608

Most useful takeaway from PR #608 discussion:

- simply unlocking orientations is not enough
- the streaming UI, stats overlay, and on-screen controls must all handle **live resize and rotation**

That is exactly the difference between “portrait compiles” and “portrait is actually usable”.

### 4.2 Relative trackpad zoom / pan

- **#550 – [Feature Request] Zoom/Pan in relative/touchpad mode**  
  https://github.com/moonlight-stream/moonlight-ios/issues/550
- **#455 – Pinch to zoom in trackpad mode** (closed)  
  https://github.com/moonlight-stream/moonlight-ios/issues/455

Most important upstream maintainer position from #455:

- The problem is **not pinch detection itself**.
- The problem is what happens **after zooming**, because Moonlight’s trackpad mode only knows **relative mouse deltas** and does **not know host cursor position**.
- Without host cursor position, the client cannot cleanly reproduce a Jump/Chrome-Remote-Desktop-style “pan the zoomed viewport while the cursor approaches screen edges” experience.

This is the single most important design constraint for your requested Jump-style trackpad viewport behavior.

### 4.3 Keyboard and missing desktop keys

- **#356 – keyboard special keys**  
  https://github.com/moonlight-stream/moonlight-ios/issues/356
- **#650 – Arrow buttons on virtual keyboard**  
  https://github.com/moonlight-stream/moonlight-ios/issues/650
- **PR #576 – Add a toolbar above the on-screen keyboard with extra keys that are missing from iOS keyboard**  
  https://github.com/moonlight-stream/moonlight-ios/pull/576
- **PR #600 – Add fn 1-12 to toolbar above keyboard to support screen switch**  
  https://github.com/moonlight-stream/moonlight-ios/pull/600

This is the cleanest area to extend.

Moonlight already solved:

- showing the keyboard
- attaching a toolbar
- sending extra keycodes

So adding:

- arrow keys
- F1-F12
- page switching
- more desktop-oriented nav keys

is much less invasive than adding a whole new touch interaction model.

### 4.4 Better touch / native touch passthrough

- **#596 – Touch Control Improvement**  
  https://github.com/moonlight-stream/moonlight-ios/issues/596
- **#597 – Multi-touch Support**  
  https://github.com/moonlight-stream/moonlight-ios/issues/597
- **#636 – Better touch support**  
  https://github.com/moonlight-stream/moonlight-ios/issues/636
- **PR #629 – Add passthrough touch support for windows native multi-touch**  
  https://github.com/moonlight-stream/moonlight-ios/pull/629
- **PR #632 – Native touch passthrough, better keyboard toggle, better remote typing…** (closed)  
  https://github.com/moonlight-stream/moonlight-ios/pull/632
- **PR #628 – Implementation of Native Touch Passthrough and Better Gesture Recognizing** (closed)  
  https://github.com/moonlight-stream/moonlight-ios/pull/628

Most useful takeaway:

- native touch is already considered desirable
- the main argument against shipping it in upstream is **gesture conflict**, especially keyboard invocation and existing Moonlight gesture semantics
- this is very similar to the discussion in Moonlight Android

### 4.5 Right click / gesture ergonomics

- **#499 – Change the right-click gesture from a long press to a two-finger tap**  
  https://github.com/moonlight-stream/moonlight-ios/issues/499
- **#621 – 2 finger tap right click soooo hard to trigger**  
  https://github.com/moonlight-stream/moonlight-ios/issues/621

This matters because a more desktop-oriented touch UX will need more reliable gesture recognition than the current simple recognizer set.

---

## 5. Related Moonlight clients: protocol and design signals

### 5.1 Moonlight Qt already uses native touch passthrough when host supports it

Relevant files:

- `app/streaming/input/abstouch.cpp`
- `app/streaming/input/reltouch.cpp`

Moonlight Qt does this in absolute touch mode:

- if host advertises `LI_FF_PEN_TOUCH_EVENTS`, it sends:
  - `LiSendTouchEvent(...)`
  - `LiSendPenEvent(...)`
- otherwise it falls back to mouse emulation

Implication:

- **the Moonlight protocol path already exists**
- the iOS problem is not “can the protocol do it?”
- the iOS problem is “how do we present touch/keyboard/gesture behavior cleanly on a phone/tablet UI?”

### 5.2 Moonlight Android has native touch code, but it was intentionally disabled upstream

Relevant upstream Android issue:

- **moonlight-android #1271 – Windows multi-touch support**  
  https://github.com/moonlight-stream/moonlight-android/issues/1271

Important maintainer comment there:

- native multitouch was already implemented but disabled
- reason: it conflicts with the app’s gesture-based keyboard invocation
- maintainer explicitly noted a need for:
  - another way to invoke the keyboard
  - likely a zoom feature for small touch targets

That is almost the exact same design problem you are trying to solve on iPhone.

### 5.3 Artemis / Moonlight Noir is a good conceptual precedent for separate pan/zoom mode

Relevant Android fork file:

- `app/src/main/java/com/limelight/utils/PanZoomHandler.java`

That fork adds a **client-side pan/zoom handler** that:

- scales the view up to 10x
- pans it with gesture scrolling
- constrains it within bounds
- stores/restores zoom and pan state

Important point:

- this is implemented as a **separate mode / handler**, not as a silent modification of the normal touchpad semantics

This is probably the most useful cross-platform precedent for your Jump-style “read tiny UI on a phone” use case.

It suggests that on iOS, a distinct **Pan/Zoom mode** or **Desktop Trackpad Zoom mode** is more realistic than trying to stretch the current relative mouse mode beyond its design.

---

## 6. Fork research

## 6.1 VoidLink / Fried Fish fork

Repo:

- https://github.com/The-Fried-Fish/VoidLink-previously-moonlight-zwm

Important branch note from the repo itself:

- latest coding is on branch **`Integration`**

### What appears relevant

#### Portrait / broader orientation support

Relevant file:

- `VoidLink/Limelight-Info.plist`

This branch declares:

- landscape left/right
- portrait
- portrait upside down

and also:

- `UIRequiresFullScreen = false`
- scene support / multiple scenes / external display scene configuration

This is much more aggressive than upstream Moonlight iOS and clearly proves that **portrait-capable packaging is possible**.

There is also explicit runtime orientation logic in:

- `VoidLink/AppDelegate.m`
- `VoidLink/ViewControllers/SWRevealViewController.m`
- `VoidLink/ViewControllers/StreamFrameViewController.m`
- `VoidLink/ViewControllers/SettingsViewController.m`

#### Configurable keyboard gesture and richer input settings

Relevant files:

- `VoidLink/Database/TemporarySettings.h`
- `VoidLink/Input/StreamView.m`
- `VoidLink/ViewControllers/SettingsViewController.m`

This fork adds settings for:

- `keyboardToggleFingers`
- `touchMode`
- `enablePinch`
- `ctrlDownForPinch`
- `passthroughGestures`
- scroll and pinch sensitivity
- orientation unlock

That is directly relevant to the upstream keyboard-vs-native-touch conflict.

#### Multiple touch modes

The fork defines multiple touch modes:

- `RelativeTouch`
- `NativeTouch`
- `AbsoluteTouch`
- `TouchDisabled`
- `NativeTouchOnly`

This is a strong signal that trying to force one universal touch behavior is probably the wrong model.

#### Native touch passthrough

Relevant files:

- `VoidLink/Input/NativeTouchHandler.m`
- `VoidLink/Input/PureNativeTouchHandler.m`
- `VoidLink/Input/NativeTouchPointer.m`

This fork has substantial native touch machinery built around `LiSendTouchEvent(...)` and per-touch pointer tracking.

#### More advanced relative trackpad gestures

Relevant files:

- `VoidLink/Input/RelativeTouchHandler.m`
- `VoidLink/Input/TouchPadGestureHandler.swift`

Notable additions over upstream:

- custom 2-finger right-click recognizer
- inertial scroll
- optional horizontal scroll
- pinch interpretation in trackpad flow

However, important nuance:

- the pinch handling here appears to be more like **host-directed zoom via scroll / ctrl+scroll semantics**, not a true Jump-style client viewport zoom that pans around the streamed image while preserving a coherent trackpad cursor anchor.

So VoidLink is useful prior art, but it does **not** fully solve the exact Jump behavior you want.

### Big caveat

VoidLink is **not a small patch set**.

It is effectively a **heavily divergent product** with:

- new bundle/app structure
- major UI changes
- toolbox/menu systems
- scene support
- extensive settings expansion
- custom OSC/widget systems

Conclusion:

- **Good source of ideas and targeted code borrowing**
- **Bad candidate for direct merge/rebase onto upstream Moonlight iOS**

## 6.2 moonlight-ios-NE

Repo:

- https://github.com/TimmyOVO/moonlight-ios-NE

README claims:

- new multitouch passthrough
- old touch moved to legacy mode
- monitor switching
- 2-finger swipe up/down to open/close keyboard
- 2-finger swipe left/right to switch monitors
- Apple Pencil passthrough mode
- MetalFX / PiP prototypes

Relevant files:

- `Limelight/Input/PassthroughTouchHandler.m`
- `Limelight/ViewControllers/StreamFrameViewController.m`
- `Limelight/Input/StreamView.m`

Useful takeaways:

- it demonstrates another approach to **replacing the 3-finger keyboard gesture** with alternate gestures
- it shows **monitor switching** can be added cheaply as macro-like key sequences
- its plist allows **portrait on iPad**, but still keeps iPhone landscape-only in the version I inspected

Conclusion:

- useful for **gesture alternatives** and **quick UX experiments**
- less directly useful than VoidLink for a polished upstreamable solution

## 6.3 King0fSpace fork

Repo:

- https://github.com/King0fSpace/moonlight-ios

This appears much less directly relevant to the specific portrait/trackpad/keyboard investigation than VoidLink and moonlight-ios-NE.

---

## 7. Feasibility by requested feature

## 7.1 Portrait use on iPhone

### Feasibility

**Feasible: yes**

**Risk / effort: medium**

### Why it is feasible

- Upstream restriction is currently explicit in `Limelight-Info.plist`.
- PR #608 shows the upstream UI can be made more resize-aware.
- VoidLink demonstrates a much broader orientation/windowing model in practice.

### What actually needs work

Not just plist changes:

- stream view sizing during rotation
- stats overlay layout
- on-screen controls layout
- keyboard lift/placement behavior
- handling live transitions while a stream is active

### Lowest-risk implementation strategy

The safest path is probably:

1. **Start with iPhone portrait support only**
2. keep the app full-screen on phone
3. do not immediately take on full iPad Stage Manager / arbitrary resizable-window support
4. adapt the stream/overlay resizing logic only as much as needed for phone rotation first

Why:

- your stated primary use case is **holding the phone vertically**
- that is a narrower, more manageable problem than “support every iPad window shape and external display arrangement”

### Most relevant code starting points

- upstream `Limelight/Limelight-Info.plist`
- upstream `Limelight/ViewControllers/StreamFrameViewController.m`
- upstream `Limelight/Input/OnScreenControls.*`
- PR #608
- VoidLink orientation/windowing code

### Recommendation

**Worth doing.**

This is one of the strongest candidates for an upstreamable improvement if scoped carefully.

---

## 7.2 Three-finger keyboard toggle + richer accessory bar

### Feasibility

**Feasible: yes**

**Risk / effort: low to medium**

### Why it is feasible

Upstream already has:

- keyboard toggle gesture
- hidden input field
- accessory toolbar plumbing
- key sending primitives

So the problem is mostly:

- UX design
- toolbar paging/layout
- key mapping

### Most obvious first improvement

Adapt or supersede **PR #600**:

- add arrow keys
- add F1-F12
- keep existing Esc/Tab/Shift/Ctrl/Alt/Win/Delete

### Better long-term design

Instead of one crowded row, use a **paged accessory bar**:

- **Page 1**: Done, Esc, Tab, Shift, Ctrl, Alt/Option, Win/Cmd, Delete
- **Page 2**: arrows, Home, End, PgUp, PgDn, Insert
- **Page 3**: F1-F12

This would map closely to what you described from Jump Desktop.

### Gesture consideration

If native touch passthrough is ever added, the keyboard gesture should likely become:

- configurable finger count
- or a toolbar/toolbox button
- or both

### Recommendation

**Best first implementation target.**

It is immediately useful, comparatively low-risk, and does not require protocol changes.

---

## 7.3 Native touch / multitouch passthrough

### Feasibility

**Feasible: yes**

**Risk / effort: medium**

### Why it is feasible

Evidence:

- Moonlight Qt already uses `LiSendTouchEvent` / `LiSendPenEvent`
- Moonlight Android has disabled native-touch code for UI reasons, not protocol reasons
- Moonlight iOS has open PR #629
- VoidLink has a large implementation already

### Real blocker

The blocker is not the host protocol path.

The blocker is:

- how to preserve local keyboard access
- how to avoid breaking existing gesture semantics
- how to keep on-screen controls workable

### Best design direction

If this is implemented upstream, it should probably ship with:

1. a **separate touch mode**
2. a **non-gesture keyboard entry point** (button/toolbox)
3. optionally a **configurable finger-count gesture**

### Host compatibility note

This feature should be guarded by host capability checks:

- e.g. `LI_FF_PEN_TOUCH_EVENTS`

In practice this likely means:

- **Sunshine / capable hosts**: native touch works
- **older / unsupported hosts**: fall back to existing mouse emulation

### Recommendation

**Worth doing, but after keyboard improvements.**

---

## 7.4 Jump Desktop-style zoomed trackpad viewport

### Feasibility

**Feasible only with caveats**

**Risk / effort: medium to high**

### Why this is hard

Current upstream trackpad mode is fundamentally based on:

- `LiSendMouseMoveEvent(deltaX, deltaY)`

That means the client knows:

- how much it asked the cursor to move

But it does **not** know:

- the actual authoritative host cursor position
- whether the host clipped/warped/accelerated/locked the cursor
- when the cursor reached a desktop edge or remained centered due to a game/input-capture situation

That is why Jump-style “cursor-centered zoomed viewport that pans until edges” is not straightforward.

### What Jump can likely rely on that upstream Moonlight cannot

Jump Desktop is built around desktop remoting/productivity and its own Fluid protocol stack.

It likely has a more desktop-centric model for:

- cursor semantics
- multi-touch semantics
- keyboard remoting semantics
- window/display awareness

Moonlight’s existing iOS touchpad mode is tuned for **game-compatible relative mouse behavior**.

### Realistic implementation options

#### Option A: Separate client-side pan/zoom mode

Like Android Noir’s `PanZoomHandler` idea:

- pinch zooms the client view
- two-finger pan moves the client view
- host mouse input is suspended or deprioritized while in that mode

Pros:

- easiest to reason about
- no protocol dependency
- good for reading tiny text on phone

Cons:

- not the full Jump “simultaneous zoomed trackpad desktop” experience

#### Option B: Separate desktop-focused trackpad mode

A new mode distinct from today’s gaming-focused relative trackpad mode, with semantics such as:

- desktop-only / productivity-oriented
- possibly based on absolute mouse position rather than pure relative deltas
- pinch+pan enabled

Pros:

- better match for the requested use case

Cons:

- can break camera-locked games or relative-mouse game interactions
- must be clearly separate from existing trackpad mode

#### Option C: Hybrid relative mode with heuristic viewport anchor

Try to fake Jump behavior by keeping a local virtual cursor anchor and moving a zoomed client viewport around it.

Pros:

- closest in spirit

Cons:

- drift-prone
- fragile
- can become confusing when host cursor state diverges from local assumptions

#### Option D: Protocol/server extension

If Sunshine exposed authoritative remote cursor position/state to the client, this feature becomes much more realistic.

Pros:

- cleanest long-term answer

Cons:

- not client-only anymore
- outside current upstream iOS scope

### Recommendation

Do **not** bolt this directly onto the current `RelativeTouchHandler` semantics.

Instead, if you want to pursue it:

- create a **new explicit mode** such as:
  - `Desktop Trackpad Zoom`
  - `Pan/Zoom`
  - `Productivity Trackpad`

That keeps existing game-friendly behavior intact while allowing a more experimental desktop-friendly behavior.

### Bottom line

**This is the least upstream-friendly of the requested features unless scoped as a separate mode.**

---

## 7.5 Better 2-finger right-click / trackpad gesture ergonomics

### Feasibility

**Feasible: yes**

**Risk / effort: low**

This is a good cleanup target regardless of the larger feature plan.

Forks like VoidLink suggest more robust custom recognizers can improve:

- 2-finger tap reliability
- gesture conflict handling
- edge gesture exclusion

This would improve trackpad-mode usability even before tackling zoom/pan.

---

## 8. Most promising code to borrow or adapt

## Upstream Moonlight iOS

- `Limelight/Input/StreamView.m`
  - current keyboard toggle and accessory bar scaffolding
- `Limelight/ViewControllers/StreamFrameViewController.m`
  - current absolute-touch-only zoom/pan wrapper
- `Limelight/Input/RelativeTouchHandler.m`
  - current relative trackpad behavior

## Upstream PRs

- **PR #600**
  - best starting point for keyboard bar enrichment
- **PR #608**
  - best starting point for rotation/resize support investigation
- **PR #629**
  - best starting point for native touch passthrough investigation

## VoidLink

- `VoidLink/Input/NativeTouchHandler.m`
- `VoidLink/Input/PureNativeTouchHandler.m`
- `VoidLink/Input/RelativeTouchHandler.m`
- `VoidLink/Input/TouchPadGestureHandler.swift`
- `VoidLink/Input/StreamView.m`
- `VoidLink/ViewControllers/SettingsViewController.m`
- `VoidLink/Limelight-Info.plist`

Usefulness:

- **high as reference**
- **low as direct cherry-pick source** due to heavy divergence

## moonlight-ios-NE

- `Limelight/Input/PassthroughTouchHandler.m`
- `Limelight/ViewControllers/StreamFrameViewController.m`
- `Limelight/Input/StreamView.m`

Usefulness:

- good for quick gesture alternatives and monitor-switch ideas

## Android Noir / Artemis

- `app/src/main/java/com/limelight/utils/PanZoomHandler.java`

Usefulness:

- best conceptual reference for a **separate client-side pan/zoom mode**
- not a direct code port target

---

## 9. Suggested roadmap if this were implemented upstream

## Phase 1 — keyboard/accessory bar refresh

Goals:

- keep existing gesture
- add arrows + F-keys + paging
- possibly add Home/End/PgUp/PgDn

Why first:

- lowest risk
- immediately improves desktop productivity
- most upstreamable

## Phase 2 — portrait support, iPhone-first

Goals:

- allow portrait on iPhone
- make stream view + overlays survive rotation
- avoid taking on all iPad windowing complexity initially

Why second:

- directly supports your use case
- clear user value
- isolated enough to ship incrementally

## Phase 3 — native touch passthrough mode

Goals:

- add optional native touch mode for Sunshine/capable hosts
- provide alternative keyboard entry path
- keep current emulated modes intact

Why third:

- protocol is already there
- biggest remaining work is UI/gesture arbitration

## Phase 4 — separate desktop pan/zoom / productivity trackpad mode

Goals:

- add opt-in phone-friendly desktop viewing mode
- do not break current gaming-oriented relative trackpad mode

Why fourth:

- this is the most experimental design
- best done after keyboard + portrait + touch mode architecture are cleaner

---

## 10. Overall recommendation

If the goal is “make Moonlight iOS much better for phone-as-remote-desktop productivity,” then I would prioritize the work like this:

1. **Keyboard bar / missing keys** — strong ROI, low risk  
2. **Portrait support** — strong ROI, medium risk  
3. **Native touch passthrough** — medium ROI, medium risk, strong protocol precedent  
4. **Jump-style zoomed trackpad viewport** — useful, but should be a separate explicit mode and will take the most design iteration

My current take is:

- **Yes**: portrait is very worth pursuing
- **Yes**: richer keyboard is very worth pursuing
- **Yes**: native touch passthrough is realistic if keyboard access is redesigned
- **Maybe, but as a separate mode**: Jump Desktop-style zoomed trackpad viewport

If I were turning this into implementation work next, I would start by prototyping:

1. a **paged keyboard accessory bar**, and
2. a **minimal portrait iPhone stream layout**

before touching the more experimental trackpad viewport idea.

---

## 11. Repo / remote notes

Local checkout currently only had the upstream repo configured as a git remote when I started the investigation.

I did **not** add a push remote for a personal fork because I don’t want to guess the correct GitHub repo URL/owner.

If you want me to push work later, send the fork URL you want used and I can add it explicitly.
