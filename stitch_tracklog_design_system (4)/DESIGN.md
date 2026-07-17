---
name: Cyber-Spatial Tech
colors:
  surface: '#0f1417'
  surface-dim: '#0f1417'
  surface-bright: '#353a3d'
  surface-container-lowest: '#0a0f12'
  surface-container-low: '#171c1f'
  surface-container: '#1b2023'
  surface-container-high: '#262b2e'
  surface-container-highest: '#313539'
  on-surface: '#dfe3e7'
  on-surface-variant: '#b9cacb'
  inverse-surface: '#dfe3e7'
  inverse-on-surface: '#2c3134'
  outline: '#849495'
  outline-variant: '#3a494b'
  surface-tint: '#00dce6'
  primary: '#e3fdff'
  on-primary: '#00373a'
  primary-container: '#00f3ff'
  on-primary-container: '#006b71'
  inverse-primary: '#00696f'
  secondary: '#dcfdff'
  on-secondary: '#00373a'
  secondary-container: '#00f1fd'
  on-secondary-container: '#006a6f'
  tertiary: '#fff7e9'
  on-tertiary: '#3b2f00'
  tertiary-container: '#ffd93d'
  on-tertiary-container: '#725e00'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#6ff6ff'
  primary-fixed-dim: '#00dce6'
  on-primary-fixed: '#002022'
  on-primary-fixed-variant: '#004f53'
  secondary-fixed: '#6ff6ff'
  secondary-fixed-dim: '#00dce6'
  on-secondary-fixed: '#002022'
  on-secondary-fixed-variant: '#004f53'
  tertiary-fixed: '#ffe173'
  tertiary-fixed-dim: '#e8c426'
  on-tertiary-fixed: '#221b00'
  on-tertiary-fixed-variant: '#554500'
  background: '#0f1417'
  on-background: '#dfe3e7'
  surface-variant: '#313539'
  background-deep: '#030712'
  surface-glass: rgba(15, 23, 42, 0.6)
  outline-cyan: rgba(0, 243, 255, 0.2)
  on-surface-muted: '#94a3b8'
typography:
  display-lg:
    fontFamily: Space Grotesk
    fontSize: 30px
    fontWeight: '700'
    lineHeight: 36px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Space Grotesk
    fontSize: 20px
    fontWeight: '700'
    lineHeight: 28px
  body-lg:
    fontFamily: Space Grotesk
    fontSize: 16px
    fontWeight: '500'
    lineHeight: 24px
  body-sm:
    fontFamily: Space Grotesk
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-caps:
    fontFamily: Space Grotesk
    fontSize: 10px
    fontWeight: '700'
    lineHeight: 16px
    letterSpacing: 0.2em
  label-data:
    fontFamily: Space Grotesk
    fontSize: 11px
    fontWeight: '700'
    lineHeight: 14px
  chart-tick:
    fontFamily: Space Grotesk
    fontSize: 8px
    fontWeight: '700'
    lineHeight: 10px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  margin-mobile: 16px
  gutter-md: 16px
  padding-card: 16px
  stack-sm: 8px
  stack-xs: 4px
---

## Brand & Style
The brand personality is high-precision, technical, and futuristic, evoking a "Mission Control" or "Advanced R&D" atmosphere. It targets technical professionals and project managers in automotive or aerospace industries who require immediate, glanceable data insights.

The design style is a sophisticated **Glassmorphism** mixed with **Cyberpunk** accents. It utilizes deep spatial backgrounds, frosted glass panels with semi-transparent blurs, and high-energy cyan glows to create a sense of depth and digital sophistication. The UI feels like a holographic interface—lightweight yet powerful, with sharp geometric precision.

## Colors
The palette is dominated by a deep "Spatial" dark theme.
- **Primary/Secondary**: A high-vibrancy Cyan (#00f3ff) used for critical data, active states, and glowing accents. This color serves as the primary "energy" source for the UI.
- **Background**: A near-black navy (#030712) provides the foundation, often layered with subtle radial gradients to simulate depth.
- **Surface**: Translucent Slate-900 blurs are used for containers, ensuring the background texture remains visible while providing legibility.
- **Feedback**: Success and active states are synonymous with the cyan glow, while muted states utilize mid-tone slates to recede.

## Typography
The system uses **Space Grotesk** exclusively to maintain a technical, geometric aesthetic. 

- **Hierarchy**: Distinction is created through extreme variations in scale and letter-spacing rather than multiple font families. 
- **Data Display**: Large numerical values (24px+) utilize the cyan glow and bold weights to emphasize project metrics.
- **Labels**: Meta-information and category headers use a strict "All-Caps" style with wide tracking (0.2em) to mimic blueprint or technical documentation.
- **Mobile Considerations**: Headlines scale down to 20px-24px for mobile devices to maintain density without sacrificing the bold character.

## Layout & Spacing
The layout follows a fluid-to-grid transition. On mobile, a single-column stack is standard, moving to a 2-column grid for smaller metric cards.

- **Safe Zones**: A standard 16px (1rem) margin is maintained on all screen edges.
- **Rhythm**: Vertical spacing between sections (cards) is a consistent 16px. Interior card spacing also uses 16px padding to ensure data elements don't feel cramped.
- **Compactness**: For grouped data points (like mini-stats inside a card), a 4px or 8px "stack" is used to show relationship through proximity.

## Elevation & Depth
Depth is not communicated via shadows, but through **Tonal Layering and Translucency**:

- **Layer 0**: Deep background (#030712) with faint radial glow textures.
- **Layer 1**: Glass panels (Slate-900/60%) with a 16px backdrop blur and a 1px cyan border at 20% opacity.
- **Layer 2**: Active "Glow" states. Elements that require focus use `text-shadow` or `filter: drop-shadow` in Cyan to appear as if they are emitting light.
- **Interaction**: Hovering over panels increases the border opacity to 40%, creating a subtle "wake up" effect.

## Shapes
The shape language combines friendly curves with technical precision.
- **Panels/Cards**: Use `1rem` (rounded-xl) for a modern, high-end feel.
- **Status Tags/Indicators**: Use "Pill-shaped" or custom "Blunted" corners (like the Active Session badge) to suggest a futuristic military/tech aesthetic.
- **Visual Accents**: Buttons and small interaction points often feature a "Full" roundedness (pill) to distinguish them from structural content containers.

## Components
- **Glass Cards**: The primary container. Must have a backdrop-blur (16px), a semi-transparent dark fill, and a 1px border using the `outline-cyan` variable.
- **Glow Buttons**: Primary actions should have a cyan background with a pulse animation or a strong drop-shadow glow. Secondary actions use the outline style.
- **Data Progress Bars**: Backgrounds should be nearly invisible (white/5%), with the fill being solid Cyan and a horizontal glow effect on the bar itself.
- **Bottom Navigation**: Fixed position, blurred background. Active items use a "Glow Bar" indicator at the bottom and an `active-icon` fill property.
- **Metric Badges**: Small, high-contrast badges with wide letter-spacing for status (e.g., "ACTIVE SESSION"). Often use a secondary fill of cyan/20% to highlight relevance.