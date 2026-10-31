# Display layouts: design

## Why

The MacBook moves between two spots: beside an external monitor, or under it. Each move meant opening System Settings → Displays → Arrange and dragging the displays around. Pane now does that with a double-tap.

## What it does

- When any external monitor is connected, Pane listens for **1 minute**.
- During that minute, double-tapping a modifier key on its own applies a saved layout. Outside that minute, double-taps do nothing.
- Defaults:
  - **Mac on left**: double-tap **Option**. Mac left of the monitor, bottom edges aligned, menu bar on the Mac.
  - **Mac below**: double-tap **Command**. Mac under the monitor, centered, menu bar on the Mac.
- A short on-screen message confirms the layout (or explains why it couldn't be applied).
- Layouts are defined by rules, not saved coordinates, so they work with any monitor size.

## Settings → Displays

- On/off switch: "Arrange displays when a monitor is connected" (on by default).
- List of layouts with a thumbnail, name, trigger and summary; + / − / ⋯ (Edit, Apply Now, Restore Default Layouts).
- Editor: name, double-tap key (Option, Command, Control, Shift; one layout per key), Mac position (left, right, above, below), alignment (top/center/bottom edges, or left/center/right edges), menu bar (Mac or monitor), live preview, Apply Now.

## Decisions

- **Double-tap:** the key pressed and released on its own, held under 0.35 s, with the second press within 0.45 s of the first release. Any ordinary key press or a second modifier in between cancels it, so shortcuts like ⌘C never trigger a layout.
- **Which monitor:** the one just connected. Other external monitors keep their positions.
- **Lid closed:** nothing happens (there is no built-in display to arrange).
- **Menu bar:** the display placed at the global origin becomes the main display, which carries the menu bar.
- **Command line:** `Pane --apply-layout "<name>"` applies a saved layout and exits, for scripting and testing.
- **Not yet:** choosing the layout automatically with the camera. That would pick between these same layouts.

## Code

| File | Role |
|---|---|
| `Sources/PaneCore/DisplayLayout.swift` | Layout model, origin math, `DoubleTapDetector` |
| `Sources/Pane/DisplayLayoutStore.swift` | Saved layouts (`displayLayouts.v1`) and on/off switch (`displayArrangementEnabled`) |
| `Sources/Pane/DisplayArranger.swift` | Applies a layout with `CGBeginDisplayConfiguration` / `CGConfigureDisplayOrigin` / `CGCompleteDisplayConfiguration(.permanently)` |
| `Sources/Pane/DisplayShortcutController.swift` | Detects a connected monitor, listens for one minute, shows the confirmation |
| `Sources/Pane/SettingsDisplays*.swift` | The Displays settings tab and editor |
| `Tests/PaneTests/DisplayLayoutTests.swift`, `DisplayLayoutStoreTests.swift` | Origin math, double-tap rules, persistence |
