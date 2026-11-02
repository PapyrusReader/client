---
name: "Papyrus"
description: "Existing Flutter visual system for the cross-platform library and reader."
colors:
  light-primary: "#5654A8"
  light-on-primary: "#FFFFFF"
  light-primary-container: "#E2DFFF"
  light-on-primary-container: "#100563"
  light-secondary: "#5D5C71"
  light-secondary-container: "#E3E0F9"
  light-on-secondary-container: "#1A1A2C"
  light-tertiary: "#7A5368"
  light-surface: "#FFFBFF"
  light-on-surface: "#1C1B1F"
  light-surface-container-highest: "#E4E1EC"
  light-on-surface-variant: "#47464F"
  light-outline: "#787680"
  light-outline-variant: "#C8C5D0"
  light-error: "#BA1A1A"
  dark-primary: "#C3C0FF"
  dark-on-primary: "#272377"
  dark-primary-container: "#3E3C8F"
  dark-on-primary-container: "#E2DFFF"
  dark-secondary: "#C7C4DD"
  dark-secondary-container: "#464559"
  dark-on-secondary-container: "#E3E0F9"
  dark-tertiary: "#EAB9D2"
  dark-surface: "#1C1B1F"
  dark-on-surface: "#E5E1E6"
  dark-surface-container-highest: "#47464F"
  dark-on-surface-variant: "#C8C5D0"
  dark-outline: "#928F9A"
  dark-outline-variant: "#47464F"
  dark-error: "#FFB4AB"
  eink-primary: "#000000"
  eink-on-primary: "#FFFFFF"
  eink-primary-container: "#000000"
  eink-on-primary-container: "#FFFFFF"
  eink-secondary: "#404040"
  eink-secondary-container: "#F5F5F5"
  eink-on-secondary-container: "#000000"
  eink-tertiary: "#404040"
  eink-surface: "#FFFFFF"
  eink-on-surface: "#000000"
  eink-surface-container-highest: "#F5F5F5"
  eink-on-surface-variant: "#404040"
  eink-outline: "#000000"
  eink-outline-variant: "#000000"
  eink-error: "#000000"
  eink-black: "#000000"
  eink-white: "#FFFFFF"
  eink-dark-gray: "#404040"
  eink-light-gray: "#C0C0C0"
  eink-container: "#F5F5F5"
typography:
  display-large: {"fontSize": "57px", "fontWeight": 400, "letterSpacing": "-0.25px"}
  display-medium: {"fontSize": "45px", "fontWeight": 400, "letterSpacing": "0px"}
  display-small: {"fontSize": "36px", "fontWeight": 400, "letterSpacing": "0px"}
  headline-large: {"fontSize": "32px", "fontWeight": 400, "letterSpacing": "0px"}
  headline-medium: {"fontSize": "28px", "fontWeight": 400, "letterSpacing": "0px"}
  headline-small: {"fontSize": "24px", "fontWeight": 400, "letterSpacing": "0px"}
  title-large: {"fontSize": "22px", "fontWeight": 400, "letterSpacing": "0px"}
  title-medium: {"fontSize": "16px", "fontWeight": 500, "letterSpacing": "0.15px"}
  title-small: {"fontSize": "14px", "fontWeight": 500, "letterSpacing": "0.1px"}
  body-large: {"fontSize": "16px", "fontWeight": 400, "letterSpacing": "0.5px"}
  body-medium: {"fontSize": "14px", "fontWeight": 400, "letterSpacing": "0.25px"}
  body-small: {"fontSize": "12px", "fontWeight": 400, "letterSpacing": "0.4px"}
  label-large: {"fontSize": "14px", "fontWeight": 500, "letterSpacing": "0.1px"}
  label-medium: {"fontSize": "12px", "fontWeight": 500, "letterSpacing": "0.5px"}
  label-small: {"fontSize": "11px", "fontWeight": 500, "letterSpacing": "0.5px"}
rounded:
  none: "0px"
  sm: "4px"
  md: "8px"
  lg: "12px"
  xl: "16px"
  xxl: "28px"
  full: "9999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
  xl: "32px"
  xxl: "48px"
components:
  button-outlined: {"rounded": "{rounded.md}", "padding": "12px 24px"}
  button-text: {"padding": "8px 12px"}
  input: {"rounded": "{rounded.sm}", "padding": "16px"}
  card: {"rounded": "{rounded.lg}"}
  button-eink: {"backgroundColor": "{colors.eink-black}", "textColor": "{colors.eink-white}", "rounded": "{rounded.none}", "padding": "12px 24px"}
  button-outlined-eink: {"backgroundColor": "{colors.eink-white}", "textColor": "{colors.eink-black}", "rounded": "{rounded.none}", "padding": "12px 24px"}
  input-eink: {"backgroundColor": "{colors.eink-container}", "textColor": "{colors.eink-black}", "rounded": "{rounded.none}", "padding": "16px"}
  chip-eink: {"backgroundColor": "{colors.eink-white}", "textColor": "{colors.eink-black}"}
  chip-eink-selected: {"backgroundColor": "{colors.eink-light-gray}", "textColor": "{colors.eink-black}"}
---

# Design System: Papyrus

## Overview

Papyrus uses its existing Material 3 theme for a readable, adaptive library and reader. Muted violet accents sit on neutral surfaces, with separate light, dark, high-contrast and e-ink themes. This record describes the implemented system, without introducing a new visual identity.

Sources: `app/lib/themes/app_theme.dart`, `design_tokens.dart`,
`color_schemes.g.dart` and `app_motion.dart`. Flutter source remains authoritative.
Frontmatter `px` values represent Flutter logical pixels. Mode prefixes identify
actual palette variants, not interchangeable colors within one theme.

**Key Characteristics:**
- Semantic theme colors and text roles.
- Shared spacing and shape tokens.
- Dedicated e-ink and reduced-motion behavior.

## Colors

The primary accent is muted violet in light mode and pale violet in dark mode.
Secondary colors support tonal controls. Tertiary colors provide a muted rose
accent. Surfaces, text and outlines use the corresponding semantic neutral roles.
E-ink resolves these roles to solid grayscale colors.

The frontmatter records explicit source values. Surface-container roles omitted
from `color_schemes.g.dart`, including `surfaceContainerLow`, retain Flutter's
runtime defaults and are deliberately not assigned inferred hex values here.
High-contrast schemes are generated from the primary seed with contrast level 1.

## Typography

The frontmatter mirrors the explicit Material text scale. The theme does not
specify a custom default font family or line heights. Flutter resolves those
values. Headline, title, body and label roles provide hierarchy without a new
brand font.

E-ink strengthens body-medium/body-small to weight 500 and label-medium/label-small
to 600. Accessibility settings can substitute OpenDyslexic and promote text to
bold. Components inherit these adaptations through the active text theme.

## Layout

The shared spacing scale supplies gaps, padding and margins. Breakpoint tokens
start tablet at 600, small desktop at 840 and large desktop at 1200 logical pixels.
They define 4/8/12 grid columns and 16/24/24 gutters for mobile/tablet/desktop.
Actual pages choose their composition within available width and text scaling.
Statistics defaults to left alignment with shared page margins. Its optional
center alignment limits content width to 1120 logical pixels.

## Elevation & Depth

Standard themes combine Material elevation and tonal surfaces. Shared cards and
elevated buttons use elevation 1, bottom navigation 3 and popup menus 6. These
are Flutter elevation values, not CSS shadow recipes. E-ink component themes use
zero elevation and visible borders. Motion durations live in the sidecar.
`AppMotion` disables motion when requested by the theme or platform settings.

## Shapes

Shared buttons use the md radius, inputs sm, cards lg, dialogs xxl and bottom
sheets xl. E-ink button, input and card themes have square corners. Default input
borders are 1 logical pixel, increasing to 2 for focus/error. E-ink input borders
use 2 at rest and 4 for focus/error. E-ink card themes use a 2-pixel border.

## Components

- **Buttons:** elevated and outlined themes use shared horizontal/vertical
  padding, minimum height 50, and 16-point medium text. Text buttons have smaller
  padding. E-ink buttons become square, instant and semibold. Standard interactive
  state layers otherwise come from Flutter Material.
- **Inputs:** outlined fields use semantic outline, primary focus and error
  colors. E-ink fields use a solid container fill and persistent bold labels.
- **Cards:** standard shared cards have a small elevation and rounded shape.
  Statistics section containers are flat, use `surfaceContainerLow` and a
  semantic outline, and inherit the card shape. Their local 1-pixel border is
  an implementation detail, not an override of the shared e-ink card theme.
- **Chips:** standard choices inherit Material styling. The e-ink theme uses
  white or selected light-gray fills, black text and 2-pixel black borders.
- **Navigation:** bottom navigation maps selected items to primary and other
  items to on-surface-variant. E-ink navigation removes elevation and strengthens
  selected labels. App bars use the surface and on-surface roles.

The sidecar's small HTML/CSS examples preview explicit e-ink theme properties.
They are reference swatches, not substitutes for Flutter widgets or their full
platform interaction behavior.

## Do's and Don'ts

### Do:
- Do resolve colors and typography through the active Flutter theme.
- Do preserve text scaling, accessibility typography and reduced-motion settings.
- Do use existing spacing and radius tokens for shared components.

### Don't:
- Don't hard-code the light palette into adaptive widgets.
- Don't carry standard-theme elevation and animation into e-ink components.
