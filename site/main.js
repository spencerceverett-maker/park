// Park — product page.

const CONFIG = {
  // Set to the signed, notarized download (e.g. a GitHub release asset) once the Developer ID is in place.
  DOWNLOAD_URL: null,
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

/* ---------- The live demo: park this desktop, then bring it back ---------- */

function wireDemo() {
  const panel = $("[data-panel]");
  const toggle = $("[data-toggle-panel]");
  const desk = $("[data-desk]");
  const windows = $$("[data-win]", desk);
  const parkButton = $("[data-park]");
  const parkLabel = $("[data-park-label]");
  const rowWrap = $("[data-new-row]");
  const row = $("[data-restore]");
  const rows = $("[data-rows]");
  const count = $("[data-count]");
  const memoryText = $("[data-memory]");
  const menubarMemory = $("[data-menubar-memory]");
  const meter = $("[data-meter]");
  const foot = $(".p-foot");
  const toast = $("[data-toast]");
  const tryChip = $(".try-chip");
  const announce = $("[data-announce]");
  const preview = {
    stack: $("[data-preview-stack]"),
    empty: $("[data-preview-empty]"),
    title: $("[data-preview-title]"),
    sub: $("[data-preview-sub]"),
  };

  const MEMORY_BEFORE = 13.1;
  const MEMORY_AFTER = 10.8;
  const TOTAL = 16;
  let parked = false;
  let memory = MEMORY_BEFORE;
  let memoryFrame = 0;
  let timers = [];

  const later = (ms, fn) => timers.push(setTimeout(fn, ms));
  const clearTimers = () => { timers.forEach(clearTimeout); timers = []; };

  toggle.addEventListener("click", () => {
    const open = toggle.getAttribute("aria-expanded") !== "true";
    toggle.setAttribute("aria-expanded", String(open));
    panel.classList.toggle("is-hidden", !open);
  });

  function setMemory(target) {
    cancelAnimationFrame(memoryFrame);
    const from = memory;
    const duration = reducedMotion.matches ? 0 : 1100;
    const start = performance.now();
    const step = (now) => {
      const t = duration ? Math.min(1, (now - start) / duration) : 1;
      const eased = 1 - Math.pow(1 - t, 4);
      memory = from + (target - from) * eased;
      memoryText.textContent = memory.toFixed(1);
      menubarMemory.textContent = `${memory.toFixed(1)} GB`;
      if (t < 1) memoryFrame = requestAnimationFrame(step);
    };
    memoryFrame = requestAnimationFrame(step);
    meter.style.transform = `scaleX(${target / TOTAL})`;
    meter.classList.toggle("is-calm", target / TOTAL < 0.75);
  }

  function showToast(message) {
    toast.innerHTML = `<svg viewBox="0 0 16 16" width="13" height="13" aria-hidden="true"><circle cx="8" cy="8" r="8" fill="currentColor"/><path d="m4.6 8.2 2.3 2.3 4.5-4.7" fill="none" stroke="#fff" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg><span></span>`;
    toast.lastChild.textContent = message;
    foot.classList.add("has-toast");
    later(2600, () => foot.classList.remove("has-toast"));
  }

  function setPreview(empty) {
    preview.stack.hidden = empty;
    preview.empty.hidden = !empty;
    preview.title.textContent = empty ? "Nothing open here" : "Chrome, Figma and Warp";
    preview.sub.textContent = empty ? "Switch to a desktop with windows to park it" : "3 windows on this desktop";
    parkButton.disabled = empty;
  }

  function park() {
    if (parked) return;
    parked = true;
    clearTimers();
    tryChip?.classList.add("is-done");
    const hadFocus = document.activeElement === parkButton;

    // The new row opens at the top of the list; each window flies to its icon in that row.
    rowWrap.classList.add("is-open");
    row.classList.add("is-fresh");
    row.classList.remove("has-freed");
    row.tabIndex = 0;
    const list = rows.getBoundingClientRect();
    const deskBox = desk.getBoundingClientRect();
    windows.forEach((win, i) => {
      const left = deskBox.left + win.offsetLeft;
      const top = deskBox.top + win.offsetTop;
      const targetX = list.left + 16 + i * 15;
      const targetY = list.top + 13;
      win.style.setProperty("--tx", `${targetX - left}px`);
      win.style.setProperty("--ty", `${targetY - top}px`);
      win.style.setProperty("--sc", String(22 / win.offsetWidth));
      win.style.transitionDelay = `${i * 45}ms, ${300 + i * 45}ms`;
      win.classList.add("is-parked");
    });

    parkLabel.textContent = "Parking…";
    later(420, () => {
      parkLabel.textContent = "Park this desktop";
      setPreview(true);
      count.textContent = "3";
      if (hadFocus) row.focus({ preventScroll: true });
    });
    later(300, () => setMemory(MEMORY_AFTER));
    later(700, () => showToast("Parked 3 windows"));
    later(1400, () => row.classList.add("has-freed"));
    later(1700, () => row.classList.remove("is-fresh"));
    announce.textContent = "Parked 3 windows. 2.3 GB of memory freed.";
  }

  function restore() {
    if (!parked) return;
    parked = false;
    clearTimers();
    const hadFocus = document.activeElement === row;

    windows.forEach((win, i) => {
      win.style.transitionDelay = `${(windows.length - 1 - i) * 40}ms, 0ms`;
      win.classList.remove("is-parked");
    });
    rowWrap.classList.remove("is-open");
    row.classList.remove("is-fresh", "has-freed");
    row.tabIndex = -1;
    parkLabel.textContent = "Park this desktop";
    setPreview(false);
    count.textContent = "2";
    if (hadFocus) parkButton.focus({ preventScroll: true });
    setMemory(MEMORY_BEFORE);
    later(200, () => showToast("Restored “Onboarding redesign”"));
    announce.textContent = "Restored Onboarding redesign. 3 windows are back.";
  }

  parkButton.addEventListener("click", park);
  row.addEventListener("click", restore);
  // ↩ parks, like the real panel, when focus is in the panel and nothing else would take it.
  panel.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && event.target === panel) park();
  });

  meter.style.transform = `scaleX(${MEMORY_BEFORE / TOTAL})`;
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
  // Only swap once the icon has loaded, so a missing file never leaves a broken image.
  const probe = new Image();
  probe.onload = () => $$("[data-browser-icon]").forEach(img => { img.src = src; });
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
wireMagnetic();
