import React from "react";
import { AbsoluteFill, Img, interpolate, Sequence, staticFile, useCurrentFrame } from "remotion";
import {
  BrowserContent,
  BrowserToolbar,
  Cursor,
  FigmaContent,
  FigmaToolbar,
  MenuBar,
  TerminalContent,
  Wallpaper,
  Window,
  WarpToolbar,
} from "./Desktop";
import { FIRST_ROW_ICON, Panel, PANEL_WIDTH } from "./Panel";
import { away, clamp, display, font, page, ramp, settle, T, travel, WIDTH } from "./theme";

/** The status item's centre, and the panel hanging from it. */
// Measured from a rendered frame: the Ⓟ status item's centre.
const ICON = { x: 1600, y: 18 };
const PANEL = { left: Math.min(ICON.x - PANEL_WIDTH / 2, WIDTH - PANEL_WIDTH - 14), top: 36 + 9 };
const ROW_TARGET = { x: PANEL.left + FIRST_ROW_ICON.x, y: PANEL.top + FIRST_ROW_ICON.y };

const PARK_BUTTON = { x: PANEL.left + PANEL_WIDTH / 2 + 40, y: PANEL.top + 24 + 46 + 18 + 24 };
const ROW_HOVER = { x: PANEL.left + PANEL_WIDTH - 120, y: ROW_TARGET.y };

type WindowSpec = { id: string; x: number; y: number; w: number; h: number; delay: number };
const WINDOWS: WindowSpec[] = [
  { id: "browser", x: 110, y: 96, w: 1000, h: 660, delay: 0 },
  { id: "figma", x: 640, y: 210, w: 1080, h: 640, delay: 5 },
  { id: "terminal", x: 230, y: 540, w: 780, h: 380, delay: 10 },
];

/** Moves a window between its place on the desktop (t=0) and the parked row (t=1). */
const parkTransform = (spec: WindowSpec, t: number): React.CSSProperties => {
  const cx = spec.x + spec.w / 2;
  const cy = spec.y + spec.h / 2;
  const scale = interpolate(t, [0, 1], [1, 36 / spec.w], clamp);
  return {
    translate: `${(ROW_TARGET.x - cx) * t}px ${(ROW_TARGET.y - cy) * t}px`,
    scale: String(scale),
    opacity: interpolate(t, [0, 0.55, 0.92], [1, 1, 0], clamp),
    filter: `blur(${interpolate(t, [0.4, 1], [0, 6], clamp)}px)`,
  };
};

const cursorPosition = (frame: number) => {
  const start = { x: 980, y: 620 };
  const path: [readonly [number, number], { x: number; y: number }][] = [
    [T.cursorToIcon, ICON],
    [T.cursorToButton, PARK_BUTTON],
    [T.cursorToRow, ROW_HOVER],
  ];
  let position = start;
  for (const [range, target] of path) {
    const t = ramp(frame, range, travel);
    position = { x: position.x + (target.x - position.x) * t, y: position.y + (target.y - position.y) * t };
  }
  return position;
};

const Caption: React.FC<{ frame: number; range: [number, number]; children: React.ReactNode }> = ({ frame, range, children }) => {
  const [start, end] = range;
  const opacity = interpolate(frame, [start, start + 18, end - 14, end], [0, 1, 1, 0], clamp);
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        bottom: 56,
        display: "flex",
        justifyContent: "center",
        opacity,
        translate: `0 ${interpolate(frame, [start, start + 18], [10, 0], { ...clamp, easing: settle })}px`,
      }}
    >
      <div
        style={{
          ...display(30, 600),
          padding: "16px 30px",
          borderRadius: 999,
          background: "rgba(255,255,255,0.72)",
          backdropFilter: "blur(30px) saturate(150%)",
          boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.7), 0 12px 32px rgba(10,22,44,0.22)",
        }}
      >
        {children}
      </div>
    </div>
  );
};

const DesktopScene: React.FC = () => {
  const frame = useCurrentFrame();

  const panelOpen = frame >= T.clickIcon && frame < T.panelOut[1];
  const panelIn = ramp(frame, T.panelIn);
  const panelOut = ramp(frame, T.panelOut, away);
  const parked = frame >= T.collapse[0] + 30;
  const parking = frame >= T.clickPark && frame < T.parkingEnd;
  const restored = frame >= T.clickRestore;

  const memoryUsed = restored
    ? interpolate(frame, [T.expand[0], T.expand[1] + 30], [10.8, 12.9], clamp)
    : interpolate(frame, T.memoryDrop, [13.1, 10.8], { ...clamp, easing: settle });

  const pressed = (at: number) => frame >= at && frame < at + 7;
  const cursor = cursorPosition(frame);

  return (
    <AbsoluteFill style={{ fontFamily: font }}>
      <AbsoluteFill>
        <Wallpaper />

        {/* Windows: park toward the new row, then restore from it */}
        {WINDOWS.map((spec) => {
          const collapse = ramp(frame, [T.collapse[0] + spec.delay, T.collapse[0] + spec.delay + 44], Easingish);
          const expand = ramp(frame, [T.expand[0] + spec.delay, T.expand[0] + spec.delay + 50]);
          const t = restored ? 1 - expand : collapse;
          const style = parkTransform(spec, t);
          if (spec.id === "browser")
            return (
              <Window key={spec.id} {...spec} toolbar={<BrowserToolbar />} style={style}>
                <BrowserContent />
              </Window>
            );
          if (spec.id === "figma")
            return (
              <Window key={spec.id} {...spec} dark toolbar={<FigmaToolbar />} style={style}>
                <FigmaContent />
              </Window>
            );
          return (
            <Window key={spec.id} {...spec} dark toolbar={<WarpToolbar />} style={style}>
              <TerminalContent />
            </Window>
          );
        })}

        <MenuBar iconHighlighted={panelOpen} memory={`${memoryUsed.toFixed(1)} GB`} />

        {panelOpen && (
          <div
            style={{
              position: "absolute",
              left: PANEL.left,
              top: PANEL.top,
              transformOrigin: `${ICON.x - PANEL.left}px 0px`,
              opacity: panelIn * (1 - panelOut),
              scale: String(0.97 + 0.03 * panelIn - 0.02 * panelOut),
              translate: `0 ${(1 - panelIn) * -8}px`,
            }}
          >
            <Panel
              frame={frame}
              parked={parked}
              parking={parking}
              buttonPressed={pressed(T.clickPark)}
              rowIn={ramp(frame, T.rowIn)}
              highlight={1 - ramp(frame, T.highlightOut)}
              freedOpacity={ramp(frame, T.freedIn)}
              memoryUsed={memoryUsed}
              hoverRow={frame >= T.hoverRow}
              restorePressed={pressed(T.clickRestore)}
            />
          </div>
        )}

        <Caption frame={frame} range={[240, 420]}>Park it. The windows close and the memory comes back.</Caption>
        <Caption frame={frame} range={[556, 646]}>Restore it later, exactly as you left it.</Caption>

        {<Cursor x={cursor.x} y={cursor.y} pressed={pressed(T.clickIcon) || pressed(T.clickPark) || pressed(T.clickRestore)} />}
      </AbsoluteFill>

    </AbsoluteFill>
  );
};

/** Light product-page card: eyebrow with the app icon, a two-line headline, optional footer lines. */
const Card: React.FC<{ footer?: boolean }> = ({ footer }) => {
  const frame = useCurrentFrame();
  const rise = (start: number) => ({
    opacity: ramp(frame, [start, start + 24]),
    translate: `0 ${(1 - ramp(frame, [start, start + 30])) * 16}px`,
  });
  return (
    <AbsoluteFill style={{ background: page.canvas, justifyContent: "center", paddingLeft: 200 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 22, ...rise(6) }}>
        <Img src={staticFile("park-icon.png")} style={{ width: 84, height: 84, borderRadius: "50%", filter: "drop-shadow(0 8px 16px rgba(10,22,44,0.22))" }} />
        <span style={display(34, 600)}>Park for Mac</span>
      </div>
      <div style={{ ...display(128, 600), marginTop: 56, ...rise(14) }}>Put a desktop away.</div>
      <div style={{ ...display(128, 600, page.muted), marginTop: 6, ...rise(24) }}>Pick it up later.</div>
      {footer && (
        <div style={{ marginTop: 70, display: "flex", flexDirection: "column", gap: 14, ...rise(36) }}>
          <span style={display(34, 600)}>Free and open source</span>
          <span style={{ ...display(30, 500, page.body), fontVariantNumeric: "tabular-nums" }}>github.com/spencerceverett-maker/park</span>
        </div>
      )}
    </AbsoluteFill>
  );
};

/** Crossfade helper: fades a whole sequence in over its first frames and out over its last. */
const Fade: React.FC<{ length: number; fadeIn?: number; fadeOut?: number; children: React.ReactNode }> = ({ length, fadeIn = 0, fadeOut = 0, children }) => {
  const frame = useCurrentFrame();
  const opacity = Math.min(
    fadeIn ? interpolate(frame, [0, fadeIn], [0, 1], clamp) : 1,
    fadeOut ? interpolate(frame, [length - fadeOut, length], [1, 0], clamp) : 1,
  );
  return <AbsoluteFill style={{ opacity }}>{children}</AbsoluteFill>;
};

export const TITLE = 150;
export const SCENE = 660;
const OVERLAP = 18;
export const END = 260;
export const TOTAL = TITLE + SCENE + END - 2 * OVERLAP;

export const ParkDemo: React.FC = () => (
  <AbsoluteFill style={{ background: page.canvas }}>
    <Sequence durationInFrames={TITLE}>
      <Fade length={TITLE} fadeOut={OVERLAP}>
        <Card />
      </Fade>
    </Sequence>
    <Sequence from={TITLE - OVERLAP} durationInFrames={SCENE}>
      <Fade length={SCENE} fadeIn={OVERLAP} fadeOut={OVERLAP}>
        <DesktopScene />
      </Fade>
    </Sequence>
    <Sequence from={TITLE + SCENE - 2 * OVERLAP} durationInFrames={END}>
      <Fade length={END} fadeIn={OVERLAP}>
        <Card footer />
      </Fade>
    </Sequence>
  </AbsoluteFill>
);

/** Windows leave gently, then accelerate into the row. */
const Easingish = (t: number) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2);
