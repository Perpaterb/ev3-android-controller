# EV3 Android Controller — User Stories

An Android app that lets kids (~10 years old) build their own custom controller for a
LEGO Mindstorms EV3 brick using UE5-Blueprint-style visual scripting, then run that
controller live over Bluetooth.

## Personas

- **Mia (10)** — the Builder. Plays with LEGO Mindstorms, can read simple menus, has
  never written text-based code. Uses the app on an Android tablet/phone.
- **Bob** — the Developer. Builds and tests the app on an Ubuntu laptop with mouse and
  keyboard, with and without a real EV3 brick nearby.

## Glossary

- **Project** — one saved controller + blueprint graph.
- **Build mode** — the blueprint editor where the controller and logic are created.
- **Run mode** — full-screen rendering of the built controller, live-driving the EV3.
- **Node** — anything placed on the blueprint canvas (controller node, motor node,
  math node, sensor node, …). Inputs on the left, outputs on the right.
- **Pin** — a connection point on a node. Wires between pins carry data or power.
- **Power (exec) pin** — white pin; the "make it happen" signal, exactly like UE5
  Blueprint execution pins. Pure nodes (e.g. math) have no power pins.

---

## Epic 1 — Project management

**P-01 · See my projects**
As Mia, when I open the app I want to see a list of all my projects so I can pick up
where I left off.
- Project list is the app's home screen.
- Each project shows its name (and ideally a last-edited time).
- Empty state invites me to create my first project.

**P-02 · Create a project**
As Mia, I want to create a new project and give it a name so I can start a new robot
controller.
- "New project" is always visible on the home screen.
- I type a name; a sensible default (e.g. "My Robot 1") is pre-filled.
- The new project opens straight into Build mode with an empty controller node ready.

**P-03 · Open a project**
As Mia, I want to tap a project to open it so I can keep building or drive my robot.
- Opening restores exactly what I last saw: nodes, wires, controller layout, zoom/pan.

**P-04 · Rename a project**
As Mia, I want to edit the name of an existing project so I can keep things organised.
- Rename is reachable from the project list (e.g. long-press or an edit icon).
- Empty names are rejected.

**P-05 · Delete a project**
As Mia, I want to delete a project I no longer need.
- A clear, kid-friendly confirmation ("Delete 'Tank Bot'? This can't be undone.") before
  anything is removed.
- Deleting never touches other projects.

**P-06 · Never lose work**
As Mia, I want everything I build to save automatically so I never lose my robot when
the app closes or my tablet dies.
- All edits persist locally without a manual save button.
- Killing the app mid-edit loses at most a couple of seconds of work.

---

## Epic 2 — EV3 Bluetooth connection

**C-01 · Connect to my brick**
As Mia, I want to connect the app to my EV3 over Bluetooth so my controller can drive
the real robot.
- The app lists paired/nearby EV3 bricks and connects with one tap.
- Required Bluetooth permissions are requested with simple wording.

**C-02 · See connection status**
As Mia, I always want to see whether the app is talking to my EV3 so I know why my
robot isn't moving.
- A persistent status indicator (connected / connecting / not connected) is visible in
  Run mode and reachable from Build mode.

**C-03 · Handle disconnects**
As Mia, when the brick goes out of range or turns off, I want the app to tell me and
let me reconnect easily — not crash or freeze.
- On disconnect: clear message, motors-stop failsafe, one-tap reconnect.

**C-04 · Run without a brick**
As Mia (and Bob), I want to enter Run mode with no EV3 connected so I can try my
controller anyway.
- Controls still work; motor/sensor commands go to a mock brick (and are visible in a
  debug log for Bob).

---

## Epic 3 — Blueprint canvas navigation

**N-01 · Pinch zoom**
As Mia, I want to pinch to zoom the blueprint canvas in and out so I can see my whole
graph or focus on one node.
- Zoom centres on the pinch midpoint; min/max zoom limits prevent getting lost.

**N-02 · Touch pan**
As Mia, I want to drag the canvas background to pan around my blueprint.
- Dragging empty canvas pans; dragging a node's header moves the node (never both).

**N-03 · Mouse scroll zoom** (desktop)
As Bob, I want the mouse scroll wheel to zoom the canvas, centred on the cursor.

**N-04 · Right-click pan** (desktop)
As Bob, I want to hold right-click and drag to pan the canvas, like UE5.

**N-05 · Navigation never locks up**
As Mia, I want pan and zoom to keep working in every editor state — including while
wiring a pin — so I can connect nodes that are far apart.

---

## Epic 4 — Controller designer

**CT-01 · The controller node**
As Mia, I want a controller node sitting in the middle of the build screen that shows
my controller's screen layout, so designing the controller and wiring its logic happen
in one place.
- A new project starts with one empty controller node centred on the canvas.
- The controller node renders a live miniature of the actual Run-mode layout.

**CT-02 · Controller tabs**
As Mia, I want to add tabs to my controller so I can have more than one page of
controls (e.g. "Drive" and "Arm").
- Tabs can be added, renamed, and deleted from the controller node.
- Each tab has its own layout area; pins from all tabs appear on the controller node.

**CT-03 · Add a control**
As Mia, I want to long-press on a blank spot inside the controller to add a control,
choosing from: button, d-pad, slider, toggle switch, light (indicator), and similar.
- Long-press inside the controller opens the add-control menu (distinct from the
  canvas add-node menu).
- The control appears where I pressed and can be repositioned/resized within the tab.

**CT-04 · Name what a control does**
As Mia, when I add a control I must name each thing it can do, so the pins it creates
make sense to me.
- Adding a control prompts for a name per capability, e.g.:
  - Button → name for "pressed" (power out) — e.g. "Forward".
  - Slider → name + range (default 0–100) for its value (int out) and "on change"
    (power out) — e.g. "Speed".
  - Toggle → name for its state (bool out) and "on switch" (power out).
  - D-pad → names per direction (power outs) or a single name with direction outputs.
  - Light → name for its input (it's an *output device*, so its pins are inputs:
    power in + colour/on state in).
- Each named capability becomes a pin on the outside of the controller node.

**CT-05 · Controller pins**
As Mia, I want every control's capabilities to show up as colour-coded pins on the
edge of the controller node so I can wire them to my robot logic.
- Outputs (buttons, sliders, toggles) on the right; inputs (lights, displays) on the
  left.
- Pins are labelled with the names I gave them and grouped by control.

**CT-06 · Edit and remove controls**
As Mia, I want to move, rename, and delete controls on my controller.
- Deleting a control removes its pins; any wires to those pins are cleanly removed
  after a confirmation that tells me which connections will be lost.

---

## Epic 5 — Nodes & wiring (visual scripting core)

**B-01 · Add a node**
As Mia, I want to long-press on a blank part of the blueprint canvas to open the
add-node menu with all the programmable functionality.
- Menu is organised by category (Motors, Sensors, Math, Logic, Flow, …) with the same
  colour coding as the nodes themselves.
- Searchable/filterable for older kids; browsable for everyone.
- The chosen node is placed where I long-pressed.

**B-02 · Move a node**
As Mia, I want to drag a node by its top label (header) section to move it around.
- Body/pin areas never start a node drag.
- Wires follow the node live while dragging.

**B-03 · Rename a node**
As Mia, I want to edit a node's label so I can call it "Left Wheel" instead of
"Motor B".
- The label is cosmetic only — renaming never changes behaviour or breaks wires.

**B-04 · Select a node**
As Mia, I want to tap a node to select it so I can move it, rename it, or delete it.
- Selection is clearly visible (highlight/outline).

**B-05 · Delete a node**
As Mia, I want to delete a selected node.
- All wires attached to it are removed with it.
- The controller node cannot be deleted.

**B-06 · Start wiring from a pin**
As Mia, when I tap a pin I want the editor to make it obvious what I can connect it to.
- The tapped pin highlights.
- Everything else on the blueprint greys out, **except** pins that are compatible with
  the tapped pin, which highlight.
- Pan and zoom still work fully in this mode (see N-05).

**B-07 · Complete a wire**
As Mia, while wiring I want to tap a highlighted compatible pin to connect a wire
between the two pins.
- The wire draws as a curve between the pins (UE5 style) and stays attached as nodes
  move.
- After connecting, the editor returns to normal (nothing greyed out).

**B-08 · Cancel wiring**
As Mia, I want a red ✕ button on screen while in wiring mode so I can back out without
connecting anything.
- Tapping the ✕ (or tapping greyed-out empty canvas) exits wiring mode unchanged.

**B-09 · Only valid connections**
As Mia, I want it to be impossible to wire incompatible pins together so my robot
program can't be "wrong" in ways I don't understand.
- Type rules: power↔power, int↔int, bool↔bool (plus any defined auto-conversions,
  e.g. bool→int, shown explicitly).
- One wire per input pin (a new wire replaces the old one, like UE5); output pins may
  fan out to many inputs. Power output pins connect to one target (use Sequence for
  more).

**B-10 · Disconnect a wire**
As Mia, I want to remove a wire I no longer want (e.g. tap the wire or its pin and
choose disconnect).

**B-11 · Pin colour coding**
As Mia, I want pin colours to tell me what kind of thing each pin carries.
- Power/exec: **white** · Integer: **green** · Boolean: **red** — consistent
  everywhere (pins, wires, add-menu, documentation).
- Wires take the colour of their pin type.

**B-12 · Node colour coding**
As Mia, I want node header colours to tell me what family a node belongs to at a
glance.
- e.g. Motors: orange · Sensors: blue · Math: green · Logic/Flow: grey/red —
  matching the add-node menu categories.

**B-13 · Inputs left, outputs right**
As Mia, I want every node's inputs on its left edge and outputs on its right edge so
data always flows left → right.

---

## Epic 6 — Node library

**L-01 · Motor node**
As Mia, I want a motor node that drives one EV3 motor.
- I must select which physical EV3 port it uses (A, B, C, D).
- Inputs (left): power (white, "run"), speed int 0–100 (green), direction bool
  (red, forward/backward).
- Outputs (right): motor angle (green int), plus power-out to chain the next action.
- Variants/extra inputs as needed: stop, run-for-degrees, run-for-seconds.

**L-02 · Sensor nodes**
As Mia, I want nodes for the EV3 sensors (touch, colour, ultrasonic/IR, gyro) so my
robot can react to the world.
- I must select the physical input port (1–4).
- Each exposes its readings as typed output pins (e.g. touch → bool; distance → int)
  and, where useful, event power-outs ("on pressed").

**L-03 · Math nodes (pure)**
As Mia, I want simple math nodes — add, subtract, multiply, divide, min/max, clamp,
compare (>, <, =) — so I can transform values.
- Pure nodes: **no power pins** — just typed inputs on the left, one result on the
  right (e.g. Add: two green int ins → one green int out; Compare: two ints in →
  bool out).
- They evaluate automatically whenever a powered node downstream needs their value.

**L-04 · Logic & flow nodes**
As Mia, I want Branch (if/else), AND/OR/NOT, and comparison-driven flow so my robot
can make decisions.
- Branch: power in + bool in → "true" power out / "false" power out, exactly like UE5.

**L-05 · Sequence node**
As Mia, I want a Sequence node so one power signal can trigger several actions in
order.
- Power in on the left; numbered power outs (Then 1, Then 2, …) on the right, fired
  in order; outs can be added/removed.

**L-06 · Timing nodes**
As Mia, I want a Wait/Delay node so I can make things happen after a pause.
- Power in, duration in (int, e.g. milliseconds or seconds), power out fired after the
  delay without freezing the rest of the controller.

**L-07 · Value nodes**
As Mia, I want constant-value nodes (a number I type, true/false) so I can feed fixed
values into pins without a control on my controller.

---

## Epic 7 — Run mode

**R-01 · Switch between Build and Run**
As Mia, I want each project to have two main areas — Build and Run — and an obvious
way to switch between them.
- Switching to Run renders my controller full screen; switching back returns me to
  the blueprint exactly as I left it.

**R-02 · My controller, live**
As Mia, in Run mode I want to see the exact controller I built — same tabs, controls,
names, and layout — and use it to drive my robot.
- Tabs are switchable; every control works as designed.

**R-03 · Real-time response**
As Mia, when I press "Forward" I want the robot to move *now*.
- Control events flow through the blueprint graph and out over Bluetooth with no
  perceptible lag (target well under ~100 ms).
- Releasing a button stops what the press started (press/release are both events).

**R-04 · Feedback on my controller**
As Mia, I want output controls (lights, readouts) on my controller to update live from
the blueprint (e.g. a light wired to a touch sensor turns on when the robot bumps a
wall).

**R-05 · Safe stop**
As Mia, I want everything to stop when I leave Run mode, the app loses focus, or the
connection drops — my robot should never run away on its own.

---

## Epic 8 — Developer & platform (Bob)

**D-01 · Run on Ubuntu**
As Bob, I want to build and run the full app on my Ubuntu laptop so I can develop and
test without an Android device.
- One documented command launches the app as a desktop window (this strongly suggests
  a cross-platform framework — e.g. Flutter with its Linux desktop target — so the
  Android and desktop builds share one codebase).

**D-02 · Mouse-equivalent input**
As Bob, on desktop I want mouse equivalents for every touch gesture:
- Scroll wheel = zoom (N-03), right-drag = pan (N-04), click = tap,
  click-and-hold = long-press, left-drag = touch-drag.

**D-03 · Bluetooth from the laptop**
As Bob, I want the desktop build to talk to a real EV3 over the laptop's Bluetooth so
I can test end-to-end without deploying to a phone.

**D-04 · Mock EV3**
As Bob, I want a mock-brick mode that logs every command the app would send (motor
port, speed, direction, …) so I can verify blueprint execution with no hardware.

---

## Suggested colour legend (single source of truth)

| Thing | Colour |
|---|---|
| Power / exec pin & wire | White |
| Integer pin & wire | Green |
| Boolean pin & wire | Red |
| Motor nodes | Orange |
| Sensor nodes | Blue |
| Math nodes | Green |
| Logic / flow nodes | Grey |

## Open questions

1. **Framework** — Flutter (one codebase → Android + Linux desktop) vs. native Android
   + separate test harness? Flutter looks like the natural fit given D-01.
2. **Float type?** Do we need a float pin (e.g. gyro angle, sensor scaling) or do ints
   cover everything for the v1 node set?
3. **Desktop long-press** — click-and-hold is assumed (right-click is taken by pan);
   confirm that feels right.
4. **Press vs. release** — buttons likely need *both* "on press" and "on release" power
   outs (to stop motors). Should that be two named pins per button by default?
5. **Save format** — JSON per project on device? Matters early for forward
   compatibility of kids' saved projects.
6. **Undo/redo in Build mode** — not in the spec, but kids will want it. v1 or later?
