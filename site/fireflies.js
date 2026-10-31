// Fireflies: the app's first-launch intro, ported from Metal (Sources/Park/IntroEffects/IntroShaders.swift).
// Motes of light drift on a current, then gather into a ring around Park's icon. Same math, same tuned values.

/* The values approved in the app's tuning panel (FireflyParams). */
export const FIREFLY_PARAMS = {
  count: 609, size: 3.865693, sizeVariation: 0.9166242, softness: 0.056060348,
  opacity: 0.98303187, opacityVariation: 0.9843467, twinkle: 0.6865093, twinkleSpeed: 0.20006794,
  depth: 0.28277856, scatter: 1, driftSpeed: 34, swirl: 1.2, turbulence: 0.45,
  gatherTime: 1.1, stagger: 0.6,
  colorMix: 0.0510077, whiteCore: 1, glow: 0.25043875,
  ringSize: 15, ringSoftness: 0.4, speed: 1,
};

const ORDER = ["count", "size", "sizeVariation", "softness", "opacity", "opacityVariation", "twinkle", "twinkleSpeed",
  "depth", "scatter", "driftSpeed", "swirl", "turbulence", "gatherTime", "stagger", "colorMix", "whiteCore", "glow",
  "ringSize", "ringSoftness", "speed"];

const COMMON = `#version 300 es
precision highp float;
uniform float uTime, uScale;
uniform vec2 uResolution, uOrigin;
uniform float uF[21];
#define F_SIZE uF[1]
#define F_SIZEVAR uF[2]
#define F_SOFT uF[3]
#define F_OPACITY uF[4]
#define F_OPVAR uF[5]
#define F_TWINKLE uF[6]
#define F_TWSPEED uF[7]
#define F_DEPTH uF[8]
#define F_SCATTER uF[9]
#define F_DRIFT uF[10]
#define F_SWIRL uF[11]
#define F_TURB uF[12]
#define F_GATHER uF[13]
#define F_STAGGER uF[14]
#define F_COLOR uF[15]
#define F_WHITE uF[16]
#define F_GLOW uF[17]
#define F_RING uF[18]
#define F_RINGSOFT uF[19]
const vec3 SIGN = vec3(0.118, 0.314, 0.659);
const vec3 DAWN = vec3(0.612, 0.753, 0.918);
const vec3 HORIZON = vec3(0.812, 0.878, 0.961);
const vec3 FIRST = vec3(0.890, 0.933, 0.980);
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float easeInOut(float x) { x = clamp(x, 0.0, 1.0); return x < 0.5 ? 4.0 * x * x * x : 1.0 - pow(-2.0 * x + 2.0, 3.0) * 0.5; }
float win(float t, float a, float b, float c, float d) { return smoothstep(a, b, t) * (1.0 - smoothstep(c, d, t)); }
float gauss(float x, float w) { return exp(-(x * x) / (w * w)); }
vec2 rot(vec2 v, float r) { float c = cos(r), s = sin(r); return vec2(c * v.x - s * v.y, s * v.x + c * v.y); }
float arrival() { return 0.35 + F_STAGGER + F_GATHER * 1.2; }
void tint(inout vec3 rgb, inout float a, vec3 c, float amount) { amount = clamp(amount, 0.0, 1.0); rgb = rgb * (1.0 - amount) + c * amount; a = a + amount * (1.0 - a); }
void light(inout vec3 rgb, inout float a, vec3 c, float amount) { amount = max(amount, 0.0); rgb += c * amount; a = a + min(amount * 0.38, 1.0) * (1.0 - a); }
`;

/* The screen-wide part: a faint pull of blue where the motes converge, then the ring. */
const RING_VS = `#version 300 es
void main() { vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2); gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0); }`;
const RING_FS = COMMON + `
out vec4 outColor;
void main() {
  float t = uTime;
  vec2 px = vec2(gl_FragCoord.x, uResolution.y - gl_FragCoord.y);
  float d = length((px - uOrigin) / uScale);
  float E = arrival();
  vec3 rgb = vec3(0.0); float a = 0.0;
  tint(rgb, a, SIGN, exp(-d / 240.0) * 0.07 * win(t, 0.7, max(E - 0.6, 0.8), E, E + 0.6));
  float x = d - F_RING, amount = win(t, E - 0.6, E - 0.1, E + 0.2, E + 0.7), R = F_RING, soft = F_RINGSOFT;
  tint(rgb, a, SIGN, (exp(-d / (R * 2.7)) * 0.16 + gauss(x, mix(3.0, 10.0, soft)) * 0.2) * amount);
  light(rgb, a, mix(DAWN, FIRST, 0.6), (gauss(x, mix(1.2, 4.5, soft)) * mix(0.85, 0.5, soft) + exp(-abs(x) / mix(5.0, 14.0, soft)) * 0.22) * amount);
  // A one-step dither so faint halos don't show 8-bit rings.
  rgb += (hash(px + fract(t) * 91.7) - 0.5) / 255.0 * step(0.002, a);
  outColor = vec4(rgb, a);
}`;

const MOTE_VS = COMMON + `
out vec2 vLocal;
out float vSize, vExt, vSoft, vTone, vBokeh, vBright;
float potential(vec2 q) { return vnoise(q) + 0.5 * vnoise(q * 2.1 + vec2(3.1, 7.7)); }
// Divergence-free flow, so the motes swirl rather than bunch up.
vec2 curl(vec2 q) {
  const float e = 0.02;
  return vec2(potential(q + vec2(0, e)) - potential(q - vec2(0, e)), potential(q - vec2(e, 0)) - potential(q + vec2(e, 0))) / (2.0 * e);
}
void main() {
  float fi = float(gl_InstanceID), t = uTime;
  float h1 = hash(vec2(fi, 1.3)), h2 = hash(vec2(fi, 4.7)), h3 = hash(vec2(fi, 8.1)), h4 = hash(vec2(fi, 2.9));
  float h5 = hash(vec2(fi, 6.2)), h6 = hash(vec2(fi, 9.4)), h7 = hash(vec2(fi, 3.6));
  float W = uResolution.x / uScale, H = uResolution.y / uScale;
  float E = arrival();
  bool bokeh = h5 < F_DEPTH;
  vec2 pos = vec2(0.5 * W, 0.52 * H) + (vec2(h1, h2) - 0.5) * vec2(W, H) * F_SCATTER - uOrigin / uScale;
  float drift = min(t, E);
  float noiseScale = mix(520.0, 140.0, F_TURB);
  for (int k = 0; k < 8; k++) pos += curl(pos / noiseScale + vec2(0.0, float(k) * 0.04)) * drift / 8.0 * F_DRIFT * (bokeh ? 1.5 : 1.0);
  float g = easeInOut((t - (0.35 + h3 * F_STAGGER)) / max(F_GATHER * (0.8 + 0.4 * h4), 0.05));
  float theta = h2 * 6.2831853 + t * 0.5;
  vec2 target = vec2(cos(theta), sin(theta)) * (F_RING + (h1 - 0.5) * mix(2.0, 8.0, F_RINGSOFT));
  pos = target + rot(pos - target, g * F_SWIRL) * (1.0 - g);

  float size = F_SIZE * min(pow(1.0 / (1.0 - 0.985 * h6), F_SIZEVAR), 9.0);
  vSize = bokeh ? max(size * 2.6, 5.0) : mix(size, min(size, 2.4), g) * (1.0 - 0.4 * g);
  vSoft = bokeh ? 1.0 : F_SOFT;
  vExt = vSize * mix(3.0, 7.0, vSoft) * (1.0 + F_GLOW * 1.5);
  vTone = clamp(F_COLOR + (h4 - 0.5) * 0.5, 0.0, 1.0);
  vBokeh = bokeh ? 1.0 : 0.0;
  vec2 corner = vec2(float(gl_VertexID & 1), float(gl_VertexID >> 1)) * 2.0 - 1.0;
  vLocal = corner * vExt;
  vec2 pixel = uOrigin + (pos + vLocal) * uScale;
  gl_Position = vec4(pixel.x / uResolution.x * 2.0 - 1.0, 1.0 - pixel.y / uResolution.y * 2.0, 0.0, 1.0);

  float twinkle = 1.0 - F_TWINKLE * 0.5 * (1.0 + sin(t * F_TWSPEED * (0.7 + 0.6 * h4) + h2 * 40.0));
  float alpha = F_OPACITY * (1.0 - F_OPVAR * h7) * (bokeh ? 0.32 : 1.0);
  vBright = smoothstep(0.0, 0.35 + h1 * 0.5, t) * twinkle * alpha * (1.0 - smoothstep(E + 0.1, E + 0.6, t))
          * (bokeh ? 1.0 - smoothstep(0.3, 0.9, g) : 1.0 - 0.35 * g);
}`;

const MOTE_FS = COMMON + `
in vec2 vLocal;
in float vSize, vExt, vSoft, vTone, vBokeh, vBright;
out vec4 outColor;
void main() {
  float dd = length(vLocal) / vSize;
  vec3 color = mix(SIGN, HORIZON, vTone);
  vec3 rgb = vec3(0.0); float a = 0.0;
  if (vBokeh > 0.5) {
    // Out of focus: a soft disc with a faint brighter rim, like a lens renders it.
    float body = (1.0 - smoothstep(0.7, 1.0, dd)) * 0.5 + gauss(dd - 0.9, 0.09) * 0.3;
    tint(rgb, a, mix(SIGN, color, 0.3), body * 0.55);
    light(rgb, a, color, body * 0.25);
  } else {
    float sigma = mix(0.55, 1.1, vSoft);
    tint(rgb, a, mix(SIGN, color, 0.2), gauss(dd, sigma * 1.7) * 0.6 + exp(-dd / mix(0.8, 2.4, vSoft)) * 0.16);
    light(rgb, a, color, gauss(dd, sigma) * mix(0.75, 0.45, vSoft));
    if (F_WHITE > 0.5) light(rgb, a, FIRST, gauss(dd, sigma * 0.4) * 0.5);
  }
  light(rgb, a, color, exp(-dd / (2.5 + 3.0 * vSoft)) * F_GLOW * 0.35);
  // Fade out before the edge of the sprite so no square ever shows.
  float edge = 1.0 - smoothstep(0.75, 1.0, length(vLocal) / vExt);
  outColor = vec4(rgb, a) * vBright * edge;
}`;

function program(gl, vs, fs) {
  const p = gl.createProgram();
  for (const [type, src] of [[gl.VERTEX_SHADER, vs], [gl.FRAGMENT_SHADER, fs]]) {
    const s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    gl.attachShader(p, s);
  }
  gl.linkProgram(p);
  if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
  return p;
}

/**
 * Plays the fireflies once over `host`, gathering on `target`. Resolves when they have landed and faded.
 * `ringSize` defaults to just outside the target. The count scales with the area, so a smaller stage
 * reads as densely as the full screen the values were tuned on.
 */
export function playFireflies(host, target, overrides = {}) {
  return new Promise((resolve) => {
    const canvas = document.createElement("canvas");
    canvas.className = "fireflies";
    canvas.setAttribute("aria-hidden", "true");
    const gl = canvas.getContext("webgl2", { premultipliedAlpha: true, antialias: false });
    if (!gl) return resolve();
    host.append(canvas);

    let ring, motes;
    try {
      ring = program(gl, RING_VS, RING_FS);
      motes = program(gl, MOTE_VS, MOTE_FS);
    } catch (error) {
      canvas.remove();
      return resolve();
    }

    const box = host.getBoundingClientRect();
    const icon = target.getBoundingClientRect();
    const scale = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(box.width * scale);
    canvas.height = Math.round(box.height * scale);
    const params = { ...FIREFLY_PARAMS, ringSize: icon.width / 2 + 7, ...overrides };
    params.count = Math.round(params.count * Math.min(1, (box.width * box.height) / (1512 * 945)));
    const values = new Float32Array(ORDER.map((key) => params[key]));
    const origin = [(icon.left + icon.width / 2 - box.left) * scale, (icon.top + icon.height / 2 - box.top) * scale];
    const end = (0.35 + params.stagger + params.gatherTime * 1.2 + 0.75) / params.speed;

    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    const set = (p, t) => {
      gl.useProgram(p);
      gl.uniform1f(gl.getUniformLocation(p, "uTime"), t);
      gl.uniform1f(gl.getUniformLocation(p, "uScale"), scale);
      gl.uniform2f(gl.getUniformLocation(p, "uResolution"), canvas.width, canvas.height);
      gl.uniform2f(gl.getUniformLocation(p, "uOrigin"), origin[0], origin[1]);
      gl.uniform1fv(gl.getUniformLocation(p, "uF"), values);
    };

    let start = 0;
    const frame = (now) => {
      start ||= now;
      const t = ((now - start) / 1000) * params.speed;
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      set(ring, t);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      set(motes, t);
      gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, params.count);
      if (t < end * params.speed) return requestAnimationFrame(frame);
      canvas.remove();
      gl.getExtension("WEBGL_lose_context")?.loseContext();
      resolve();
    };
    requestAnimationFrame(frame);
  });
}
