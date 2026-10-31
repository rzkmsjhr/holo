# Pulse Audio: Design System & Direction

> **Design Read**: Reading this as: Mobile music streaming application for audiophiles and daily music listeners, in a modern Scandinavian-Swiss utility visual language with vivid solar accents, dial **ENERGY 2 / RHYTHM 1 / MOTION 2**.

---

## 1. Concept & Philosophy
The user requested a **mature, reliable, and "really boring" mobile layout** with **flowing, gesture-reactive elements** and a **bright, modern color mix and match**, available in both **Dark Mode** and **Light Mode**.

- **"Really boring" = Rock-solid mobile maturity**:
  - Predictable, standardized navigation patterns inspired by the best of iOS Human Interface Guidelines and Android Material 3.
  - Standard 3-tab bottom navigation (`Home`, `Search`, `Library`).
  - Persistent sticky Mini-Player resting right above the tab bar.
  - Standard bottom-sheet Now Playing modal with swipe-down-to-dismiss gesture.
  - Familiar list and card spacing that eliminates cognitive load.

- **Flowing & Gesture-Reactive**:
  - Swipe down to minimize Now Playing to Mini-Player; swipe up on Mini-Player to expand.
  - Interactive scrubbing timeline with tactile drag physics and live timestamp updates.
  - Fluid animated audio waveform / equalizer bars that pulse when playing and freeze when paused.
  - Spring-release micro-interactions on buttons (`scale(0.96)` tap down with `cubic-bezier(0.175, 0.885, 0.32, 1.275)` release).
  - Horizontal snap carousels for albums and daily mixes.
  - Swipeable queue items (swipe to remove or reorder).

---

## 2. Palette & Contrast Verification (R-29, R-25)

The active palette is strictly disciplined: **2 core colors + 1 accent color**, anchored by neutral surfaces.

### Core & Accent Colors
| Role | Color Name | Hex Code | Purpose (R-31) |
|---|---|---|---|
| **Core 1 (Primary)** | Solar Ember | `#FF5416` | Key action focal point: play buttons, active scrubber, now playing indicators. |
| **Core 2 (Secondary)** | Night Indigo | `#5A32A3` | Subtle depth, playlist cover gradients, secondary tags. |
| **Accent** | Acid Chartreuse | `#CCFF00` | High-fidelity badges (`Hi-Res FLAC`), live indicator dots, scrub head highlight. |

### Theme Surfaces & Neutrals
#### Dark Mode (Default for evening/listening sessions)
- Canvas / Background: `#0A0C10` (Warm obsidian base)
- Card / Sheet Surface: `#14171F` (Elevated dark slate)
- Border / Divider: `#222736` (Subtle boundary line)
- Primary Text: `#FFFFFF` (WCAG Contrast vs `#0A0C10` = **19.57:1**: PASS)
- Secondary / Muted Text: `#8F9CAE` (WCAG Contrast vs `#0A0C10` = **7.02:1**: PASS)
- Primary CTA Icon / Text: `#0A0C10` on `#FF5416` (WCAG Contrast = **6.09:1**: PASS)

#### Light Mode (Studio Daylight)
- Canvas / Background: `#F6F7F9` (Crisp off-white)
- Card / Sheet Surface: `#FFFFFF` (Pure white card)
- Border / Divider: `#E2E5EB` (Crisp architectural border)
- Primary Text: `#11141A` (WCAG Contrast vs `#F6F7F9` = **17.20:1**: PASS)
- Secondary / Muted Text: `#5C6474` (WCAG Contrast vs `#F6F7F9` = **5.55:1**: PASS)
- Accent Badge Text: `#0A0C10` on `#CCFF00` (WCAG Contrast = **16.66:1**: PASS)

---

## 3. Liveliness Dials & Levers
- **ENERGY: 2 (Balanced)**: The layout remains calm, dependable, and mature, while album artwork and bright Solar Ember accents inject vivid liveliness.
- **RHYTHM: 1 (Predictable)**: Strict adherence to standard mobile list rows, 6-card quick jump grids, and standard bottom bars. No jarring asymmetric layout tricks that hinder music discovery.
- **MOTION: 2 (Interactive)**: Gesture-driven sheet dismissals, smooth interactive timeline scrubbing, fluid equalizer bars, and responsive button spring-press feedback.

### Levers Applied:
1. **One focal point per screen**:
   - Home: Quick Jump grid & Current playing card.
   - Now Playing: Massive, immersive album cover with reactive ambient glow.
   - Library: Filter pill row and active playlist track listing.
2. **Whitespace as structure**: Generous 16px/20px side margins, 44px+ touch targets, and clear typographic hierarchy.
3. **One deliberate accent**: Acid Chartreuse `#CCFF00` reserved for live playback & hi-res audio quality badges.
4. **Identity motif**: The pulsing 4-bar fluid audio equalizer and the signature Solar Ember pill play button.

---

## 4. One-Line Reasons for Major Decisions (R-31)
1. **Why Solar Ember `#FF5416`?**: Provides an unmistakable, high-energy primary focal point that differentiates the app from standard streaming greens and purples.
2. **Why a standardized 3-tab bottom bar?**: It is the gold standard for one-handed mobile ergonomic accessibility on iOS and Android.
3. **Why an interactive Mini-Player?**: Ensures unbroken audio control across every screen without interrupting browsing flow.
4. **Why swipe-down sheet for Now Playing?**: Matches universal iOS/Android modal gestures, making player dismissal instinctual.
5. **Why System Sans typography (`-apple-system, SF Pro, Roboto`)?**: Guarantees maximum legibility at small sizes and effortless 1:1 translation into Flutter and Kotlin Compose.
6. **Why a 6-item quick jump grid on Home?**: Reduces thumb travel to recent favorites from 3 taps down to 1 tap.
