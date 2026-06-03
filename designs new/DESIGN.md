---
name: Antigravity
colors:
  surface: '#0f131d'
  surface-dim: '#0f131d'
  surface-bright: '#353944'
  surface-container-lowest: '#0a0e17'
  surface-container-low: '#181b25'
  surface-container: '#1c1f29'
  surface-container-high: '#262a34'
  surface-container-highest: '#31353f'
  on-surface: '#dfe2f0'
  on-surface-variant: '#b9cacb'
  inverse-surface: '#dfe2f0'
  inverse-on-surface: '#2d303b'
  outline: '#849495'
  outline-variant: '#3a494b'
  surface-tint: '#00dce6'
  primary: '#e3fdff'
  on-primary: '#00373a'
  primary-container: '#00f3ff'
  on-primary-container: '#006b71'
  inverse-primary: '#00696f'
  secondary: '#d1bcff'
  on-secondary: '#3c0090'
  secondary-container: '#7000ff'
  on-secondary-container: '#ddcdff'
  tertiary: '#f9f7ff'
  on-tertiary: '#2a2f46'
  tertiary-container: '#d5daf8'
  on-tertiary-container: '#5a5f78'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#6ff6ff'
  primary-fixed-dim: '#00dce6'
  on-primary-fixed: '#002022'
  on-primary-fixed-variant: '#004f53'
  secondary-fixed: '#e9ddff'
  secondary-fixed-dim: '#d1bcff'
  on-secondary-fixed: '#23005b'
  on-secondary-fixed-variant: '#5700c9'
  tertiary-fixed: '#dce1ff'
  tertiary-fixed-dim: '#c0c5e2'
  on-tertiary-fixed: '#151a30'
  on-tertiary-fixed-variant: '#40465d'
  background: '#0f131d'
  on-background: '#dfe2f0'
  surface-variant: '#31353f'
typography:
  display-lg:
    fontFamily: Space Grotesk
    fontSize: 72px
    fontWeight: '700'
    lineHeight: 80px
    letterSpacing: -0.04em
  display-md:
    fontFamily: Space Grotesk
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Space Grotesk
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
  headline-lg-mobile:
    fontFamily: Space Grotesk
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  title-md:
    fontFamily: Space Grotesk
    fontSize: 20px
    fontWeight: '500'
    lineHeight: 28px
  body-lg:
    fontFamily: Space Grotesk
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-sm:
    fontFamily: Space Grotesk
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-caps:
    fontFamily: Space Grotesk
    fontSize: 12px
    fontWeight: '700'
    lineHeight: 16px
    letterSpacing: 0.1em
  data-mono:
    fontFamily: Space Grotesk
    fontSize: 18px
    fontWeight: '700'
    lineHeight: 24px
    letterSpacing: 0.02em
rounded:
  sm: 0.5rem
  DEFAULT: 1rem
  md: 1.5rem
  lg: 2rem
  xl: 3rem
  full: 9999px
spacing:
  container-padding-desktop: 40px
  container-padding-mobile: 20px
  gutter: 24px
  stack-sm: 8px
  stack-md: 16px
  stack-lg: 32px
---

## Brand & Style
The design system is engineered for high-performance automotive telemetry, targeting professional drivers and track engineers who require split-second data clarity. The brand personality is futuristic, spatial, and ethereal, evoking a sense of weightless precision.

The visual style leverages **Glassmorphism** and **Spatial Depth**. UI elements should appear as if they are floating in a vacuum, supported by subtle background glows rather than physical structures. This is a premium, next-generation engineering aesthetic that balances the raw power of automotive data with the refined elegance of aerospace interfaces. The emotional response should be one of calm focus and technological empowerment.

## Colors
The palette is centered on a "Deep Dark" environment to minimize eye strain during night racing and high-intensity monitoring.

- **Base:** `#050811` (Deep Space) serves as the infinite background.
- **Primary:** `#00f3ff` (Antigravity Blue) is used for critical telemetry data, active states, and primary actions. It should be treated as a light source.
- **Secondary:** `#7000ff` (Stellar Purple) provides depth through subtle light leaks and atmospheric accents.
- **Surface:** `#0a1025` is used for the base layer of glass containers before backdrop filters are applied.
- **Accents:** Use high-vibrancy cyan glows to indicate system health and performance peaks.

## Typography
The typography utilizes **Space Grotesk** to maintain a technical, geometric rhythm. 

- **Data-Heavy Elements:** Use bold weights for telemetry readouts (speed, G-force, RPM) to ensure legibility at a glance.
- **Labels:** Use the `label-caps` style for secondary metadata. The increased letter spacing and uppercase styling differentiate it from dynamic data.
- **Hierarchy:** Maintain a clear distinction between "Reading" (Body) and "Monitoring" (Display). Display sizes are aggressively large to simulate a heads-up display (HUD).

## Layout & Spacing
This design system employs a **Fluid Grid** model designed for wide-screen telemetry dashboards and mobile handhelds.

- **Margins:** Large 40px outer margins on desktop to allow the "floating" effect of the glass panels to be visible against the deep background.
- **Grid:** A 12-column grid for desktop, collapsing to a single column for mobile. 
- **Rhythm:** Spacing follows an 8px base unit. Containers should have generous internal padding (32px+) to maintain an airy, ethereal feel.
- **Spatial Arrangement:** Elements are grouped in logical "pods." Each pod is a self-contained glass container with 24px gutters between adjacent pods.

## Elevation & Depth
Depth is not communicated through traditional shadows, but through **Tonal Layers** and **Luminance**.

- **Level 1 (Background):** Pure `#050811`.
- **Level 2 (Panels):** Glassmorphism surfaces. Use a backdrop blur of `40px` to `60px`. Background color should be `rgba(10, 16, 37, 0.6)`.
- **Level 3 (Interactive):** Elements that are interactive have a `1px` inner stroke of `rgba(0, 243, 255, 0.2)` to define their edges.
- **Atmospherics:** Apply a "Stellar Purple" radial gradient blur (`800px` radius, `0.1` opacity) behind the primary data panels to create a sense of light leaking from the void.

## Shapes
The shape language is fluid and organic. Main containers must use a minimum of **24px (rounded-xl)** corner radii to avoid the "industrial/sharp" look of traditional software, opting instead for a more aerodynamic aesthetic.

- **Main Containers:** 24px - 32px radius.
- **Secondary Elements (Buttons, Inputs):** 12px - 16px radius.
- **Data Tags:** Full pill-shape for status indicators and chips.

## Components

- **Glass Containers:** The core layout component. Must have a `1px` solid border at `rgba(255, 255, 255, 0.1)` and a `40px` backdrop blur.
- **Primary Action Buttons:** Solid `Antigravity Blue` with black text for maximum contrast. Apply a subtle outer glow (cyan, 15px blur, 0.3 opacity) to simulate a powered-on state.
- **Telemetry Cards:** Feature a large display-weight number, a small `label-caps` title at the top left, and a micro-sparkline graph at the bottom using a `1.5px` stroke of the primary color.
- **Inputs:** Darker than the container background, with a `0.5px` border. On focus, the border glows `Antigravity Blue`.
- **Status Chips:** High-contrast pill shapes. "Optimal" status uses a Cyan glow; "Critical" uses a vibrating Magenta/Red, breaking the cool palette to demand immediate attention.
- **Data Gauges:** Semi-circular or linear progress bars with a gradient stroke from `Stellar Purple` to `Antigravity Blue`.