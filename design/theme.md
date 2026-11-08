# Golden Hour theme: "Family wreath"

Taken from the reference illustration (2026-11-07): warm folk-art style, a family in a circle,
hand-drawn hair strands, a wreath of leaves, rosy cheeks. This replaces the navy/violet theme.

## Palette

| Token        | Hex       | Taken from          | Used for                                         |
|--------------|-----------|---------------------|--------------------------------------------------|
| terracotta   | `#E0785A` | background          | App and widget background                        |
| terracottaDeep | `#C8603F` | background shadow | Pressed states, outer ring edge                  |
| cream        | `#F4EAD0` | faces               | Cards, the clock face, primary surfaces          |
| ink          | `#233C7A` | dark hair           | All body text on cream; clock hands; member arcs |
| cornflower   | `#4F74B8` | hair highlights     | "Maybe free" arcs, secondary strokes             |
| ochre        | `#D9A441` | gold hair strands   | Overlap glow, the family-time arc, primary buttons |
| blush        | `#EF8A73` | cheeks              | Avatar cheeks, "now" dot, small highlights       |
| bark         | `#5B2A1E` | leaves              | Wreath leaves, captions on cream, dividers       |
| speckle      | `#FFF8EC` | white dots          | Tiny decorative dots on terracotta only          |

## Contrast rules
- Body text goes on **cream** in **ink** (about 10:1) or **bark** (about 11:1).
- Cream text on terracotta only for large titles (20pt+ bold). It measures about 2.6:1, so never use it for small text.
- Buttons: ochre fill with ink text (about 5:1).

## Style
- **Circle first.** The family circle is the core shape: the widget clock, the avatars and the home header are all circles framed by a bark-leaf wreath.
- **One ring.** The clock has a single 24h ochre ring, split into 30-minute cells. A cell's opacity shows how many people are free then: 0 → 0.1, 1 → 0.3, 2 → 0.5, 3 → 0.75, all → 1.0 plus a soft glow. A key with the counts sits under the clock, so the opacity is never the only cue.
- **Avatars** are cream discs with an ink hair cap and two blush cheek dots, so there are no photos to collect.
- **Corners and type**: radius 24 on cards; buttons are capsules. Font: a rounded humanist face (SF Pro Rounded on iOS).
- A few speckle dots on the terracotta background; never on cream.
