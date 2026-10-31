// Fireflies: the look of the app's first-launch intro (Sources/Park/IntroEffects/IntroShaders.swift), as an
// ambient field. Motes float on a slow current and part around the pointer like something disturbed in the air.

/* The look approved in the app's tuning panel (FireflyParams). */
const LOOK = {
  size: 3.865693, sizeVariation: 0.9166242, softness: 0.056060348,
  opacity: 0.98303187, opacityVariation: 0.9843467, twinkle: 0.6865093, twinkleSpeed: 0.20006794,
  depth: 0.28277856, colorMix: 0.0510077, whiteCore: 1, glow: 0.25043875,
};

/* The field's own motion. Slower and sparser than the intro: texture, not an event. */
const FIELD = {
  density: 150 / 1e6,   // motes per square pixel of the hero (about 150 on a laptop-sized card)
  maxCount: 320,
  drift: 9,             // px/s along the current
  noiseScale: 380,      // px per cell of the current
  reach: 150,           // px around the pointer that motes feel
  push: 900,            // px/s² away from the pointer at its center
  swirl: 0.35,          // share of the push turned sideways, so they eddy instead of scatter
  damping: 1.6,         // per second: how fast a disturbed mote settles back into the current
  parallax: 14,         // px that out-of-focus motes lean with the pointer
};

const VS = `#version 300 es
precision highp float;
in vec3 aMote;   // x, y in CSS px; z: this mote's own fade
uniform float uTime, uScale, uFade;
uniform vec2 uResolution, uPointer;
uniform float uPointerOn;
uniform float uL[11];
out vec2 vLocal;
out float vSize, vExt, vSoft, vTone, vBokeh, vBright;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void main() {
  float fi = float(gl_InstanceID);
  float h1 = hash(vec2(fi, 1.3)), h2 = hash(vec2(fi, 4.7)), h4 = hash(vec2(fi, 2.9));
  float h5 = hash(vec2(fi, 6.2)), h6 = hash(vec2(fi, 9.4)), h7 = hash(vec2(fi, 3.6));
  bool bokeh = h5 < uL[6];
  // Power-law sizes: most motes are small, a few are noticeably larger.
  float size = uL[0] * min(pow(1.0 / (1.0 - 0.985 * h6), uL[1]), 9.0);
  vSize = bokeh ? max(size * 2.6, 5.0) : size;
  vSoft = bokeh ? 1.0 : uL[2];
  vExt = vSize * mix(3.0, 7.0, vSoft) * (1.0 + uL[10] * 1.5);
  vTone = clamp(uL[7] + (h4 - 0.5) * 0.5, 0.0, 1.0);
  vBokeh = bokeh ? 1.0 : 0.0;
  vec2 corner = vec2(float(gl_VertexID & 1), float(gl_VertexID >> 1)) * 2.0 - 1.0;
  vLocal = corner * vExt;
  vec2 pixel = (aMote.xy + vLocal) * uScale;
  gl_Position = vec4(pixel.x / uResolution.x * 2.0 - 1.0, 1.0 - pixel.y / uResolution.y * 2.0, 0.0, 1.0);

  float twinkle = 1.0 - uL[4] * 0.5 * (1.0 + sin(uTime * uL[5] * (0.7 + 0.6 * h4) * 6.2831853 + h2 * 40.0));
  float alpha = uL[3] * (1.0 - uL[8] * h7) * (bokeh ? 0.32 : 1.0);
  // Motes near the pointer brighten a little, as if stirred.
  float near = uPointerOn * exp(-pow(length(aMote.xy - uPointer) / 120.0, 2.0));
  vBright = twinkle * alpha * (1.0 + near * 0.6) * uFade * aMote.z * (0.55 + 0.45 * h1);
}`;

const FS = `#version 300 es
precision highp float;
in vec2 vLocal;
in float vSize, vExt, vSoft, vTone, vBokeh, vBright;
uniform float uL[11];
out vec4 outColor;
const vec3 SIGN = vec3(0.118, 0.314, 0.659);
const vec3 HORIZON = vec3(0.812, 0.878, 0.961);
const vec3 FIRST = vec3(0.890, 0.933, 0.980);
float gauss(float x, float w) { return exp(-(x * x) / (w * w)); }
void tint(inout vec3 rgb, inout float a, vec3 c, float amount) { amount = clamp(amount, 0.0, 1.0); rgb = rgb * (1.0 - amount) + c * amount; a = a + amount * (1.0 - a); }
void light(inout vec3 rgb, inout float a, vec3 c, float amount) { amount = max(amount, 0.0); rgb += c * amount; a = a + min(amount * 0.38, 1.0) * (1.0 - a); }
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
    if (uL[9] > 0.5) light(rgb, a, FIRST, gauss(dd, sigma * 0.4) * 0.5);
  }
  light(rgb, a, color, exp(-dd / (2.5 + 3.0 * vSoft)) * uL[10] * 0.35);
  // Fade out before the edge of the sprite so no square ever shows.
  float edge = 1.0 - smoothstep(0.75, 1.0, length(vLocal) / vExt);
  outColor = vec4(rgb, a) * vBright * edge;
}`;

/* The current: divergence-free value-noise flow, so motes swirl instead of bunching up. */
function hash(x, y) { const s = Math.sin(x * 12.9898 + y * 78.233) * 43758.5453; return s - Math.floor(s); }
function noise(x, y) {
  const ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
  const ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
  const a = hash(ix, iy), b = hash(ix + 1, iy), c = hash(ix, iy + 1), d = hash(ix + 1, iy + 1);
  return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy;
}
function curl(x, y, out) {
  const e = 0.02;
  out[0] = (noise(x, y + e) - noise(x, y - e)) / (2 * e);
  out[1] = (noise(x - e, y) - noise(x + e, y)) / (2 * e);
}

function compile(gl) {
  const p = gl.createProgram();
  for (const [type, src] of [[gl.VERTEX_SHADER, VS], [gl.FRAGMENT_SHADER, FS]]) {
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
 * Fills `host` with a field of fireflies. With `still`, draws one frame and never moves (reduced motion).
 * `listen` is the element whose pointer they feel (the host, unless the host doesn't take pointer events).
 * Returns nothing; the field lives as long as the page, pausing whenever the host is off screen.
 */
export function mountFireflies(host, { still = false, density = FIELD.density, look: lookOverrides = {}, listen = host, reach = FIELD.reach, push = FIELD.push } = {}) {
  const L = { ...LOOK, ...lookOverrides };
  const canvas = document.createElement("canvas");
  canvas.className = "fireflies";
  canvas.setAttribute("aria-hidden", "true");
  const gl = canvas.getContext("webgl2", { premultipliedAlpha: true, antialias: false });
  if (!gl) return;
  let prog;
  try { prog = compile(gl); } catch { return; }
  host.append(canvas);

  const u = (name) => gl.getUniformLocation(prog, name);
  const look = new Float32Array([L.size, L.sizeVariation, L.softness, L.opacity, L.twinkle,
    L.twinkleSpeed, L.depth, L.colorMix, L.opacityVariation, L.whiteCore, L.glow]);
  const buffer = gl.createBuffer();
  const loc = gl.getAttribLocation(prog, "aMote");

  let W = 0, H = 0, scale = 1, count = 0;
  let pos = new Float32Array(0), vel = new Float32Array(0), depth = new Float32Array(0);
  const draw = new Float32Array(FIELD.maxCount * 3);

  // Keep motes where they are across resizes; only add or drop the difference.
  function resize() {
    const box = host.getBoundingClientRect();
    scale = Math.min(window.devicePixelRatio || 1, 2);
    const oldW = W || box.width, oldH = H || box.height;
    W = box.width; H = box.height;
    canvas.width = Math.round(W * scale);
    canvas.height = Math.round(H * scale);
    const next = Math.min(FIELD.maxCount, Math.round(W * H * density));
    const p = new Float32Array(next * 2), v = new Float32Array(next * 2), d = new Float32Array(next);
    for (let i = 0; i < next; i++) {
      if (i < count) {
        p[i * 2] = pos[i * 2] * (W / oldW); p[i * 2 + 1] = pos[i * 2 + 1] * (H / oldH);
        v[i * 2] = vel[i * 2]; v[i * 2 + 1] = vel[i * 2 + 1];
      } else {
        p[i * 2] = Math.random() * W; p[i * 2 + 1] = Math.random() * H;
      }
      // Matches the shader's bokeh pick, so the near motes are the ones that lean with the pointer.
      d[i] = hash(i, 6.2) < L.depth ? 1 : 0.35 + 0.3 * hash(i, 9.4);
    }
    pos = p; vel = v; depth = d; count = next;
  }

  let pointerX = -1e4, pointerY = -1e4, pointerOn = 0, pointerTarget = 0;
  let leanX = 0, leanY = 0;
  listen.addEventListener("pointermove", (event) => {
    const box = host.getBoundingClientRect();
    pointerX = event.clientX - box.left; pointerY = event.clientY - box.top;
    pointerTarget = 1;
  }, { passive: true });
  listen.addEventListener("pointerleave", () => { pointerTarget = 0; });

  const flow = [0, 0];
  function step(dt, t) {
    pointerOn += (pointerTarget - pointerOn) * Math.min(1, dt * 4);
    const lx = pointerOn ? (pointerX / W - 0.5) : 0, ly = pointerOn ? (pointerY / H - 0.5) : 0;
    leanX += (lx * FIELD.parallax - leanX) * Math.min(1, dt * 2);
    leanY += (ly * FIELD.parallax - leanY) * Math.min(1, dt * 2);
    const settle = Math.exp(-FIELD.damping * dt);
    const reach2 = reach * reach;
    for (let i = 0; i < count; i++) {
      const ix = i * 2, iy = ix + 1;
      let x = pos[ix], y = pos[iy];
      curl(x / FIELD.noiseScale, y / FIELD.noiseScale + t * 0.01, flow);
      let vx = vel[ix] * settle, vy = vel[iy] * settle;
      if (pointerOn > 0.01) {
        const dx = x - pointerX, dy = y - pointerY, d2 = dx * dx + dy * dy;
        if (d2 < reach2 && d2 > 1) {
          const d = Math.sqrt(d2), falloff = (1 - d / reach) ** 2;
          const f = push * falloff * pointerOn * dt * depth[i];
          // Mostly away from the pointer, partly around it.
          vx += (dx / d - (dy / d) * FIELD.swirl) * f;
          vy += (dy / d + (dx / d) * FIELD.swirl) * f;
        }
      }
      vel[ix] = vx; vel[iy] = vy;
      x += (flow[0] * FIELD.drift * depth[i] * 2 + vx) * dt;
      y += (flow[1] * FIELD.drift * depth[i] * 2 + vy) * dt;
      // Wrap around the edges with a margin, so nothing pops in view.
      const m = 30;
      if (x < -m) x += W + 2 * m; else if (x > W + m) x -= W + 2 * m;
      if (y < -m) y += H + 2 * m; else if (y > H + m) y -= H + 2 * m;
      pos[ix] = x; pos[iy] = y;
    }
  }

  function render(t, fade) {
    for (let i = 0; i < count; i++) {
      // Near motes lean with the pointer: a hint of depth.
      const lean = depth[i] === 1 ? 1 : 0;
      draw[i * 3] = pos[i * 2] + leanX * lean;
      draw[i * 3 + 1] = pos[i * 2 + 1] + leanY * lean;
      draw[i * 3 + 2] = 1;
    }
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    gl.useProgram(prog);
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, draw.subarray(0, count * 3), gl.DYNAMIC_DRAW);
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 3, gl.FLOAT, false, 0, 0);
    gl.vertexAttribDivisor(loc, 1);
    gl.uniform1f(u("uTime"), t);
    gl.uniform1f(u("uScale"), scale);
    gl.uniform1f(u("uFade"), fade);
    gl.uniform2f(u("uResolution"), canvas.width, canvas.height);
    gl.uniform2f(u("uPointer"), pointerX, pointerY);
    gl.uniform1f(u("uPointerOn"), pointerOn);
    gl.uniform1fv(u("uL"), look);
    gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, count);
  }

  resize();
  new ResizeObserver(() => { resize(); if (still) render(0, 1); }).observe(host);
  if (still) { render(0, 1); return; }

  let visible = true, frame = 0, last = 0, t = 0, born = 0;
  const tick = (now) => {
    const dt = Math.min((now - (last || now)) / 1000, 1 / 20);
    last = now; t += dt;
    born ||= now;
    step(dt, t);
    // Fade in over a second and a half on load, so the field arrives instead of appearing.
    render(t, Math.min(1, (now - born) / 1500));
    frame = visible && !document.hidden ? requestAnimationFrame(tick) : 0;
  };
  const resume = () => { if (!frame && visible && !document.hidden) { last = 0; frame = requestAnimationFrame(tick); } };
  new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; resume(); }).observe(host);
  document.addEventListener("visibilitychange", resume);
  resume();
}
