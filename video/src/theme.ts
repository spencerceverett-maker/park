import type React from "react";
import { Easing, interpolate } from "remotion";

export const FPS = 60;
export const WIDTH = 1920;
export const HEIGHT = 1080;

/** The panel is designed in points; the video shows it at 1.5×, like a Retina screenshot cropped in. */
export const S = 1.5;

export const font = '-apple-system, "SF Pro Text", "SF Pro Display", system-ui, Inter, sans-serif';

/** Light-mode tokens matching the real panel in light appearance, over frosted glass. */
export const color = {
  primary: "rgba(0,0,0,0.85)",
  secondary: "rgba(0,0,0,0.50)",
  tertiary: "rgba(0,0,0,0.28)",
  hover: "rgba(0,0,0,0.05)",
  hairline: "rgba(0,0,0,0.08)",
  accent: "#007AFF",
  panel: "rgba(250,250,251,0.72)",
  panelBorder: "rgba(255,255,255,0.7)",
};

/** Apple product-page palette for the title and end cards. */
export const page = {
  canvas: "#F5F5F7",
  ink: "#1D1D1F",
  muted: "#86868B",
  body: "#6E6E73",
};

/** SF Pro Display at display sizes, with Apple's tight tracking. */
export const display = (size: number, weight = 600, c: string = page.ink): React.CSSProperties => ({
  fontFamily: '"SF Pro Display", -apple-system, system-ui, Inter, sans-serif',
  fontSize: size,
  fontWeight: weight,
  letterSpacing: `${size >= 40 ? -0.025 : -0.01}em`,
  lineHeight: 1.08,
  color: c,
});

/** Every beat of the story, in frames. */
export const T = {
  cursorToIcon: [40, 96] as const,
  clickIcon: 100,
  panelIn: [102, 124] as const,
  cursorToButton: [140, 196] as const,
  clickPark: 206,
  parkingEnd: 236,
  collapse: [222, 290] as const,
  rowIn: [262, 300] as const,
  memoryDrop: [270, 330] as const,
  highlightOut: [300, 360] as const,
  freedIn: [380, 400] as const,
  cursorToRow: [430, 480] as const,
  hoverRow: 482,
  clickRestore: 530,
  panelOut: [532, 544] as const,
  expand: [540, 620] as const,
  endCard: [720, 760] as const,
  total: 1020,
};

/** Apple's critically damped default: settles without overshoot. */
export const settle = Easing.bezier(0.16, 1, 0.3, 1);
/** For things leaving: accelerate away. */
export const away = Easing.bezier(0.55, 0, 0.75, 0.2);
/** For a cursor travelling between targets. */
export const travel = Easing.bezier(0.45, 0, 0.15, 1);

export const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

export const ramp = (frame: number, range: readonly [number, number], easing = settle) =>
  interpolate(frame, [range[0], range[1]], [0, 1], { ...clamp, easing });
