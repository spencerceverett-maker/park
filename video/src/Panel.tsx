import React from "react";
import { Img, staticFile } from "remotion";
import { color, font, S } from "./theme";

const pt = (v: number) => v * S;

const IconStack: React.FC<{ icons: string[]; overflow?: number }> = ({ icons, overflow = 0 }) => {
  const size = pt(22);
  return (
    <div style={{ display: "flex", width: size + 2 * size * 0.68, flexShrink: 0 }}>
      {icons.map((icon, i) => (
        <Img
          key={icon + i}
          src={staticFile(icon)}
          style={{
            width: size,
            height: size,
            marginLeft: i === 0 ? 0 : -size * 0.32,
            zIndex: icons.length - i,
            filter: "drop-shadow(0 0.75px 1.5px rgba(0,0,0,0.3))",
          }}
        />
      ))}
      {overflow > 0 && (
        <div
          style={{
            width: size,
            height: size,
            marginLeft: -size * 0.32,
            borderRadius: size / 2,
            background: "white",
            boxShadow: `inset 0 0 0 1px ${color.hairline}`,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontFamily: font,
            fontSize: pt(9.5),
            fontWeight: 600,
            color: color.secondary,
          }}
        >
          +{overflow}
        </div>
      )}
    </div>
  );
};

const Row: React.FC<{
  icons: string[];
  overflow?: number;
  title: string;
  subtitle: string;
  freed?: string;
  freedOpacity?: number;
  background?: string;
  hovered?: boolean;
  restorePressed?: boolean;
}> = ({ icons, overflow, title, subtitle, freed, freedOpacity = 1, background, hovered, restorePressed }) => (
  <div
    style={{
      height: pt(48),
      display: "flex",
      alignItems: "center",
      gap: pt(10),
      padding: `0 ${pt(8)}px`,
      borderRadius: pt(8),
      background: background ?? (hovered ? color.hover : "transparent"),
    }}
  >
    <IconStack icons={icons} overflow={overflow} />
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ fontFamily: font, fontSize: pt(13), fontWeight: 500, color: color.primary, letterSpacing: -0.15, whiteSpace: "nowrap" }}>{title}</div>
      <div style={{ fontFamily: font, fontSize: pt(11.5), color: color.secondary, marginTop: pt(1), fontVariantNumeric: "tabular-nums" }}>{subtitle}</div>
    </div>
    {hovered ? (
      <div style={{ display: "flex", alignItems: "center", gap: pt(2) }}>
        <div
          style={{
            fontFamily: font,
            fontSize: pt(12),
            fontWeight: 500,
            color: color.accent,
            height: pt(24),
            padding: `0 ${pt(8)}px`,
            borderRadius: pt(6),
            display: "flex",
            alignItems: "center",
            background: restorePressed ? "rgba(0,0,0,0.10)" : color.hover,
          }}
        >
          Restore
        </div>
        <Ellipsis />
      </div>
    ) : (
      freed && (
        <div style={{ fontFamily: font, fontSize: pt(11.5), color: color.tertiary, marginRight: pt(4), opacity: freedOpacity, fontVariantNumeric: "tabular-nums" }}>
          {freed}
        </div>
      )
    )}
  </div>
);

const Ellipsis = () => (
  <div style={{ width: pt(24), height: pt(24), display: "flex", alignItems: "center", justifyContent: "center", gap: pt(2.5) }}>
    {[0, 1, 2].map((i) => (
      <div key={i} style={{ width: pt(2.6), height: pt(2.6), borderRadius: pt(1.3), background: color.secondary }} />
    ))}
  </div>
);

const Spinner: React.FC<{ frame: number }> = ({ frame }) => (
  <svg width={pt(14)} height={pt(14)} viewBox="0 0 20 20" style={{ rotate: `${Math.floor(frame / 4) * 45}deg` }}>
    {Array.from({ length: 8 }).map((_, i) => (
      <rect key={i} x="9" y="1.5" width="2" height="5" rx="1" fill="white" opacity={0.25 + (i / 8) * 0.75} transform={`rotate(${i * 45} 10 10)`} />
    ))}
  </svg>
);

export type PanelState = {
  frame: number;
  /** 0 = windows on the desktop, 1 = desktop parked */
  parked: boolean;
  parking: boolean;
  buttonPressed: boolean;
  /** Height progress of the newly parked row, 0…1 */
  rowIn: number;
  /** Accent highlight on the new row, 1…0 */
  highlight: number;
  freedOpacity: number;
  memoryUsed: number;
  hoverRow: boolean;
  restorePressed: boolean;
};

export const PANEL_WIDTH = pt(340);
/** Where the first parked row's icon stack sits, relative to the panel's top-left corner. */
export const FIRST_ROW_ICON = { x: pt(8) + pt(8) + pt(11), y: pt(16) * 2 + pt(31) + pt(12) + pt(32) + 1 + pt(10) + pt(16) + pt(4) + pt(24) };

export const Panel: React.FC<PanelState> = (s) => {
  const total = 16;
  const fraction = s.memoryUsed / total;
  return (
    <div
      style={{
        width: PANEL_WIDTH,
        borderRadius: pt(14),
        overflow: "hidden",
        background: color.panel,
        backdropFilter: "blur(60px) saturate(150%)",
        boxShadow: `0 ${pt(14)}px ${pt(40)}px rgba(0,0,0,0.32), inset 0 0 0 ${pt(0.7)}px ${color.panelBorder}`,
        fontFamily: font,
      }}
    >
      {/* This desktop */}
      <div style={{ padding: pt(16), display: "flex", flexDirection: "column", gap: pt(12) }}>
        <div style={{ display: "flex", alignItems: "center", gap: pt(10) }}>
          {s.parked ? (
            <div style={{ width: pt(22) + 2 * pt(22) * 0.68, flexShrink: 0 }}>
              <div style={{ width: pt(22), height: pt(22), borderRadius: pt(6), border: `${pt(1)}px dashed ${color.tertiary}`, boxSizing: "border-box" }} />
            </div>
          ) : (
            <IconStack icons={["chrome.png", "figma.png", "warp.png"]} />
          )}
          <div>
            <div style={{ fontSize: pt(13), fontWeight: 500, color: color.primary, letterSpacing: -0.15 }}>
              {s.parked ? "Nothing open here" : "Chrome, Figma and Warp"}
            </div>
            <div style={{ fontSize: pt(11.5), color: color.secondary, marginTop: pt(1) }}>
              {s.parked ? "Switch to a desktop with windows to park it" : "3 windows on this desktop"}
            </div>
          </div>
        </div>
        <div
          style={{
            height: pt(32),
            borderRadius: pt(8),
            background: color.accent,
            opacity: s.parked && !s.parking ? 0.35 : 1,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: pt(8),
            color: "white",
            fontSize: pt(13),
            fontWeight: 600,
            scale: s.buttonPressed ? "0.985" : "1",
            boxShadow: `inset 0 0 0 ${pt(0.5)}px rgba(255,255,255,0.14)`,
            filter: s.buttonPressed ? "brightness(0.86)" : undefined,
          }}
        >
          {s.parking ? (
            <>
              <Spinner frame={s.frame} />
              Parking…
            </>
          ) : (
            <>
              Park this desktop
              <span style={{ fontSize: pt(11), fontWeight: 500, color: "rgba(255,255,255,0.75)", background: "rgba(255,255,255,0.16)", borderRadius: pt(4), minWidth: pt(18), height: pt(18), display: "inline-flex", alignItems: "center", justifyContent: "center" }}>↩</span>
            </>
          )}
        </div>
      </div>

      <div style={{ height: 1, background: color.hairline }} />

      {/* Parked */}
      <div>
        <div style={{ display: "flex", justifyContent: "space-between", padding: `${pt(10)}px ${pt(16)}px ${pt(4)}px` }}>
          <span style={{ fontSize: pt(11.5), fontWeight: 500, color: color.secondary }}>Parked</span>
          <span style={{ fontSize: pt(11.5), color: color.tertiary, fontVariantNumeric: "tabular-nums" }}>{s.rowIn > 0.5 ? 3 : 2}</span>
        </div>
        <div style={{ padding: `0 ${pt(8)}px ${pt(8)}px` }}>
          <div style={{ height: pt(48) * s.rowIn, opacity: s.rowIn, overflow: "hidden" }}>
            <div style={{ translate: `0 ${(1 - s.rowIn) * -pt(10)}px` }}>
              <Row
                icons={["figma.png", "chrome.png", "warp.png"]}
                title="Onboarding redesign"
                subtitle="3 windows · Just now"
                freed="2.3 GB"
                freedOpacity={s.freedOpacity}
                hovered={s.hoverRow}
                restorePressed={s.restorePressed}
                background={s.hoverRow ? undefined : `rgba(30,80,168,${0.14 * s.highlight})`}
              />
            </div>
          </div>
          <Row icons={["figma.png", "chrome.png"]} overflow={3} title="Q4 launch plan" subtitle="5 windows · Yesterday" freed="1.0 GB" />
          <Row icons={["warp.png", "chrome.png"]} title="api-server" subtitle="2 windows · Tuesday" />
        </div>
      </div>

      <div style={{ height: 1, background: color.hairline }} />

      {/* Footer */}
      <div style={{ height: pt(40), display: "flex", alignItems: "center", padding: `0 ${pt(8)}px 0 ${pt(16)}px`, gap: pt(8) }}>
        <div style={{ width: pt(44), height: pt(4), borderRadius: pt(2), background: color.hover, position: "relative" }}>
          <div style={{ position: "absolute", left: 0, top: 0, bottom: 0, width: pt(44) * fraction, borderRadius: pt(2), background: "#1E50A8" }} />
        </div>
        <span style={{ flex: 1, fontSize: pt(11.5), color: color.secondary, fontVariantNumeric: "tabular-nums" }}>
          {s.memoryUsed.toFixed(1)} of 16 GB memory used
        </span>
        <Ellipsis />
      </div>
    </div>
  );
};
