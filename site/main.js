// Park — product page.

const CONFIG = {
  // Set to the signed, notarized download (e.g. a GitHub release asset) once the Developer ID is in place.
  DOWNLOAD_URL: "https://github.com/spencerceverett-maker/park/releases/latest/download/Park.zip",
  // TODO: set to the tip page (Buy Me a Coffee or Ko-fi) once the account exists.
  TIP_URL: null,
  REPO_URL: "https://github.com/spencerceverett-maker/park",
};

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
// ?reduced in the URL forces reduced motion, so it can be checked without changing system settings.
const forcedReduced = document.documentElement.classList.contains("reduce-motion");
const systemReduced = matchMedia("(prefers-reduced-motion: reduce)");
const reducedMotion = { get matches() { return forcedReduced || systemReduced.matches; } };
const finePointer = matchMedia("(hover: hover) and (pointer: fine)");

/* ---------- Links that depend on what's available ---------- */

function wireLinks() {
  const install = `${CONFIG.REPO_URL}#install`;
  for (const link of $$("[data-download]")) {
    link.href = CONFIG.DOWNLOAD_URL ?? install;
    if (!CONFIG.DOWNLOAD_URL && link.matches(".pill, .dock-button")) link.textContent = "Get Park";
  }
  if (!CONFIG.DOWNLOAD_URL) {
    const label = $("[data-download-label]");
    if (label) label.textContent = "Get Park on GitHub";
    const note = $("[data-download-note]");
    if (note) note.textContent = "Free and open source · macOS 14 or later · A signed download is coming soon";
  }

  const tip = $("[data-tip]");
  const tipNote = $("[data-tip-note]");
  const chips = $$("[data-amount]");
  const choose = (chip) => {
    for (const other of chips) other.setAttribute("aria-pressed", String(other === chip));
    tip.textContent = `Buy me a $${chip.dataset.amount} coffee`;
  };
  chips.forEach((chip) => chip.addEventListener("click", () => choose(chip)));
  tip.href = CONFIG.TIP_URL ?? CONFIG.REPO_URL;
  if (!CONFIG.TIP_URL) {
    tip.textContent = "Star Park on GitHub";
    tipNote.textContent = "The tip jar opens soon. Until then, a star on GitHub helps more people find Park.";
    $(".tips").hidden = true;
  }
}

/* ---------- Motion: a critically damped spring, as a CSS linear() curve ---------- */

function installSpring() {
  if (!CSS.supports("transition-timing-function", "linear(0, 1)")) return;
  // x(t) = 1 − (1 + ωt)e^(−ωt), response 0.42 s. Sampled across the 640 ms the transitions use.
  const omega = (2 * Math.PI) / 0.42;
  const duration = 0.64;
  const points = [];
  for (let i = 0; i <= 40; i++) {
    const t = (i / 40) * duration;
    const x = 1 - (1 + omega * t) * Math.exp(-omega * t);
    points.push(x.toFixed(4));
  }
  points[points.length - 1] = "1";
  document.documentElement.style.setProperty("--spring", `linear(${points.join(", ")})`);
}

/* ---------- Floating nav and download card follow the scroll ---------- */

function wireScroll() {
  const nav = $("[data-nav]");
  const hero = $(".hero");
  const dock = $("[data-dock]");
  const support = $("#support");
  let queued = false;

  const update = () => {
    queued = false;
    const heroBottom = hero.getBoundingClientRect().bottom;
    nav.classList.toggle("is-solid", heroBottom < 80);
    const supportRect = support.getBoundingClientRect();
    const supportVisible = supportRect.top < innerHeight && supportRect.bottom > 0;
    const atEnd = innerHeight + scrollY >= document.documentElement.scrollHeight - 40;
    dock.hidden = !(heroBottom < 0 && !supportVisible && !atEnd);
  };
  addEventListener("scroll", () => {
    if (!queued) { queued = true; requestAnimationFrame(update); }
  }, { passive: true });
  addEventListener("resize", update);
  update();
}

/* ---------- Demo video ---------- */

function wireVideo() {
  const video = $("[data-video]");
  const toggle = $("[data-video-toggle]");
  const frame = video.closest(".video-frame");
  const sync = () => {
    frame.classList.toggle("is-paused", video.paused);
    toggle.setAttribute("aria-label", video.paused ? "Play video" : "Pause video");
  };
  if (reducedMotion.matches) { video.removeAttribute("autoplay"); video.pause(); }
  toggle.addEventListener("click", () => (video.paused ? video.play() : video.pause()));
  video.addEventListener("play", sync);
  video.addEventListener("pause", sync);
  sync();
}

/* ---------- The live demo: a little Mac you can actually use ---------- */

// The browser in the demo matches the visitor's, when Park supports it (see wireBrowserIcon).
const demoBrowser = { name: "Chrome", icon: "assets/icons/chrome.png" };
const APP_NAMES = { figma: "Figma", warp: "Warp" };
const APP_ICONS = { figma: "assets/icons/figma.png", warp: "assets/icons/warp.png" };
const appName = (win) => (win.dataset.app === "browser" ? demoBrowser.name : APP_NAMES[win.dataset.app]);
const appIcon = (win) => (win.dataset.app === "browser" ? demoBrowser.icon : APP_ICONS[win.dataset.app]);
let refreshDemo = () => {};

/** Joins names the way people write them: "A", "A and B", "A, B and C". */
function nameList(names) {
  if (names.length < 2) return names[0] ?? "";
  return `${names.slice(0, -1).join(", ")} and ${names.at(-1)}`;
}

/**
 * Critically damped spring for one 2D value, from the current position and velocity.
 * Drag releases and Show Desktop use it, so motion always continues from where it is.
 */
function springTo(state, target, onFrame, { response = 0.36 } = {}) {
  cancelAnimationFrame(state.frame);
  if (reducedMotion.matches) {
    state.x = target.x; state.y = target.y; state.vx = state.vy = 0;
    onFrame();
    return;
  }
  const omega = (2 * Math.PI) / response;
  let last = performance.now();
  const step = (now) => {
    const dt = Math.min(0.032, (now - last) / 1000);
    last = now;
    for (const axis of ["x", "y"]) {
      const v = axis === "x" ? "vx" : "vy";
      const accel = -omega * omega * (state[axis] - target[axis]) - 2 * omega * state[v];
      state[v] += accel * dt;
      state[axis] += state[v] * dt;
    }
    onFrame();
    const settled = Math.abs(state.x - target.x) < 0.3 && Math.abs(state.y - target.y) < 0.3
      && Math.abs(state.vx) < 8 && Math.abs(state.vy) < 8;
    if (settled) { state.x = target.x; state.y = target.y; state.vx = state.vy = 0; onFrame(); return; }
    state.frame = requestAnimationFrame(step);
  };
  state.frame = requestAnimationFrame(step);
}

/** Past an edge, the window still follows, with increasing resistance. */
const rubberband = (over, size) => (over * size * 0.55) / (size + 0.55 * Math.abs(over));

function wireDemo() {
  const display = $(".display");
  const panel = $("[data-panel]");
  const panelSlot = $(".panel-slot");
  const toggle = $("[data-toggle-panel]");
  const desk = $("[data-desk]");
  const windows = $$("[data-win]", desk);
  const draggables = $$("[data-drag]", desk);
  const about = $("[data-about]", desk);
  const parkButton = $("[data-park]");
  const parkLabel = $("[data-park-label]");
  const rowWrap = $("[data-new-row]");
  const row = $("[data-restore]");
  const rowStack = $(".stack", row);
  const rowSub = $(".p-sub", row);
  const rowFreed = $("[data-freed]", row);
  const rows = $("[data-rows]");
  const count = $("[data-count]");
  const memoryText = $("[data-memory]");
  const menubarMemory = $("[data-menubar-memory]");
  const meter = $("[data-meter]");
  const foot = $(".p-foot");
  const toast = $("[data-toast]");
  const tryChip = $(".try-chip");
  const announce = $("[data-announce]");
  const sleep = $("[data-sleep]");
  const preview = {
    stack: $("[data-preview-stack]"),
    empty: $("[data-preview-empty]"),
    title: $("[data-preview-title]"),
    sub: $("[data-preview-sub]"),
  };

  const BASE_MEMORY = 10.8;   // everything else on this Mac
  const TOTAL = 16;
  let memory = 13.1;
  let memoryFrame = 0;
  let timers = [];
  let parkedSet = [];        // windows currently in the parked row, in the order they flew in
  let showingDesktop = false;
  let viewMode = "Icons";   // View ▸ as Icons/List/Columns only moves its checkmark

  // Per window: "open" | "minimized" | "closed" | "parked", plus its dragged offset (a share of the desk's size).
  const state = new Map(draggables.map((win) => [win, {
    status: win === about ? "closed" : "open",
    fx: 0, fy: 0, x: 0, y: 0, vx: 0, vy: 0, frame: 0, aside: { x: 0, y: 0 },
  }]));
  let order = [...windows];   // back to front

  const later = (ms, fn) => timers.push(setTimeout(fn, ms));
  const clearTimers = () => { timers.forEach(clearTimeout); timers = []; };
  const memOf = (win) => Number(win.dataset.mem || 0);
  const isPresent = (win) => ["open", "minimized"].includes(state.get(win).status);
  const isVisible = (win) => state.get(win).status === "open";
  const fmt = (gb) => `${gb.toFixed(1)} GB`;

  /* ---- Geometry ---- */

  const deskSize = () => ({ w: desk.clientWidth, h: desk.clientHeight });

  const hero = desk.closest(".hero");

  /**
   * Where a window may sit: within the part of the desktop you can actually see (the hero card crops
   * it), always keeping the title bar and a good piece of the window on screen.
   */
  function bounds(win) {
    const { w, h } = deskSize();
    const deskBox = desk.getBoundingClientRect();
    const clip = hero?.getBoundingClientRect();
    const visibleW = clip ? Math.min(w, clip.right - deskBox.left - 8) : w;
    const visibleH = clip ? Math.min(h, clip.bottom - deskBox.top - 8) : h;
    const keepX = Math.min(win.offsetWidth * 0.4, 160);
    const keepY = Math.min(win.offsetHeight * 0.45, 90);
    return {
      minX: -win.offsetLeft - win.offsetWidth + keepX,
      maxX: visibleW - win.offsetLeft - keepX,
      minY: -win.offsetTop,
      maxY: visibleH - win.offsetTop - keepY,
    };
  }

  function render(win) {
    const s = state.get(win);
    win.style.translate = `${s.x + s.aside.x}px ${s.y + s.aside.y}px`;
  }

  function syncFromFractions() {
    const { w, h } = deskSize();
    for (const [win, s] of state) {
      cancelAnimationFrame(s.frame);
      s.x = s.fx * w; s.y = s.fy * h;
      if (showingDesktop) s.aside = asideVector(win);
      render(win);
    }
  }
  new ResizeObserver(syncFromFractions).observe(desk);

  /* ---- Focus and stacking ---- */

  function restack() {
    order.forEach((win, i) => { win.style.zIndex = String(i + 1); });
    const top = [...order].reverse().find(isVisible);
    for (const win of draggables) win.classList.toggle("is-focused", win === top);
  }

  function bringToFront(win) {
    order = order.filter((w) => w !== win).concat(win);
    restack();
  }

  /* ---- Dragging by the title bar ---- */

  for (const win of draggables) {
    const bar = $(".win-bar", win);
    let drag = null;

    win.addEventListener("pointerdown", () => { if (isVisible(win)) bringToFront(win); });

    bar.addEventListener("pointerdown", (event) => {
      if (drag || event.button !== 0 || event.target.closest(".tl") || !isVisible(win)) return;
      if (showingDesktop) toggleShowDesktop(false);
      const s = state.get(win);
      cancelAnimationFrame(s.frame);
      drag = { id: event.pointerId, startX: event.clientX - s.x, startY: event.clientY - s.y, history: [] };
      try { bar.setPointerCapture(event.pointerId); } catch {}
      // Parking or closing mid-drag lets go of the window.
      s.cancelDrag = () => {
        if (!drag) return;
        try { bar.releasePointerCapture(drag.id); } catch {}
        const size = deskSize();
        s.fx = s.x / size.w; s.fy = s.y / size.h;   // remember where it was let go, for resizes
        drag = null;
        win.classList.remove("is-dragging");
      };
      win.classList.add("is-dragging");
      closeMenus();
    });

    bar.addEventListener("pointermove", (event) => {
      if (!drag || event.pointerId !== drag.id) return;
      const s = state.get(win);
      const b = bounds(win);
      const { w, h } = deskSize();
      let x = event.clientX - drag.startX;
      let y = event.clientY - drag.startY;
      // Past the edges the window resists instead of stopping dead.
      if (x < b.minX) x = b.minX + rubberband(x - b.minX, w);
      if (x > b.maxX) x = b.maxX + rubberband(x - b.maxX, w);
      if (y < b.minY) y = b.minY + rubberband(y - b.minY, h);
      if (y > b.maxY) y = b.maxY + rubberband(y - b.maxY, h);
      s.x = x; s.y = y;
      drag.history.push({ x: event.clientX, y: event.clientY, t: event.timeStamp });
      // Only the last tenth of a second matters for the release velocity.
      while (drag.history.length > 2 && event.timeStamp - drag.history[0].t > 100) drag.history.shift();
      render(win);
    });

    const end = (event) => {
      if (!drag || event.pointerId !== drag.id) return;
      const s = state.get(win);
      const b = bounds(win);
      // Hand the release velocity to the spring, and let it carry the window a little further.
      const hist = drag.history;
      const first = hist[0], last = hist.at(-1);
      const dt = hist.length > 2 && last.t - first.t > 16 ? (last.t - first.t) / 1000 : 0;
      const cap = (v) => Math.max(-1800, Math.min(1800, v));
      s.vx = dt ? cap((last.x - first.x) / dt) : 0;
      s.vy = dt ? cap((last.y - first.y) / dt) : 0;
      // Apple's deceleration projection, kept short: a flick nudges a window, it doesn't throw it.
      const projection = 0.99 / (1 - 0.99) / 1000 * 0.6;
      const target = {
        x: Math.min(b.maxX, Math.max(b.minX, s.x + s.vx * projection)),
        y: Math.min(b.maxY, Math.max(b.minY, s.y + s.vy * projection)),
      };
      drag = null;
      win.classList.remove("is-dragging");
      const size = deskSize();
      s.fx = target.x / size.w; s.fy = target.y / size.h;
      springTo(s, target, () => render(win));
    };
    bar.addEventListener("pointerup", end);
    bar.addEventListener("pointercancel", end);
    bar.addEventListener("lostpointercapture", end);

    // Traffic lights.
    $("[data-close]", win)?.addEventListener("click", () => closeWindow(win));
    $("[data-minimize]", win)?.addEventListener("click", () => minimizeWindow(win));
    $("[data-zoom]", win)?.addEventListener("click", () => bringToFront(win));
  }

  /* ---- Open, close, minimize ---- */

  function setStatus(win, status) {
    state.get(win).status = status;
    win.classList.toggle("is-closed", status === "closed");
    win.classList.toggle("is-minimized", status === "minimized");
  }

  function closeWindow(win) {
    if (!isVisible(win)) return;
    state.get(win).cancelDrag?.();
    setStatus(win, "closed");
    restack();
    if (win !== about) refreshDemo();
  }

  function minimizeWindow(win) {
    if (!isVisible(win) || win === about) return;
    state.get(win).cancelDrag?.();
    setStatus(win, "minimized");
    restack();
    refreshDemo();
  }

  /** Brings a closed or minimized window back, with the same motion it left with, reversed. */
  function openWindow(win) {
    const s = state.get(win);
    if (s.status === "parked") return;
    if (s.status !== "open") {
      const cls = s.status === "minimized" ? "is-unminimizing" : "is-opening";
      win.classList.add(cls);
      setStatus(win, "open");
      // Not a cancellable demo timer: this cleanup must always run.
      setTimeout(() => win.classList.remove(cls), 460);
    }
    bringToFront(win);
    if (win !== about) refreshDemo();
  }

  /* ---- Memory, preview and the parked row ---- */

  function targetMemory() {
    return draggables.filter((w) => w !== about && isPresent(w)).reduce((sum, w) => sum + memOf(w), BASE_MEMORY);
  }

  function setMemory(target) {
    cancelAnimationFrame(memoryFrame);
    const from = memory;
    const duration = reducedMotion.matches ? 0 : 1100;
    const start = performance.now();
    const step = (now) => {
      const t = duration ? Math.min(1, (now - start) / duration) : 1;
      memory = from + (target - from) * (1 - Math.pow(1 - t, 4));
      memoryText.textContent = memory.toFixed(1);
      menubarMemory.textContent = fmt(memory);
      updateAbout();
      if (t < 1) memoryFrame = requestAnimationFrame(step);
    };
    memoryFrame = requestAnimationFrame(step);
    meter.style.transform = `scaleX(${target / TOTAL})`;
    meter.classList.toggle("is-calm", target / TOTAL < 0.75);
  }

  function updateAbout() {
    $("[data-about-memory]").textContent = `${memory.toFixed(1)} GB of 16 GB in use`;
    $("[data-about-desktops]").textContent = parkedSet.length ? "4, one of them parked" : "4, all of them open";
  }

  const icons = (wins) => wins.map((w) => `<img src="${appIcon(w)}" alt="">`).join("");

  function updatePreview() {
    const present = windows.filter(isPresent);
    const empty = present.length === 0;
    preview.stack.hidden = empty;
    preview.empty.hidden = !empty;
    preview.stack.innerHTML = icons(present);
    preview.title.textContent = empty ? "Nothing open here" : nameList([...new Set(present.map(appName))]);
    preview.sub.textContent = empty
      ? "Switch to a desktop with windows to park it"
      : `${present.length} window${present.length === 1 ? "" : "s"} on this desktop`;
    parkButton.disabled = empty;
  }

  function updateRow() {
    const n = parkedSet.length;
    rowStack.innerHTML = icons(parkedSet);
    rowSub.textContent = `${n} window${n === 1 ? "" : "s"} · Just now`;
    rowFreed.textContent = fmt(parkedSet.reduce((sum, w) => sum + memOf(w), 0));
  }

  refreshDemo = () => {
    updatePreview();
    if (parkedSet.length) updateRow();
    setMemory(targetMemory());
  };

  toggle.addEventListener("click", (event) => {
    event.stopPropagation();
    const open = toggle.getAttribute("aria-expanded") !== "true";
    if (open) closeMenus();
    setPanel(open);
  });

  function setPanel(open) {
    toggle.setAttribute("aria-expanded", String(open));
    panel.classList.toggle("is-hidden", !open);
  }

  function showToast(message) {
    toast.innerHTML = `<svg viewBox="0 0 16 16" width="13" height="13" aria-hidden="true"><circle cx="8" cy="8" r="8" fill="currentColor"/><path d="m4.6 8.2 2.3 2.3 4.5-4.7" fill="none" stroke="#fff" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg><span></span>`;
    toast.lastChild.textContent = message;
    foot.classList.add("has-toast");
    later(2600, () => foot.classList.remove("has-toast"));
  }

  /* ---- Park and restore: windows go from wherever they are, and come back there ---- */

  function park() {
    const going = windows.filter(isPresent);
    if (!going.length) return;
    clearTimers();
    if (showingDesktop) toggleShowDesktop(false, { instant: true });
    tryChip?.classList.add("is-done");
    const hadFocus = document.activeElement === parkButton;

    rowWrap.classList.add("is-open");
    row.classList.add("is-fresh");
    row.classList.remove("has-freed");
    row.tabIndex = 0;
    const startIndex = parkedSet.length;
    parkedSet = parkedSet.concat(going);
    updateRow();

    const list = rows.getBoundingClientRect();
    going.forEach((win, i) => {
      const s = state.get(win);
      cancelAnimationFrame(s.frame);
      // Fly from the window's current spot (its CSS place plus wherever it was dragged).
      const box = win.getBoundingClientRect();
      const wasMinimized = s.status === "minimized";
      const targetX = list.left + 16 + Math.min(startIndex + i, 2) * 15;
      const targetY = list.top + 13;
      win.style.setProperty("--tx", `${targetX - box.left}px`);
      win.style.setProperty("--ty", `${targetY - box.top}px`);
      win.style.setProperty("--sc", String(22 / win.offsetWidth));
      win.style.transitionDelay = wasMinimized ? "" : `${i * 45}ms, ${300 + i * 45}ms`;
      s.cancelDrag?.();
      win.classList.remove("is-minimized", "is-opening", "is-unminimizing", "is-dragging");
      s.status = "parked";
      win.classList.add("is-parked");
    });
    restack();

    parkLabel.textContent = "Parking…";
    later(420, () => {
      parkLabel.textContent = "Park this desktop";
      updatePreview();
      count.textContent = "3";
      if (hadFocus) row.focus({ preventScroll: true });
    });
    later(300, () => setMemory(targetMemory()));
    const n = going.length;
    later(700, () => showToast(`Parked ${n} window${n === 1 ? "" : "s"}`));
    later(1400, () => row.classList.add("has-freed"));
    later(1700, () => row.classList.remove("is-fresh"));
    announce.textContent = `Parked ${n} window${n === 1 ? "" : "s"}.`;
  }

  function restore() {
    if (!parkedSet.length) return;
    clearTimers();
    const hadFocus = document.activeElement === row;
    const coming = parkedSet;
    parkedSet = [];

    coming.forEach((win, i) => {
      win.style.transitionDelay = `${(coming.length - 1 - i) * 40}ms, 0ms`;
      state.get(win).status = "open";
      win.classList.remove("is-parked");
      bringToFront(win);
    });
    rowWrap.classList.remove("is-open");
    row.classList.remove("is-fresh", "has-freed");
    row.tabIndex = -1;
    parkLabel.textContent = "Park this desktop";
    updatePreview();
    count.textContent = "2";
    if (hadFocus) parkButton.focus({ preventScroll: true });
    setMemory(targetMemory());
    later(200, () => showToast("Restored “Onboarding redesign”"));
    announce.textContent = `Restored Onboarding redesign. ${coming.length} window${coming.length === 1 ? " is" : "s are"} back.`;
  }

  // Clear the per-window delays once a window has finished flying, so later moves aren't delayed.
  for (const win of windows) {
    win.addEventListener("transitionend", (event) => { if (event.propertyName === "transform") win.style.transitionDelay = ""; });
  }

  parkButton.addEventListener("click", park);
  row.addEventListener("click", restore);
  panel.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && event.target === panel) park();
  });

  /* ---- Show Desktop: windows slide to the nearest edge, and back ---- */

  function asideVector(win) {
    const { w, h } = deskSize();
    const s = state.get(win);
    const cx = win.offsetLeft + s.x + win.offsetWidth / 2;
    const cy = win.offsetTop + s.y + win.offsetHeight / 2;
    const left = cx < w / 2;
    return {
      x: left ? -(win.offsetLeft + s.x + win.offsetWidth * 0.86) : w - (win.offsetLeft + s.x) - win.offsetWidth * 0.14,
      y: (cy < h / 2 ? -1 : 1) * h * 0.06,
    };
  }

  const asideAnim = new Map(draggables.map((w) => [w, { x: 0, y: 0, vx: 0, vy: 0, frame: 0 }]));
  function toggleShowDesktop(force, { instant = false } = {}) {
    showingDesktop = force ?? !showingDesktop;
    for (const win of draggables) {
      const s = state.get(win);
      const a = asideAnim.get(win);
      const target = showingDesktop && isVisible(win) ? asideVector(win) : { x: 0, y: 0 };
      a.x = s.aside.x; a.y = s.aside.y;
      if (instant) { cancelAnimationFrame(a.frame); s.aside = target; render(win); continue; }
      springTo(a, target, () => { s.aside = { x: a.x, y: a.y }; render(win); }, { response: 0.5 });
    }
  }
  display.addEventListener("pointerdown", (event) => {
    // Clicking the bare desktop while windows are aside brings them back, as on macOS.
    if (showingDesktop && event.target === desk) toggleShowDesktop(false);
  });

  /* ---- Sleep ---- */

  function goToSleep() {
    sleep.classList.add("is-on");
    const wake = () => { sleep.classList.remove("is-on"); };
    sleep.addEventListener("pointerdown", wake, { once: true });
    later(60, () => document.addEventListener("keydown", wake, { once: true }));
  }

  /* ---- Menus ---- */

  const menubar = $("[data-menubar]");
  const titles = $$("[data-menu]", menubar);
  const layer = $("[data-menu-layer]");
  const focusedWindow = () => [...order].reverse().find(isVisible);

  // Each item: label, key equivalent, and an action (or disabled). A function builds menus that depend on state.
  const MENUS = {
    apple: () => [
      { label: "About This Mac", act: () => { openWindow(about); updateAbout(); } },
      "—",
      { label: "System Settings…", disabled: true },
      { label: "App Store…", disabled: true },
      "—",
      { label: "Force Quit…", key: "⌥⌘⎋", disabled: true },
      "—",
      { label: "Sleep", act: goToSleep },
      { label: "Restart…", disabled: true },
      { label: "Shut Down…", disabled: true },
      "—",
      { label: "Lock Screen", key: "⌃⌘Q", act: goToSleep },
    ],
    finder: () => [
      { label: "About Finder", disabled: true },
      "—",
      { label: "Settings…", key: "⌘,", disabled: true },
      "—",
      { label: "Hide Finder", key: "⌘H", disabled: true },
      { label: "Hide Others", key: "⌥⌘H", act: () => toggleShowDesktop(true) },
      { label: "Show All", disabled: !showingDesktop, act: () => toggleShowDesktop(false) },
    ],
    file: () => {
      const closed = windows.filter((w) => state.get(w).status === "closed");
      return [
        { label: "New Window", key: "⌘N", disabled: !closed.length, act: () => openWindow(closed.at(-1)) },
        { label: "Open…", key: "⌘O", disabled: true },
        "—",
        { label: "Close Window", key: "⌘W", disabled: !focusedWindow(), act: () => closeWindow(focusedWindow()) },
        "—",
        { label: "Get Info", key: "⌘I", disabled: true },
      ];
    },
    edit: () => [
      { label: "Undo", key: "⌘Z", disabled: true },
      { label: "Redo", key: "⇧⌘Z", disabled: true },
      "—",
      { label: "Cut", key: "⌘X", disabled: true },
      { label: "Copy", key: "⌘C", disabled: true },
      { label: "Paste", key: "⌘V", disabled: true },
      { label: "Select All", key: "⌘A", disabled: true },
    ],
    view: () => [
      ...["Icons", "List", "Columns"].map((mode, i) => (
        { label: `as ${mode}`, key: `⌘${i + 1}`, checked: viewMode === mode, act: () => { viewMode = mode; } }
      )),
      "—",
      { label: showingDesktop ? "Hide Desktop" : "Show Desktop", key: "F11", act: () => toggleShowDesktop() },
    ],
    go: () => [
      { label: "Back", key: "⌘[", disabled: true },
      { label: "Forward", key: "⌘]", disabled: true },
      "—",
      { label: "Recents", key: "⇧⌘F", act: () => {} },
      { label: "Documents", key: "⇧⌘O", act: () => {} },
      { label: "Desktop", key: "⇧⌘D", act: () => toggleShowDesktop(true) },
      { label: "Downloads", key: "⌥⌘L", act: () => {} },
      { label: "Home", key: "⇧⌘H", act: () => {} },
    ],
    window: () => {
      const front = focusedWindow();
      const any = windows.some(isPresent);
      return [
        { label: "Minimize", key: "⌘M", disabled: !front || front === about, act: () => minimizeWindow(front) },
        { label: "Zoom", disabled: true },
        "—",
        { label: "Park This Desktop", key: "⌃⌥⌘P", disabled: !any, act: parkFromMenu },
        "—",
        { label: "Bring All to Front", disabled: !windows.some(isVisible), act: () => windows.filter(isVisible).forEach(bringToFront) },
        "—",
        ...windows.map((w) => {
          const st = state.get(w).status;
          return { label: w.dataset.title, checked: w === front, dot: st === "minimized", disabled: st === "parked", act: () => openWindow(w) };
        }),
      ];
    },
    help: () => [
      { search: true },
      { label: "Park Help", act: () => document.querySelector("#faq")?.scrollIntoView({ behavior: reducedMotion.matches ? "auto" : "smooth" }) },
      { label: "Mac User Guide", disabled: true },
    ],
  };

  function parkFromMenu() {
    // Show the panel first so the windows have somewhere to fly to.
    setPanel(true);
    requestAnimationFrame(() => requestAnimationFrame(park));
  }

  let openKey = null;
  let menuEl = null;

  function closeMenus({ focusTitle = false } = {}) {
    if (!openKey) return;
    const title = titles.find((t) => t.dataset.menu === openKey);
    title.setAttribute("aria-expanded", "false");
    const leaving = menuEl;
    leaving.classList.add("is-leaving");
    setTimeout(() => leaving.remove(), reducedMotion.matches ? 0 : 150);
    openKey = null; menuEl = null;
    if (focusTitle) title.focus();
  }

  function openMenu(key, { focusFirst = false } = {}) {
    if (openKey === key) return;
    if (openKey) {
      // Switching between menus is instant, as on a Mac.
      titles.find((t) => t.dataset.menu === openKey).setAttribute("aria-expanded", "false");
      menuEl.remove();
    }
    // The menu bar's menus and Park's panel never show at once (desktop layout only).
    if (getComputedStyle(panelSlot).position === "absolute") setPanel(false);
    const title = titles.find((t) => t.dataset.menu === key);
    openKey = key;
    title.setAttribute("aria-expanded", "true");
    menuEl = buildMenu(key, title);
    layer.append(menuEl);
    // Keep the menu on the little screen.
    const max = layer.clientWidth - menuEl.offsetWidth - 6;
    menuEl.style.left = `${Math.max(6, Math.min(title.offsetLeft - 5, max))}px`;
    // A menu with nothing enabled (Edit, here) takes focus itself, so the arrow keys and Escape still work.
    if (focusFirst) (items(menuEl)[0] ?? menuEl).focus();
  }

  const items = (menu) => $$(".mi:not([aria-disabled='true'])", menu);

  function buildMenu(key, title) {
    const menu = document.createElement("div");
    menu.className = "mac-menu";
    menu.tabIndex = -1;
    menu.setAttribute("role", "menu");
    menu.setAttribute("aria-label", title.getAttribute("aria-label") || title.textContent);
    for (const entry of MENUS[key]()) {
      if (entry === "—") {
        const hr = document.createElement("hr");
        hr.setAttribute("role", "separator");
        menu.append(hr);
        continue;
      }
      if (entry.search) {
        const box = document.createElement("div");
        box.className = "mi-search";
        box.innerHTML = "<span>Search</span>";
        box.setAttribute("aria-hidden", "true");
        menu.append(box);
        continue;
      }
      const item = document.createElement("button");
      item.type = "button";
      item.className = "mi" + (entry.dot ? " mi-dot" : "");
      item.tabIndex = -1;
      if (entry.checked !== undefined) {
        item.setAttribute("role", "menuitemcheckbox");
        item.setAttribute("aria-checked", String(Boolean(entry.checked)));
      } else {
        item.setAttribute("role", "menuitem");
      }
      if (entry.disabled) item.setAttribute("aria-disabled", "true");
      item.innerHTML = "<span></span>" + (entry.key ? `<kbd aria-hidden="true">${entry.key}</kbd>` : "");
      item.firstChild.textContent = entry.label;
      item.addEventListener("click", (event) => {
        event.stopPropagation();
        if (entry.disabled) return;
        closeMenus({ focusTitle: event.detail === 0 });
        entry.act?.();
      });
      item.addEventListener("pointerenter", () => { if (!entry.disabled) item.focus({ preventScroll: true }); });
      menu.append(item);
    }
    menu.addEventListener("keydown", (event) => {
      const list = items(menu);
      const i = list.indexOf(document.activeElement);
      const titleIndex = titles.indexOf(titles.find((t) => t.dataset.menu === key));
      const visibleTitles = titles.filter((t) => t.offsetParent);
      const vi = visibleTitles.indexOf(titles[titleIndex]);
      if (event.key === "ArrowDown") { event.preventDefault(); list[(i + 1) % list.length]?.focus(); }
      else if (event.key === "ArrowUp") { event.preventDefault(); list[(i - 1 + list.length) % list.length]?.focus(); }
      else if (event.key === "Home") { event.preventDefault(); list[0]?.focus(); }
      else if (event.key === "End") { event.preventDefault(); list.at(-1)?.focus(); }
      else if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
        event.preventDefault();
        const next = visibleTitles[(vi + (event.key === "ArrowRight" ? 1 : -1) + visibleTitles.length) % visibleTitles.length];
        setRoving(next);
        openMenu(next.dataset.menu, { focusFirst: true });
      } else if (event.key === "Escape") { event.preventDefault(); closeMenus({ focusTitle: true }); }
      else if (event.key === "Tab") { closeMenus(); }
    });
    return menu;
  }

  function setRoving(title) { titles.forEach((t) => { t.tabIndex = t === title ? 0 : -1; }); }

  titles.forEach((title) => {
    title.addEventListener("pointerdown", (event) => {
      if (event.button !== 0) return;
      event.preventDefault();      // menus open on press, like macOS
      event.stopPropagation();
      setRoving(title);
      if (openKey === title.dataset.menu) closeMenus(); else openMenu(title.dataset.menu);
    });
    // While a menu is open, sliding across the bar switches menus.
    title.addEventListener("pointerenter", () => { if (openKey && openKey !== title.dataset.menu) openMenu(title.dataset.menu); });
    title.addEventListener("click", (event) => {
      // Keyboard activation (Enter/Space) arrives as a click without a pointer press.
      if (event.detail !== 0) return;
      if (openKey === title.dataset.menu) closeMenus(); else openMenu(title.dataset.menu, { focusFirst: true });
    });
    title.addEventListener("keydown", (event) => {
      const visibleTitles = titles.filter((t) => t.offsetParent);
      const vi = visibleTitles.indexOf(title);
      if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
        event.preventDefault();
        const next = visibleTitles[(vi + (event.key === "ArrowRight" ? 1 : -1) + visibleTitles.length) % visibleTitles.length];
        setRoving(next);
        next.focus();
        if (openKey) openMenu(next.dataset.menu);
      } else if (event.key === "ArrowDown") {
        event.preventDefault();
        openMenu(title.dataset.menu, { focusFirst: true });
      } else if (event.key === "Escape") {
        closeMenus({ focusTitle: true });
      }
    });
  });

  document.addEventListener("pointerdown", (event) => {
    if (openKey && !event.target.closest(".mac-menu") && !event.target.closest("[data-menubar]")) closeMenus();
  });

  /* ---- About This Mac ---- */

  $("[data-about-more]").addEventListener("click", () => {
    closeWindow(about);
    document.querySelector("#how")?.scrollIntoView({ behavior: reducedMotion.matches ? "auto" : "smooth" });
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && isVisible(about) && !openKey) closeWindow(about);
  });

  restack();
  refreshDemo();
  meter.style.transform = `scaleX(${memory / TOTAL})`;
}

/* ---------- Reveals: headings rise word by word, copy fades up, once ---------- */

function splitWords(element) {
  let i = 0;
  const walk = (node) => {
    for (const child of [...node.childNodes]) {
      if (child.nodeType === Node.TEXT_NODE) {
        const parts = child.textContent.split(/(\s+)/);
        const fragment = document.createDocumentFragment();
        for (const part of parts) {
          if (!part) continue;
          if (/^\s+$/.test(part)) { fragment.append(part); continue; }
          const word = document.createElement("span");
          word.className = "word";
          word.style.setProperty("--i", i++);
          word.textContent = part;
          fragment.append(word);
        }
        child.replaceWith(fragment);
      } else if (child.nodeType === Node.ELEMENT_NODE) {
        walk(child);
      }
    }
  };
  walk(element);
  element.classList.add("split");
}

function wireReveals() {
  if (reducedMotion.matches || !("IntersectionObserver" in window)) return;

  const headings = $$(".hero h1, .section h2:not(.sr-only)");
  headings.forEach(splitWords);

  // Copy fades up after its heading; items in a list follow each other closely.
  const fades = [
    ...$$(".hero-icon, .hero .lede, .hero-actions, .hero .meta, .stage"),
    ...$$(".section-lede, .reading p, .features-intro p, .video-frame, .tips, .support .button, .meta-dark"),
    ...$$(".steps li, .restores li, .detail-list li, .faq details"),
  ];
  fades.forEach((element) => element.classList.add("fade"));

  const delays = new Map([
    [".hero-icon", 0], [".hero .lede", 320], [".hero-actions", 420], [".hero .meta", 480], [".stage", 560],
  ]);
  for (const [selector, ms] of delays) {
    const element = $(selector);
    if (element) element.style.setProperty("--d", `${ms}ms`);
  }
  for (const list of $$(".steps, .restores, .detail-list, .faq-inner")) {
    $$(".fade", list).forEach((item, index) => item.style.setProperty("--d", `${Math.min(index, 8) * 60}ms`));
  }
  $(".hero h1").style.setProperty("--d", "80ms");

  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("is-in");
      observer.unobserve(entry.target);
    }
  }, { rootMargin: "0px 0px -8% 0px", threshold: 0.15 });

  // Wait a frame so the hidden state paints before the hero animates in.
  requestAnimationFrame(() => requestAnimationFrame(() => {
    [...headings, ...fades].forEach((element) => observer.observe(element));
  }));
}

/* ---------- Daylight: drifts on its own, leans gently toward the pointer ---------- */

function wireLight() {
  const hero = $(".hero");
  const light = $("[data-light]");
  if (!hero || !light) return;

  // Pause the drift when the hero is off screen; CSS handles hidden tabs.
  new IntersectionObserver(([entry]) => hero.classList.toggle("is-offscreen", !entry.isIntersecting)).observe(hero);
  if (reducedMotion.matches || !finePointer.matches) return;

  let targetX = 0, targetY = 0, x = 0, y = 0, frame = 0;
  const step = () => {
    // Heavy damping: the light follows like something with weight.
    x += (targetX - x) * 0.045;
    y += (targetY - y) * 0.045;
    light.style.transform = `translate3d(${x.toFixed(2)}px, ${y.toFixed(2)}px, 0)`;
    frame = Math.abs(targetX - x) + Math.abs(targetY - y) > 0.05 ? requestAnimationFrame(step) : 0;
  };
  const aim = (nx, ny) => {
    const rect = hero.getBoundingClientRect();
    targetX = nx * rect.width * 0.025;
    targetY = ny * rect.height * 0.02;
    if (!frame) frame = requestAnimationFrame(step);
  };
  hero.addEventListener("pointermove", (event) => {
    const rect = hero.getBoundingClientRect();
    aim((event.clientX - rect.left) / rect.width - 0.5, (event.clientY - rect.top) / rect.height - 0.5);
  });
  hero.addEventListener("pointerleave", () => aim(0, 0));
}

/* ---------- Fireflies: motes float in the sky and part around the pointer ---------- */

function wireFireflies() {
  const hero = $(".hero");
  if (!hero) return;
  // With reduced motion they stay: one still frame of texture, no movement.
  import("./fireflies.js").then(({ mountFireflies }) => mountFireflies(hero, { still: reducedMotion.matches })).catch(() => {});
}

/* ---------- Buttons lean slightly toward the pointer ---------- */

function wireMagnetic() {
  if (reducedMotion.matches || !finePointer.matches) return;
  for (const button of $$(".button, .pill, .dock-button")) {
    button.addEventListener("pointermove", (event) => {
      const rect = button.getBoundingClientRect();
      const dx = (event.clientX - rect.left - rect.width / 2) / (rect.width / 2);
      const dy = (event.clientY - rect.top - rect.height / 2) / (rect.height / 2);
      button.style.setProperty("--mx", `${(dx * 3).toFixed(2)}px`);
      button.style.setProperty("--my", `${(dy * 2).toFixed(2)}px`);
    });
    button.addEventListener("pointerleave", () => {
      button.style.setProperty("--mx", "0px");
      button.style.setProperty("--my", "0px");
    });
  }
}

/** The little Mac's menu bar shows the visitor's own time, like a real one. */
function wireClock() {
  const clock = $("[data-clock]");
  if (!clock) return;
  const format = new Intl.DateTimeFormat(undefined, { weekday: "short", hour: "numeric", minute: "2-digit" });
  const tick = () => {
    clock.textContent = format.format(new Date()).replace(",", "");
    // Wake again right as the minute changes.
    setTimeout(tick, 60_000 - (Date.now() % 60_000) + 50);
  };
  tick();
}

/**
 * Show the visitor's own browser in the demo, if it's one Park restores tab by tab.
 * Anything else (Safari, Firefox, Arc) keeps Chrome rather than promising what the app doesn't do yet.
 */
async function wireBrowserIcon() {
  const ua = navigator.userAgent;
  let browser = "chrome";
  if (navigator.brave && (await navigator.brave.isBrave().catch(() => false))) browser = "brave";
  else if (/\bEdg\//.test(ua)) browser = "edge";
  else if (/\bVivaldi\//.test(ua)) browser = "vivaldi";
  if (browser === "chrome") return;
  const src = `assets/icons/${browser}.png`;
  const names = { brave: "Brave", edge: "Edge", vivaldi: "Vivaldi" };
  // Only swap once the icon has loaded, so a missing file never leaves a broken image.
  const probe = new Image();
  probe.onload = () => {
    demoBrowser.name = names[browser];
    demoBrowser.icon = src;
    $$("[data-browser-icon]").forEach((img) => { img.src = src; });
    refreshDemo();
  };
  probe.src = src;
}

installSpring();
wireLinks();
wireClock();
wireBrowserIcon();
wireScroll();
wireVideo();
wireDemo();
wireReveals();
wireLight();
wireFireflies();
wireMagnetic();
