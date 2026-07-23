# GolfTracker sealed enclosure + thumb-knob shaft clamp

A slim, no-wiggle mount that **clamps to the club shaft just below the grip**,
**loosens by hand** to slide down for bag storage, and re-seats repeatably at the
grip edge. Three printed parts plus a small hardware kit. Sized for a
**24 × 27 × 30 mm taped bundle** and shafts of **44–49 mm circumference
(≈14.0–15.6 mm diameter)** — one clamp covers a whole set of clubs.

- **body** — sealed box for the bundle, integral with the **upper** clamp half,
  the lid flange, a **grip-edge register lip**, and two ear tabs with captive
  nut pockets.
- **lid** — gasketed, screw-down cap (watertight), with a plugged USB port.
- **clamp** — the **lower** clamp half with matching ear tabs.

### How the clamp works

- **Four M4 star thumb-knobs, two per side (near both ends).** Two per side keeps
  the two halves from splaying open at the ends, so the grip is rigid along the
  whole length. Each knob's M4 × 25 mm stud passes up through the clamp/body ear
  tabs into a **captive M4 nut** in the body ear.
  **Turn to lock, loosen a few turns to release** — no tools.
- **No-wiggle grip** comes from a **1.5 mm rubber liner** + knob tension, not
  print tolerance. The liner is tuned so, loosened, the mount **slides with a
  push but won't creep** (stays parked on the lower shaft).
- **Grip-edge registration:** slide up until the register lip butts the bottom
  of the grip — repeatable position every round, so the per-club distance holds.
- The knobs mount from the **underside** so they clear the box; the 25 mm studs
  are longer than needed and the tips protrude a few mm past the nuts (harmless,
  or snip them).

## Slim vs. earlier lever version

Switching from the big adjustable levers to ~20 mm star knobs cut the printed
width from ~64 mm to **~59 mm** (the ears were then widened slightly so the
captive-nut pockets keep a solid wall), and the protruding hardware from a 44 mm handle
to a small knob. The remaining width is set by the knob's turning circle needing
to clear the bore core — a smaller knob would slim it further. **If your star
knob is larger than ~20 mm diameter, bump `knob_dia` in `generate_enclosure.py`
and re-run** so the ears widen to keep clearance.

## Test-fit note

The stud/nut/ear mechanism is the fussiest part and the one I can't verify
without a physical print. Print a cheap **PETG proof first** to confirm the studs
reach the nuts and the knobs turn freely, then order the nylon.

## Shaft size

Golf shafts just below the grip measure ~**44–49 mm circumference (≈14.0–15.6 mm
dia)** depending on the club. The bore (**16.3 mm**) is sized so the **largest
(49 mm) fits** while the halves still close far enough to grip the **smallest
(44 mm)** — the grip is the **1.5 mm liner being squeezed** by the adjustable
knobs, so you just tighten each club to firm. One clamp covers a whole set. Notes:
- Grip squeeze available at full close ranges ~**0.35 mm/side at 44 mm** up to
  ~1 mm+ at 49 mm; you stop tightening when firm. The **44 mm (thin) end is the
  lightest grip** — if a thin club slips under a hard swing, use a **2 mm liner**
  (more squeeze across the range) or slide the mount slightly lower.
- Clubs **thinner than 44 mm**: slide lower (shaft narrows) or reprint smaller.
- Parametric: `shaft_circ_min` / `shaft_circ_max` / `shaft_clear` / `liner` in
  `generate_enclosure.py` set the range. Re-measure and re-run to retune.

## Files

| File | Purpose |
|---|---|
| `body.stl`, `lid.stl`, `clamp.stl` | The three parts to print |
| `generate_enclosure.py` | Parametric generator — edit params, re-run |
| `preview.png` | Exploded render |
| `old_v1/` | Superseded single-piece zip-tie clip |

## Hardware kit (not printed)

| Item | Qty | Where | Notes |
|---|---|---|---|
| **M4 x 25 mm Thread Clamping Knob, Star Hand Knob (thumb screw), 30 Pcs** | 1 pack (use 4) | Amazon | Two per side (near both ends); the daily hand-lock/release |
| M4 hex nut — **standard (DIN 934 / ISO 4032), M4 × 0.7, 18-8 stainless, ~3.2 mm tall / 7 mm across flats** | 4 | Amazon / hardware | Captive in the four body-ear pockets; the knob studs thread into these. **Not** a thin/jam nut |
| M3 × 12–13 mm self-tapping screw — **thread-forming for plastic, FLAT (countersunk) head, Phillips/cross drive, 18-8 stainless** | 4 | Amazon / McMaster | Lid → flange, into ~12 mm-deep 2.5 mm pilot bosses. **The lid holes are countersunk** so flat heads sit flush. **Not** machine screws (those need a nut). Heat-set upgrade in `GolfSwingTracker.md` §5 |
| Rubber/silicone liner ~1.5 mm (or inner tube / self-fusing silicone tape) | 1 | Amazon / bike shop | Cradle liner — grip, damping, park-friction |
| Rubber/neoprene sheet ~2 mm (gasket) or silicone RTV | 1 | Amazon / hardware | Seals the lid in the flange recess |
| Silicone blanking plug ~11 mm | 1 | Amazon / hardware | Seals the USB charging port |
| Thin neoprene foam scrap | — | (already in main BOM) | Zero-wiggle bundle shim |

Tune printed holes with `stud_clear`, `nut_r`, `knob_dia`, and `lid_pilot_d` in
the generator to match your exact hardware.

## Print settings

- **Nylon PA12 (best) or PETG.** Not PLA. Walls 4+, infill 50 %+, 0.2 mm layers.
- Print liner and gasket from sheet stock. Minimal supports (body cavity up,
  clamp cradle up, lid flat).

## Getting it printed

Upload `body.stl`, `lid.stl`, `clamp.stl` to a service (**Craftcloud, Xometry,
JLCPCB, PCBWay, Treatstock, Shapeways**), pick **Nylon PA12**. Buy the hardware
separately (Amazon / McMaster). Do a **PETG proof print first** (see test-fit
note). **Meshy.ai won't work** — it makes organic meshes, not tolerance-accurate
parts.

## Assembly

1. Line both cradles with the rubber liner. Press an M4 nut into each body-ear
   pocket.
2. Tape the bundle into the box (sensor **+Z toward the clubhead**, USB aligned
   to the port) with a foam shim; fit the gasket; screw the lid down; plug USB.
3. Put the two halves around the shaft; pass a thumb-knob up through each side
   into its captive nut (four total). Slide the mount **up until the register lip
   butts the grip**.
4. **Hand-tighten all four knobs** — firm, no wiggle. Tune the liner thickness so
   locked = firm, loose = slides.
5. Set that club's **sensor-to-clubface distance** in the app (from the register
   lip to the face); fine-tune vs a launch monitor.

**Storage:** loosen the four knobs, slide the mount **down toward the head** (shaft
narrows, slides easily; liner holds it parked), bag the club. Next round: slide
up to the grip register, hand-tighten.

## Size & mass

~**59 × 44 × 53 mm**, roughly **28–53 g** printed in nylon, before hardware —
plus the two small knobs. A smaller knob would slim the width further.
