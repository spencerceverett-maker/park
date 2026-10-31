import React from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";
import { color, font } from "./theme";

/** The same soft color field as the social card: indigo base, blurred blobs, warm at the bottom. */
export const Wallpaper: React.FC = () => {
  const blobs: [number, number, number, string][] = [
    [0.15, 0.15, 0.55, "#5B6CFF"],
    [0.75, 0.05, 0.5, "#8A5CF6"],
    [0.95, 0.65, 0.55, "rgba(46,197,211,0.9)"],
    [0.35, 0.9, 0.6, "rgba(255,154,123,0.95)"],
    [0.6, 0.5, 0.35, "rgba(198,184,255,0.7)"],
  ];
  return (
    <AbsoluteFill style={{ background: "#2E2F9E", overflow: "hidden" }}>
      <AbsoluteFill style={{ filter: "blur(80px)", scale: "1.15" }}>
        {blobs.map(([x, y, r, c]) => (
          <div
            key={c}
            style={{
              position: "absolute",
              left: x * 1920 - r * 1920,
              top: y * 1080 - r * 1920,
              width: r * 1920 * 2,
              height: r * 1920 * 2,
              borderRadius: "50%",
              background: `radial-gradient(circle, ${c} 0%, transparent 70%)`,
            }}
          />
        ))}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const ParkGlyph: React.FC<{ size: number; color?: string }> = ({ size, color: c = "white" }) => (
  <svg width={size} height={size} viewBox="0 0 24 24">
    <circle cx="12" cy="12" r="10" fill="none" stroke={c} strokeWidth="1.8" />
    <path d="M9.4 17V7.2h3.6c2.1 0 3.4 1.2 3.4 3.05S15.1 13.3 13 13.3h-3.6" fill="none" stroke={c} strokeWidth="1.9" strokeLinejoin="round" strokeLinecap="round" />
  </svg>
);

/** A slim macOS menu bar with Park's status item. */
export const MenuBar: React.FC<{ iconHighlighted: boolean; memory: string }> = ({ iconHighlighted, memory }) => (
  <div
    style={{
      position: "absolute",
      top: 0,
      left: 0,
      right: 0,
      height: 36,
      display: "flex",
      alignItems: "center",
      padding: "0 22px",
      gap: 28,
      background: "rgba(255,255,255,0.22)",
      backdropFilter: "blur(30px) saturate(140%)",
      color: "white",
      fontFamily: font,
      fontSize: 19,
      fontWeight: 500,
      letterSpacing: -0.1,
    }}
  >
    <span style={{ fontWeight: 700 }}>Finder</span>
    {["File", "Edit", "View", "Go", "Window", "Help"].map((item) => (
      <span key={item} style={{ fontWeight: 400, opacity: 0.88 }}>
        {item}
      </span>
    ))}
    <div style={{ flex: 1 }} />
    <div
      style={{
        width: 40,
        height: 28,
        borderRadius: 7,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: iconHighlighted ? "rgba(255,255,255,0.28)" : "transparent",
      }}
    >
      <ParkGlyph size={22} />
    </div>
    <span style={{ fontVariantNumeric: "tabular-nums", fontWeight: 400, opacity: 0.8, fontSize: 17 }}>{memory}</span>
    <WifiGlyph />
    <span style={{ fontWeight: 400 }}>Sat 9:41 AM</span>
  </div>
);

const WifiGlyph = () => (
  <svg width="22" height="22" viewBox="0 0 24 24" style={{ opacity: 0.9 }}>
    <path d="M2.5 9a14 14 0 0 1 19 0M5.8 12.4a9.3 9.3 0 0 1 12.4 0M9 15.7a4.6 4.6 0 0 1 6 0" fill="none" stroke="white" strokeWidth="2" strokeLinecap="round" />
    <circle cx="12" cy="19" r="1.5" fill="white" />
  </svg>
);

/** The macOS pointer. */
export const Cursor: React.FC<{ x: number; y: number; pressed: boolean }> = ({ x, y, pressed }) => (
  <svg
    width="34"
    height="34"
    viewBox="0 0 24 24"
    style={{
      position: "absolute",
      left: x - 6,
      top: y - 4,
      scale: pressed ? "0.88" : "1",
      transformOrigin: "6px 4px",
      filter: "drop-shadow(0 2px 3px rgba(0,0,0,0.45))",
    }}
  >
    <path d="M5 3l14 8.2-6.3 1.4 3.8 7.2-2.6 1.3-3.7-7.2L5 18.5z" fill="black" stroke="white" strokeWidth="1.4" strokeLinejoin="round" />
  </svg>
);

/** Rounded window chrome with traffic lights; children draw the content. */
export const Window: React.FC<{
  x: number;
  y: number;
  w: number;
  h: number;
  title?: string;
  dark?: boolean;
  toolbar?: React.ReactNode;
  children?: React.ReactNode;
  style?: React.CSSProperties;
}> = ({ x, y, w, h, title, dark, toolbar, children, style }) => (
  <div
    style={{
      position: "absolute",
      left: x,
      top: y,
      width: w,
      height: h,
      borderRadius: 16,
      overflow: "hidden",
      background: dark ? "#16171c" : "#f5f5f7",
      boxShadow: "0 24px 60px rgba(20,20,60,0.35), 0 0 0 1px rgba(0,0,0,0.10)",
      fontFamily: font,
      display: "flex",
      flexDirection: "column",
      ...style,
    }}
  >
    <div
      style={{
        height: 52,
        flexShrink: 0,
        display: "flex",
        alignItems: "center",
        gap: 10,
        padding: "0 18px",
        background: dark ? "#1d1e24" : "#e9e9ec",
        borderBottom: `1px solid ${dark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.08)"}`,
      }}
    >
      {["#ff5f57", "#febc2e", "#28c840"].map((c) => (
        <div key={c} style={{ width: 14, height: 14, borderRadius: 7, background: c }} />
      ))}
      {toolbar ?? (
        <div style={{ flex: 1, textAlign: "center", marginRight: 70, fontSize: 16, fontWeight: 600, color: dark ? "rgba(255,255,255,0.7)" : "rgba(0,0,0,0.7)" }}>
          {title}
        </div>
      )}
    </div>
    <div style={{ flex: 1, position: "relative" }}>{children}</div>
  </div>
);

const Bar: React.FC<{ w: number | string; h?: number; c?: string; mt?: number }> = ({ w, h = 12, c = "rgba(0,0,0,0.09)", mt = 0 }) => (
  <div style={{ width: w, height: h, borderRadius: h / 2, background: c, marginTop: mt }} />
);

export const BrowserContent: React.FC = () => (
  <div style={{ padding: "44px 70px", display: "flex", flexDirection: "column" }}>
    <div style={{ fontSize: 15, fontWeight: 600, color: "#6e6e78", letterSpacing: 0.2 }}>PLANNING · Q4</div>
    <div style={{ fontSize: 40, fontWeight: 700, color: "#1d1d22", letterSpacing: -0.8, marginTop: 10 }}>Q4 launch plan</div>
    <Bar w="88%" mt={28} />
    <Bar w="76%" mt={14} />
    <Bar w="82%" mt={14} />
    <div style={{ display: "flex", gap: 18, marginTop: 34 }}>
      {[0, 1, 2].map((i) => (
        <div key={i} style={{ flex: 1, height: 130, borderRadius: 14, background: ["#e3e8ff", "#e9f7ef", "#fff1e3"][i] }} />
      ))}
    </div>
    <Bar w="70%" mt={34} />
    <Bar w="80%" mt={14} />
  </div>
);

export const BrowserToolbar: React.FC = () => (
  <div style={{ display: "flex", alignItems: "center", gap: 8, marginLeft: 16, flex: 1 }}>
    {["Q4 launch plan", "Onboarding research", "Linear"].map((t, i) => (
      <div
        key={t}
        style={{
          height: 34,
          padding: "0 16px",
          borderRadius: 10,
          display: "flex",
          alignItems: "center",
          fontSize: 14.5,
          fontWeight: 500,
          color: i === 0 ? "#1d1d22" : "#6e6e78",
          background: i === 0 ? "#ffffff" : "transparent",
          boxShadow: i === 0 ? "0 1px 2px rgba(0,0,0,0.08)" : undefined,
        }}
      >
        {t}
      </div>
    ))}
  </div>
);

export const FigmaToolbar: React.FC = () => (
  <div style={{ display: "flex", alignItems: "center", gap: 12, marginLeft: 16, flex: 1 }}>
    <Img src={staticFile("figma.png")} style={{ width: 22, height: 22 }} />
    <span style={{ fontSize: 15, fontWeight: 600, color: "rgba(255,255,255,0.85)" }}>Onboarding redesign</span>
  </div>
);

export const FigmaContent: React.FC = () => (
  <div style={{ position: "absolute", inset: 0, display: "flex" }}>
    <div style={{ width: 210, background: "#1d1e24", borderRight: "1px solid rgba(255,255,255,0.06)", padding: 18 }}>
      {["Welcome", "Choose a plan", "Connect bank", "Invite team", "Done"].map((layer, i) => (
        <div key={layer} style={{ height: 32, display: "flex", alignItems: "center", gap: 10, fontSize: 14, color: i === 1 ? "white" : "rgba(255,255,255,0.6)", background: i === 1 ? "rgba(10,132,255,0.35)" : "transparent", borderRadius: 6, padding: "0 8px" }}>
          <div style={{ width: 12, height: 12, border: "1.5px solid currentColor", borderRadius: 2, opacity: 0.8 }} />
          {layer}
        </div>
      ))}
    </div>
    <div style={{ flex: 1, background: "#2a2b31", position: "relative" }}>
      {[0, 1, 2].map((i) => (
        <div
          key={i}
          style={{
            position: "absolute",
            left: 60 + i * 250,
            top: 70 + (i === 1 ? -20 : 0),
            width: 210,
            height: 420,
            borderRadius: 18,
            background: "#ffffff",
            outline: i === 1 ? "2.5px solid #0A84FF" : undefined,
            padding: 20,
            boxSizing: "border-box",
          }}
        >
          <div style={{ width: 54, height: 54, borderRadius: 14, background: ["#5b6bff", "#22c55e", "#f59e0b"][i] }} />
          <Bar w="80%" h={14} c="rgba(0,0,0,0.75)" mt={22} />
          <Bar w="92%" h={10} mt={14} />
          <Bar w="70%" h={10} mt={10} />
          <div style={{ position: "absolute", left: 20, right: 20, bottom: 22, height: 42, borderRadius: 12, background: "#1d1d22" }} />
        </div>
      ))}
    </div>
  </div>
);

export const TerminalContent: React.FC = () => {
  const lines: [string, string][] = [
    ["~/Developer/api-server", "#7aa2ff"],
    ["❯ npm run dev", "rgba(255,255,255,0.92)"],
    ["", ""],
    ["  ▲ Ready on http://localhost:3000", "#7ee2a8"],
    ["  ✓ Compiled in 412 ms", "rgba(255,255,255,0.6)"],
    ["  GET /api/plans 200 in 18 ms", "rgba(255,255,255,0.6)"],
    ["  GET /api/team 200 in 11 ms", "rgba(255,255,255,0.6)"],
  ];
  return (
    <div style={{ padding: "22px 26px", fontFamily: '"SF Mono", Menlo, monospace', fontSize: 17, lineHeight: 1.6 }}>
      {lines.map(([text, c], i) => (
        <div key={i} style={{ color: c, whiteSpace: "pre" }}>
          {text || " "}
        </div>
      ))}
    </div>
  );
};

export const WarpToolbar: React.FC = () => (
  <div style={{ display: "flex", alignItems: "center", gap: 10, marginLeft: 16, flex: 1 }}>
    <div style={{ height: 32, padding: "0 14px", borderRadius: 8, background: "rgba(255,255,255,0.08)", display: "flex", alignItems: "center", fontSize: 14.5, color: "rgba(255,255,255,0.85)" }}>api-server</div>
    <div style={{ height: 32, padding: "0 14px", borderRadius: 8, display: "flex", alignItems: "center", fontSize: 14.5, color: "rgba(255,255,255,0.45)" }}>~</div>
  </div>
);

export const textStyle = (size: number, weight: number, c: string): React.CSSProperties => ({
  fontFamily: font,
  fontSize: size,
  fontWeight: weight,
  color: c,
  letterSpacing: size > 24 ? -0.4 : -0.1,
});

export { color };
