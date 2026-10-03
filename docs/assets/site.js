/* Cache — website.
 *
 * The first section is a sticky stage, and scrolling through it is a clock from 0 to 1
 * that plays the launch film: the notch peeks, grows into the panel, files a
 * screenshot, finds it by the words inside it, deletes a card and brings it back.
 * The notch, the springs and the cards are the app's own (Theme.swift, NotchShape.swift),
 * drawn in app points and scaled by --k.
 *
 * Phones, small windows and anyone who asked for reduced motion get the same story as a
 * plain stacked page with the film inline. No libraries.
 */
(() => {
  "use strict";

  const doc = document.documentElement;
  const REPO = "sagarmohansingh02-cloud/cache";
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const clamp = (v, a = 0, b = 1) => (v < a ? a : v > b ? b : v);
  const seg = (p, a, b) => clamp((p - a) / (b - a));
  const lerp = (a, b, t) => a + (b - a) * t;
  const out3 = (t) => 1 - Math.pow(1 - t, 3);
  const inOut3 = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
  const bump = (p, a, b) => Math.sin(Math.PI * seg(p, a, b)); // down and back up
  const env = (p, a, b, c, d) => Math.min(seg(p, a, b), 1 - seg(p, c, d)); // in over a–b, out over c–d

  // Only touch the DOM when a value actually changes.
  const set = (el, prop, v) => {
    if (!el) return;
    const s = el.__s || (el.__s = {});
    if (s[prop] !== v) { s[prop] = v; el.style[prop] = v; }
  };
  const setText = (el, v) => { if (el && el.__t !== v) { el.__t = v; el.textContent = v; } };

  // SwiftUI spring(response:dampingFraction:) as an easing curve — Theme.swift's motion.
  function spring(response, damping, dur) {
    const w0 = (2 * Math.PI) / response;
    const z = damping;
    return (t) => {
      if (t <= 0) return 0;
      if (t >= 1) return 1;
      const x = t * dur;
      if (z < 1) {
        const wd = w0 * Math.sqrt(1 - z * z);
        return 1 - Math.exp(-z * w0 * x) * (Math.cos(wd * x) + ((z * w0) / wd) * Math.sin(wd * x));
      }
      return 1 - Math.exp(-w0 * x) * (1 + w0 * x);
    };
  }
  const SPR = {
    open: spring(0.42, 0.8, 0.62), // the notch growing — the app's one flourish
    close: spring(0.3, 1, 0.45), // quicker than arriving, never bounces
    peek: spring(0.36, 0.72, 0.58),
    select: spring(0.3, 0.84, 0.42),
  };

  // ——————————————————————————————— NotchShape.swift ———————————————————————————————

  const S = {
    closed: { w: 197, h: 37, s: 6, b: 10 },
    peek: { w: 349, h: 37, s: 6, b: 14 },
    open: { w: 1000, h: 290, s: 14, b: 30 },
  };
  const mixS = (a, b, t) => ({ w: lerp(a.w, b.w, t), h: lerp(a.h, b.h, t), s: lerp(a.s, b.s, t), b: lerp(a.b, b.b, t) });

  function notchPath(W, { w, h, s, b }) {
    const x0 = (W - w) / 2;
    const x1 = x0 + w;
    const sh = Math.max(0, Math.min(s, w / 4, h / 2));
    const bo = Math.max(0, Math.min(b, (w - 2 * sh) / 2, h - sh));
    const r = (v) => Math.round(v * 100) / 100;
    return (
      `M ${r(x0)} 0 Q ${r(x0 + sh)} 0 ${r(x0 + sh)} ${r(sh)} L ${r(x0 + sh)} ${r(h - bo)} ` +
      `Q ${r(x0 + sh)} ${r(h)} ${r(x0 + sh + bo)} ${r(h)} L ${r(x1 - sh - bo)} ${r(h)} ` +
      `Q ${r(x1 - sh)} ${r(h)} ${r(x1 - sh)} ${r(h - bo)} L ${r(x1 - sh)} ${r(sh)} Q ${r(x1 - sh)} 0 ${r(x1)} 0 Z`
    );
  }

  // ——————————————————————————————— glyphs (SF Symbol-like) ———————————————————————————————

  const sv = (s, body) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" aria-hidden="true">${body}</svg>`;
  const STAR = `<path d="M12 3.2l2.6 5.5 6 .8-4.4 4.1 1.1 5.9L12 16.6l-5.3 2.9 1.1-5.9L3.4 9.5l6-.8z" stroke="#fff" stroke-width="2" stroke-linejoin="round"/>`;
  const G = {
    search: (c) => sv(16, `<circle cx="10.5" cy="10.5" r="7" stroke="${c}" stroke-width="2.6"/><path d="M15.8 15.8l5.7 5.7" stroke="${c}" stroke-width="2.8" stroke-linecap="round"/>`),
    star: (s) => sv(s, STAR),
    pause: sv(14, `<rect x="6" y="4.5" width="4" height="15" rx="1.2" fill="#fff"/><rect x="14" y="4.5" width="4" height="15" rx="1.2" fill="#fff"/>`),
    gear: sv(14.7, `<circle cx="12" cy="12" r="3.2" stroke="#fff" stroke-width="2"/><path d="M12 2.8v2.6M12 18.6v2.6M21.2 12h-2.6M5.4 12H2.8M18.5 5.5l-1.8 1.8M7.3 16.7l-1.8 1.8M18.5 18.5l-1.8-1.8M7.3 7.3L5.5 5.5" stroke="#fff" stroke-width="2.4" stroke-linecap="round"/><circle cx="12" cy="12" r="6.6" stroke="#fff" stroke-width="2"/>`),
    plus: sv(14.7, `<path d="M12 5v14M5 12h14" stroke="rgba(255,255,255,.92)" stroke-width="2.6" stroke-linecap="round"/>`),
    eye: sv(11.3, `<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z" stroke="#fff" stroke-width="2.2"/><circle cx="12" cy="12" r="3" fill="#fff"/>`),
    trash: (s, c = "#fff") => sv(s, `<path d="M4.5 6.6h15M9.6 6.6V4.9c0-.6.4-1 1-1h2.8c.6 0 1 .4 1 1v1.7M6.6 6.6l.9 12.4c.1.8.7 1.4 1.5 1.4h6c.8 0 1.4-.6 1.5-1.4l.9-12.4" stroke="${c}" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>`),
    link: sv(13.3, `<path d="M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1.2 1.2M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1.2-1.2" stroke="rgba(255,255,255,.38)" stroke-width="2.4" stroke-linecap="round"/>`),
    shot: (s) => sv(s, `<path d="M4 8V5.5A1.5 1.5 0 0 1 5.5 4H8M16 4h2.5A1.5 1.5 0 0 1 20 5.5V8M20 16v2.5a1.5 1.5 0 0 1-1.5 1.5H16M8 20H5.5A1.5 1.5 0 0 1 4 18.5V16" stroke="#fff" stroke-width="2.2" stroke-linecap="round"/><circle cx="12" cy="12" r="3.2" fill="#fff"/>`),
    x: sv(11, `<path d="M6 6l12 12M18 6L6 18" stroke="rgba(255,255,255,.62)" stroke-width="2.8" stroke-linecap="round"/>`),
  };
  // monochrome source-app tiles (the film's three-colour rule: no third-party icons)
  const s16 = (body) => sv(10.7, body);
  const SRC = {
    browser: s16(`<circle cx="12" cy="12" r="9" stroke="#fff" stroke-width="2.2"/><path d="M3 12h18M12 3c3 3.2 3 14.8 0 18M12 3c-3 3.2-3 14.8 0 18" stroke="#fff" stroke-width="1.8"/>`),
    notes: s16(`<path d="M5 6h14M5 11h14M5 16h9" stroke="#fff" stroke-width="2.4" stroke-linecap="round"/>`),
    shot: G.shot(10.7),
    code: s16(`<path d="M5 8l4 4-4 4M11 17h8" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>`),
    design: s16(`<circle cx="8" cy="8" r="3.5" stroke="#fff" stroke-width="2.2"/><rect x="12.5" y="12.5" width="7" height="7" rx="1.5" stroke="#fff" stroke-width="2.2"/>`),
    photo: s16(`<rect x="3.5" y="5" width="17" height="14" rx="2.5" stroke="#fff" stroke-width="2.2"/><path d="M6 17l4.5-5 3.5 3.5 2-2 3 3.5" stroke="#fff" stroke-width="2" stroke-linejoin="round"/>`),
    doc: s16(`<path d="M7 3.5h7l4 4V20a.5.5 0 0 1-.5.5h-10A.5.5 0 0 1 7 20z" stroke="#fff" stroke-width="2.2" stroke-linejoin="round"/>`),
  };

  // ——————————————————————————————— cards (ClipCardView) ———————————————————————————————

  const foot = (src, time, size = "", tint = "") =>
    `<div class="foot"${tint ? ` style="color:${tint}"` : ""}><span class="src">${SRC[src]}</span><span>${time}</span>${size ? `<span class="sz">${size}</span>` : ""}</div>`;
  const scrim = (s) => `<div class="scrim" style="background:linear-gradient(180deg,rgba(0,0,0,0) 50%,rgba(0,0,0,${s}) 100%)"></div>`;
  const picScrim = `<div class="scrim" style="background:linear-gradient(180deg,rgba(0,0,0,0) 45%,rgba(0,0,0,.28) 72%,rgba(0,0,0,.72) 100%)"></div>`;
  const swatch = (hex, time) => `<div class="fill" style="background:${hex}"></div>${scrim(0.35)}<div class="hex">${hex}</div>${foot("design", time)}`;
  const linkFace = (host, path, time) => `${scrim(0.78)}<div class="lnk">${G.link}</div><div class="host">${host}</div><div class="path">${path}</div>${foot("browser", time)}`;
  const textFace = (t, time, size) => `${scrim(0.78)}<div class="txt">${t}</div>${foot("notes", time, size)}`;
  const codeFace = (c, time, size) => `<div class="fill" style="background:var(--code)"></div>${scrim(0.78)}<div class="code">${c}</div>${foot("code", time, size)}`;

  const OCR_LINES = [
    { x: 30, y: 17, w: 262, h: 46 },
    { x: 30, y: 58, w: 214, h: 26 },
    { x: 30, y: 82, w: 346, h: 30, hit: true },
    { x: 30, y: 134, w: 420, h: 27 },
    { x: 30, y: 162, w: 420, h: 27 },
    { x: 30, y: 190, w: 420, h: 27 },
    { x: 30, y: 233, w: 420, h: 33 },
  ];
  function receipt(scale, boxes) {
    const items = [["Oat flat white", "4.50", 140], ["Almond croissant", "3.75", 168], ["Sparkling water", "2.00", 196]];
    return (
      `<div class="receipt" style="transform:scale(${scale})"><div class="rh">LUMA COFFEE</div><div class="rs">Studio Row · 2nd floor</div>` +
      `<div class="ro">Order #4471 · Thu 24 Sep 08:42</div><div class="rl" style="top:122px"></div>` +
      items.map(([a, b, y]) => `<div class="ri" style="top:${y}px"><span>${a}</span><span>${b}</span></div>`).join("") +
      `<div class="rl" style="top:224px"></div><div class="rt" style="top:240px"><span>TOTAL</span><span>10.25</span></div>` +
      (boxes ? OCR_LINES.map((l) => `<div class="ocr"${l.hit ? " data-hit" : ""} style="left:${l.x}px;top:${l.y}px;width:${l.w}px;height:${l.h}px"></div>`).join("") : "") +
      `</div>`
    );
  }

  const PHOTO =
    `<div class="fill" style="background:radial-gradient(60px 60px at 72% 30%,rgba(242,238,250,.95),rgba(242,238,250,0) 70%),linear-gradient(180deg,#5CB4FC 0%,#488DFB 38%,#AC76FB 62%,#743AF0 100%)"></div>` +
    `<svg class="fill" style="width:100%;height:100%" viewBox="0 0 306 230" preserveAspectRatio="none" aria-hidden="true"><path d="M0 170 L60 120 L110 150 L170 95 L230 140 L306 110 L306 230 L0 230 Z" fill="#3858F4"/><path d="M0 200 L80 160 L150 185 L220 150 L306 175 L306 230 L0 230 Z" fill="#1E1360"/></svg>`;
  const DESIGN =
    `<div class="fill" style="background:#F2EEFA"></div>` +
    `<div class="fill" style="left:13px;top:13px;right:13px;bottom:auto;height:20px;border-radius:5px;background:#fff"></div>` +
    `<div class="fill" style="left:13px;top:41px;width:80px;right:auto;bottom:auto;height:73px;border-radius:8px;background:linear-gradient(135deg,#5CB4FC,#743AF0)"></div>` +
    `<div class="fill" style="left:101px;top:41px;right:13px;bottom:auto;height:9px;border-radius:5px;background:#1E1360"></div>` +
    `<div class="fill" style="left:101px;top:57px;right:32px;bottom:auto;height:7px;border-radius:4px;background:#AC76FB"></div>` +
    `<div class="fill" style="left:101px;top:69px;right:47px;bottom:auto;height:7px;border-radius:4px;background:#AC76FB"></div>` +
    `<div class="fill" style="left:101px;top:91px;width:56px;right:auto;bottom:auto;height:20px;border-radius:10px;background:#3858F4"></div>`;
  const PDF = `<svg width="44" height="44" viewBox="0 0 66 66" aria-hidden="true"><path d="M16 6h24l14 14v38a3 3 0 0 1-3 3H16a3 3 0 0 1-3-3V9a3 3 0 0 1 3-3z" fill="#F2EEFA"/><path d="M40 6v11a3 3 0 0 0 3 3h11" fill="#AC76FB"/><rect x="21" y="34" width="24" height="3.5" rx="1.75" fill="#5233E5"/><rect x="21" y="42" width="18" height="3.5" rx="1.75" fill="#5233E5"/></svg>`;

  const C = {
    receipt: () => `<div class="fill" style="background:#fff">${receipt(0.425, true)}</div>${picScrim}${foot("shot", "2 min ago", "412 KB", "rgba(255,255,255,.85)")}`,
    violet: () => swatch("#743AF0", "5 min ago"),
    sky: () => swatch("#5CB4FC", "1 hr ago"),
    royal: () => swatch("#3858F4", "2 hr ago"),
    lilac: () => swatch("#AC76FB", "Yesterday"),
    indigo: () => swatch("#5233E5", "Yesterday"),
    wiki: () => linkFace("wikipedia.org", "/wiki/Clipboard_(computing)", "12 min ago"),
    repo: () => linkFace("github.com", "/sagarmohansingh02-cloud/cache", "1 hr ago"),
    docs: () => linkFace("developer.mozilla.org", "/docs/Web/API/Clipboard", "3 hr ago"),
    meet: () => textFace("Meet at 4 — Luma Coffee, 2nd floor. Bring the prototype.", "18 min ago", "58 bytes"),
    quote: () => textFace("The notch is the one place on screen nothing else uses.", "2 hr ago", "56 bytes"),
    code1: () => codeFace("const recent = clips\n  .filter(c =&gt; c.starred)\n  .slice(0, 9)", "24 min ago", "1 KB"),
    code2: () => codeFace("git tag v2.1.0\ngit push --tags", "40 min ago", "31 bytes"),
    code3: () => codeFace("xattr -dr com.apple.\n  quarantine Cache.app", "3 hr ago", "44 bytes"),
    photo: () => `${PHOTO}${picScrim}${foot("photo", "31 min ago", "2.4 MB")}`,
    design: () => `${DESIGN}${picScrim}${foot("shot", "52 min ago", "688 KB")}`,
    pdf: () => `${scrim(0.78)}<div class="ficon">${PDF}</div><div class="fname">Q3-roadmap.pdf</div>${foot("doc", "44 min ago", "1.8 MB")}`,
  };

  const card = (id, face, i, hover) =>
    `<div class="slot" data-card="${id}" style="left:${i * 216}px"><div class="card">${face}<div class="edge"></div><div class="sel"></div></div>` +
    (hover ? `<div class="corner"><div class="cbtn">${G.eye}</div><div class="cbtn">${G.star(11.3)}</div></div><div class="cbtn trash">${G.trash(11.3)}</div>` : "") +
    `</div>`;
  const track = (name, list, hoverId) =>
    `<div class="p-track" data-track="${name}">${list.map(([id, face], i) => card(id, face, i, id === hoverId)).join("")}</div>`;

  const CHIPS = [["all", "History", "128"], ["shots", "Screenshots", "24"], ["image", "Images", "41"], ["link", "Links", "31"], ["color", "Colors", "12"], ["text", "Text", "29"], ["code", "Code", "9"], ["file", "Files", "6"]];

  function panelHTML() {
    const chips = CHIPS.map(([k, t, n]) => `<div class="p-chip" data-chip="${k}"><span class="l"><b>${t}</b><i>${n}</i></span><span class="l dk"><b>${t}</b><i>${n}</i></span></div>`).join("");
    return (
      `<div class="p-top"><div class="p-search"><span class="p-mag">${G.search("rgba(255,255,255,.62)")}<span class="p-magw">${G.search("#fff")}</span></span>` +
      `<span class="p-ph">Search</span><span class="p-q"><span class="p-qt"></span><i class="p-caret"></i></span></div>` +
      `<div class="p-buttons"><div class="p-round">${G.star(14)}</div><div class="p-round">${G.pause}</div><div class="p-round">${G.gear}</div></div></div>` +
      `<div class="p-undo">Deleted<b>Undo</b></div>` +
      `<div class="p-chips"><div class="p-pill"></div>${chips}<div class="p-plus">${G.plus}</div></div>` +
      `<div class="p-strip">` +
      track("history", [["h-repo", C.repo()], ["h-code", C.code1()], ["h-violet", C.violet()], ["h-meet", C.meet()], ["h-wiki", C.wiki()], ["h-photo", C.photo()], ["h-design", C.design()], ["h-pdf", C.pdf()], ["h-sky", C.sky()], ["h-quote", C.quote()]]) +
      track("link", [["l-repo", C.repo()], ["l-wiki", C.wiki()], ["l-docs", C.docs()]]) +
      track("color", [["c-violet", C.violet()], ["c-sky", C.sky()], ["c-royal", C.royal()], ["c-lilac", C.lilac()], ["c-indigo", C.indigo()]]) +
      track("code", [["k-code1", C.code1()], ["k-code2", C.code2()], ["k-code3", C.code3()]]) +
      track("recent", [["r-receipt", C.receipt()], ["r-repo", C.repo()], ["r-code", C.code1()], ["r-violet", C.violet()], ["r-meet", C.meet()], ["r-wiki", C.wiki()], ["r-photo", C.photo()], ["r-design", C.design()], ["r-pdf", C.pdf()], ["r-sky", C.sky()]], "r-code") +
      `</div>`
    );
  }

  function previewHTML() {
    return (
      `<div class="preview" id="preview"><div class="pv-head"><div class="pv-icon">${G.shot(15)}</div>` +
      `<div><div class="pv-title">Screenshot</div><div class="pv-meta">1512 × 982 · 412 KB · Screenshot · 2 min ago</div></div><div class="pv-sp"></div>` +
      `<div class="pv-round" style="margin-right:6px">${G.trash(12, "rgba(255,255,255,.62)")}</div><div class="pv-btn">Copy Text</div><div class="pv-btn">Show in Finder</div><div class="pv-btn pri">Copy</div><div class="pv-round">${G.x}</div></div>` +
      `<div class="pv-body"><div class="pv-pic"><div class="pv-shot">${receipt(444 / 480, true)}</div></div>` +
      `<div class="pv-text"><p class="eyebrow">Text in image</p><p>LUMA COFFEE\nStudio Row · 2nd floor\nOrder #<mark>4471</mark> · Thu 24 Sep 08:42\nOat flat white        4.50\nAlmond croissant      3.75\nSparkling water       2.00\nTOTAL                10.25</p></div></div></div>`
    );
  }

  const TEXT_GLYPH = sv(12, `<path d="M5 6h14M5 11h14M5 16h9" stroke="#fff" stroke-width="2.6" stroke-linecap="round"/>`);
  const POINTER = `<svg class="nt-pointer" id="pointer" viewBox="0 0 18 27" width="18" height="27" aria-hidden="true"><path d="M1.5 1.5 L1.5 21 L6.3 16.6 L9.6 24.4 L13 23 L9.7 15.3 L16 15.3 Z" fill="#000" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>`;

  // ——————————————————————————————— build ———————————————————————————————

  const bar = $("#bar");
  const notch = $("#notch");
  const story = $("#top");
  const screen = $("#screen");
  const scene = $("#scene");
  const flash = $("#flash");
  const flood = $("#flood");

  notch.innerHTML =
    `<div class="nt-mask" id="nt-mask"><div class="nt-peek">` +
    `<div class="nt-glimpse" data-g="violet"><div style="background:#743AF0"></div></div>` +
    `<div class="nt-glimpse" data-g="text"><div style="background:#303030;display:flex;align-items:center;justify-content:center">${TEXT_GLYPH}</div></div>` +
    `<div class="nt-glimpse" data-g="receipt"><div style="background:#fff">${receipt(22 / 480, false)}</div></div>` +
    `<div class="nt-glimpse" data-g="app"><img src="assets/icon-256.png" alt="" style="width:100%;height:100%"></div>` +
    `<div class="nt-label" data-l="Copied">Copied</div><div class="nt-label" data-l="Saved">Saved</div></div>` +
    `<div class="nt-panel" id="nt-panel">${panelHTML()}</div><div class="nt-lens"></div></div>` +
    previewHTML() +
    POINTER;

  scene.innerHTML =
    `<div class="clipslot" id="clipslot"><div class="ring"></div>${card("cs-a", C.violet(), 0)}${card("cs-b", C.code1(), 0)}</div>` +
    `<div class="keys" id="keys-copy"><span class="key">⌘</span><span class="key">C</span></div>` +
    `<div class="keys" id="keys-shot"><span class="key">⇧</span><span class="key">⌘</span><span class="key">4</span></div>` +
    `<div class="keys" id="keys-open"><span class="key">⌃</span><span class="key">⌘</span><span class="key">V</span></div>`;

  const mask = $("#nt-mask");
  const panel = $("#nt-panel");
  const preview = $("#preview");
  const pointer = $("#pointer");
  const glimpses = $$(".nt-glimpse", notch);
  const peekLabels = $$(".nt-label", notch);
  const pill = $(".p-pill", panel);
  const chips = $$(".p-chip", panel).map((el) => ({ el, w: $(".l:not(.dk)", el), k: $(".l.dk", el) }));
  const tracks = $$(".p-track", panel).map((el) => ({ el, name: el.dataset.track, cards: $$(".slot", el) }));
  const T = Object.fromEntries(tracks.map((t) => [t.name, t]));
  const ph = $(".p-ph", panel);
  const qt = $(".p-qt", panel);
  const caret = $(".p-caret", panel);
  const magW = $(".p-magw", panel);
  const undo = $(".p-undo", panel);
  const undoBtn = $("b", undo);
  const victim = $('[data-card="r-code"]', panel);
  const victimParts = { edge: $(".edge", victim), corner: $(".corner", victim), trash: $(".trash", victim) };
  const receiptSel = $('[data-card="r-receipt"] .sel', panel);
  const ocrBoxes = $$(".ocr", preview).concat($$('[data-card="r-receipt"] .ocr', panel));
  const ocrHits = ocrBoxes.filter((b) => b.hasAttribute("data-hit"));
  const pvBoxes = $$(".ocr", preview);
  const cardBoxes = $$('[data-card="r-receipt"] .ocr', panel);
  const mark = $("mark", preview);
  const clipslot = $("#clipslot");
  const csA = $('[data-card="cs-a"]', clipslot);
  const csB = $('[data-card="cs-b"]', clipslot);
  const keys = { copy: $("#keys-copy"), shot: $("#keys-shot"), open: $("#keys-open") };

  // the captions: each beat's words arrive one at a time, scrubbed
  const beats = {};
  $$(".beat[data-beat]").forEach((el) => {
    const heads = $$(".h1, .h2, .display", el);
    heads.forEach((h) => {
      const lines = $$(".line-a, .line-b", h);
      (lines.length ? lines : [h]).forEach((host) => {
        host.innerHTML = host.textContent
          .split(" ")
          .map((w, i, a) => `<span class="w">${w}${i < a.length - 1 ? " " : ""}</span>`)
          .join("");
      });
    });
    beats[el.dataset.beat] = {
      el,
      words: $$(".w", el),
      a: $$(".line-a .w", el),
      b: $$(".line-b .w", el),
      lineA: $(".line-a", el),
      lineB: $(".line-b", el),
      y: 0,
    };
  });

  // ——————————————————————————————— layout ———————————————————————————————

  const mqBig = matchMedia("(min-width: 1024px) and (min-height: 560px)");
  const mqCalm = matchMedia("(prefers-reduced-motion: reduce)");
  let timeline = doc.classList.contains("is-timeline");
  let vw = innerWidth;
  let vh = innerHeight;
  let k = 1;
  let pk = 1; // the preview's own scale, so the caption still fits beneath it
  let storyTop = 0;
  let storyLen = 1;
  let chipRects = [];
  let undoAt = { x: 828, y: 24 };

  function measure() {
    vw = innerWidth;
    vh = innerHeight;
    k = timeline ? clamp((vw * 0.62) / 1000, 0.72, 1.25) : clamp(vw / 500, 0.72, 0.86);
    doc.style.setProperty("--k", k.toFixed(4));
    doc.style.setProperty("--bar", timeline ? `${(37 * k).toFixed(2)}px` : "44px");

    storyTop = story.getBoundingClientRect().top + scrollY;
    storyLen = Math.max(1, story.offsetHeight - vh);

    chipRects = chips.map((c) => ({ x: c.el.offsetLeft, w: c.el.offsetWidth }));
    const box = { x: undo.offsetLeft + undoBtn.offsetLeft + undoBtn.offsetWidth / 2, y: undo.offsetTop + undoBtn.offsetTop + undoBtn.offsetHeight / 2 };
    undoAt = { x: 20 + box.x, y: box.y };

    if (!timeline) return;
    pk = clamp((vh - 190 - 300 * k) / (440 * k), 0.55, 1);
    const panelBottom = 290 * k;
    const belowPanel = panelBottom + (vh - panelBottom) * 0.5;
    const pvBottom = (300 + 440 * pk) * k;
    const belowPreview = pvBottom + (vh - pvBottom) * 0.5;
    const Y = { hero: vh * 0.5, problem: vh * 0.25, kept: vh * 0.5, notch: belowPanel, kinds: belowPanel, shot: vh * 0.44, search: belowPreview, delete: belowPanel, private: vh * 0.5 };
    Object.entries(beats).forEach(([name, b]) => { b.y = Y[name] || vh * 0.5; set(b.el, "top", `${Math.round(b.y)}px`); });

    const ks = clamp(k * 1.05, 0.8, 1.15);
    set(clipslot, "top", `${Math.round(vh * 0.4)}px`);
    set(clipslot, "transform", `scale(${(k * 1.3).toFixed(3)})`);
    set(keys.copy, "top", `${Math.round(vh * 0.74)}px`);
    set(keys.shot, "top", `${Math.round(vh * 0.62)}px`);
    set(keys.open, "top", `${Math.round(vh * 0.62)}px`);
    Object.values(keys).forEach((el) => { set(el, "transform", `scale(${ks.toFixed(3)})`); el.style.transformOrigin = "50% 0"; });
  }

  // Clear everything the timeline wrote, so the stacked page lays out cleanly.
  function resetInline() {
    const els = [...Object.values(beats).flatMap((b) => [b.el, b.lineA, b.lineB, ...b.words]), screen, flash, flood, clipslot, csA, csB, ...Object.values(keys), preview, pointer, panel];
    els.forEach((el) => { if (el) { el.removeAttribute("style"); el.__s = null; } });
    bar.classList.remove("is-glass");
  }

  // ——————————————————————————————— the notch ———————————————————————————————

  let pulse = null; // a peek that runs on the clock: a copy on the page, or the hero idling
  function firePulse(kind, label) {
    pulse = { t0: performance.now(), kind, label };
    kick();
  }
  function pulseAmount(now) {
    if (!pulse) return 0;
    const t = (now - pulse.t0) / 1000;
    if (t > 2.45) { pulse = null; return 0; }
    const up = SPR.peek(clamp(t / 0.58));
    const down = t > 1.9 ? SPR.close(clamp((t - 1.9) / 0.45)) : 0;
    return up * (1 - down);
  }

  function storyNotch(p) {
    let st = S.closed;
    let kind = "violet";
    let label = "Copied";
    if (p >= 0.245) st = mixS(S.closed, S.peek, SPR.peek(seg(p, 0.245, 0.275)));
    if (p >= 0.3) st = mixS(S.peek, S.open, SPR.open(seg(p, 0.3, 0.335)));
    if (p >= 0.52) st = mixS(S.open, S.closed, SPR.close(seg(p, 0.52, 0.545)));
    if (p >= 0.578) { st = mixS(S.closed, S.peek, SPR.peek(seg(p, 0.578, 0.605))); kind = "receipt"; label = "Saved"; }
    if (p >= 0.625) st = mixS(S.peek, S.closed, SPR.close(seg(p, 0.625, 0.645)));
    if (p >= 0.665) st = mixS(S.closed, S.open, SPR.open(seg(p, 0.665, 0.7)));
    if (p >= 0.94) st = mixS(S.open, S.closed, SPR.close(seg(p, 0.94, 0.96)));
    return { st, kind, label };
  }

  function renderNotch(p, now) {
    let { st, kind, label } = timeline ? storyNotch(p) : { st: S.closed, kind: "violet", label: "Copied" };
    const a = pulseAmount(now);
    const closed = Math.abs(st.w - S.closed.w) < 0.5 && Math.abs(st.h - S.closed.h) < 0.5;
    if (a > 0 && closed && pulse) { st = mixS(S.closed, S.peek, a); kind = pulse.kind; label = pulse.label; }

    set(mask, "clipPath", `path("${notchPath(1040, st)}")`);
    const open = clamp((st.h - 37) / 253);
    const peekness = clamp((st.w - S.closed.w) / (S.peek.w - S.closed.w)) * (1 - clamp(open * 4));
    const g = clamp((peekness - 0.55) / 0.35).toFixed(3);
    glimpses.forEach((el) => set(el, "opacity", el.dataset.g === kind ? g : "0"));
    peekLabels.forEach((el) => set(el, "opacity", el.dataset.l === label ? g : "0"));
    set(panel, "opacity", clamp((open - 0.3) / 0.55).toFixed(3));
    set(panel, "transform", `scale(${(0.96 + 0.04 * clamp(open)).toFixed(4)})`);
    // the panel covers the middle of the menu bar, as it does on a Mac: the menus under it step aside
    bar.classList.toggle("is-covered", open > 0.08);
  }

  // ——————————————————————————————— the story ———————————————————————————————

  function caption(b, vis, dy, reveal) {
    set(b.el, "opacity", vis.toFixed(3));
    set(b.el, "transform", `translate3d(0, calc(-50% + ${dy.toFixed(1)}px), 0)`);
    b.el.classList.toggle("is-live", vis > 0.5);
    if (reveal !== undefined) words(b.words, reveal);
  }
  function words(list, t) {
    const n = list.length;
    list.forEach((w, i) => {
      const start = (i / n) * 0.6;
      const e = out3(clamp((t - start) / 0.4));
      set(w, "opacity", e.toFixed(3));
      set(w, "transform", `translate3d(0, ${((1 - e) * 22).toFixed(1)}px, 0)`);
    });
  }
  const at = (a, b, t) => ({ x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t) });

  function renderStory(p, now) {
    // the menu bar turns to glass over the desktop; the desktop rises under the bezel
    bar.classList.toggle("is-glass", p > 0.215 && p < 0.955);
    set(screen, "transform", `translate3d(0, ${((1 - inOut3(seg(p, 0.19, 0.25))) * 100).toFixed(3)}%, 0)`);

    // hero
    const heroOut = seg(p, 0.012, 0.05);
    caption(beats.hero, 1 - heroOut, -heroOut * 70);

    // one clipboard, two copies
    const pr = beats.problem;
    const aVis = seg(p, 0.05, 0.075) * (1 - seg(p, 0.122, 0.135));
    const bVis = seg(p, 0.135, 0.158) * (1 - seg(p, 0.178, 0.195));
    set(pr.el, "opacity", aVis > 0 || bVis > 0 ? "1" : "0");
    set(pr.el, "transform", "translate3d(0, -50%, 0)");
    set(pr.lineA, "opacity", (1 - seg(p, 0.122, 0.135)).toFixed(3));
    set(pr.lineB, "opacity", (1 - seg(p, 0.178, 0.195)).toFixed(3));
    words(pr.a, seg(p, 0.05, 0.075));
    words(pr.b, seg(p, 0.135, 0.158));

    set(clipslot, "opacity", env(p, 0.06, 0.08, 0.175, 0.195).toFixed(3));
    const drop = seg(p, 0.128, 0.142);
    set(csA, "opacity", (seg(p, 0.095, 0.11) * (1 - drop)).toFixed(3));
    set(csA, "transform", `translate3d(0, ${(drop * 40).toFixed(1)}px, 0) scale(${(1 - drop * 0.06).toFixed(3)})`);
    const bIn = out3(seg(p, 0.135, 0.15));
    set(csB, "opacity", bIn.toFixed(3));
    set(csB, "transform", `translate3d(0, ${((1 - bIn) * -24).toFixed(1)}px, 0)`);

    const press = (el, d) => $$(".key", el).forEach((key) => set(key, "transform", `translate3d(0, ${(d * 5).toFixed(2)}px, 0) scale(${(1 - d * 0.03).toFixed(3)})`));
    set(keys.copy, "opacity", env(p, 0.06, 0.078, 0.17, 0.19).toFixed(3));
    press(keys.copy, Math.max(bump(p, 0.09, 0.104), bump(p, 0.125, 0.139)));
    set(keys.shot, "opacity", env(p, 0.535, 0.55, 0.6, 0.615).toFixed(3));
    press(keys.shot, bump(p, 0.558, 0.57));
    set(keys.open, "opacity", env(p, 0.635, 0.648, 0.688, 0.7).toFixed(3));
    press(keys.open, bump(p, 0.652, 0.664));

    // captions on the desktop
    caption(beats.kept, env(p, 0.24, 0.26, 0.288, 0.302), (1 - out3(seg(p, 0.24, 0.26))) * 20, seg(p, 0.24, 0.265));
    caption(beats.notch, env(p, 0.315, 0.335, 0.384, 0.398), (1 - out3(seg(p, 0.315, 0.335))) * 20, seg(p, 0.315, 0.34));
    caption(beats.kinds, env(p, 0.398, 0.418, 0.5, 0.515), (1 - out3(seg(p, 0.398, 0.418))) * 20, seg(p, 0.398, 0.423));
    caption(beats.shot, env(p, 0.56, 0.58, 0.622, 0.636), (1 - out3(seg(p, 0.56, 0.58))) * 20, seg(p, 0.56, 0.585));
    caption(beats.search, env(p, 0.7, 0.72, 0.8, 0.815), (1 - out3(seg(p, 0.7, 0.72))) * 20, seg(p, 0.7, 0.725));
    caption(beats.delete, env(p, 0.835, 0.855, 0.928, 0.942), (1 - out3(seg(p, 0.835, 0.855))) * 20, seg(p, 0.835, 0.86));
    caption(beats.private, seg(p, 0.972, 0.99), (1 - out3(seg(p, 0.972, 0.99))) * 20, seg(p, 0.972, 0.995));

    // the shutter
    set(flash, "opacity", (Math.min(seg(p, 0.568, 0.573), 1 - seg(p, 0.573, 0.592)) * 0.85).toFixed(3));

    // the notch's black floods the screen
    const f = inOut3(seg(p, 0.955, 0.985));
    const w0 = 185 * k;
    const side = ((vw - w0) / 2) * (1 - f);
    const bottom = (vh - 37 * k) * (1 - f);
    const r = 10 * k * (1 - f);
    set(flood, "clipPath", f <= 0 ? "inset(0 50% 100% 50%)" : `inset(0 ${side.toFixed(1)}px ${bottom.toFixed(1)}px ${side.toFixed(1)}px round 0 0 ${r.toFixed(1)}px ${r.toFixed(1)}px)`);

    renderPanel(p, now);
  }

  function renderPanel(p, now) {
    // the chip tour: History → Links → Colors → Code, the white pill sliding on the select spring
    const late = p >= 0.55;
    let from = 0;
    let to = 0;
    let e = 0;
    if (!late) {
      if (p >= 0.475) { from = 4; to = 6; e = SPR.select(seg(p, 0.475, 0.495)); }
      else if (p >= 0.445) { from = 3; to = 4; e = SPR.select(seg(p, 0.445, 0.465)); }
      else { from = 0; to = 3; e = SPR.select(seg(p, 0.415, 0.435)); }
    }
    const a = chipRects[from];
    const b = chipRects[to];
    if (a && b) {
      set(pill, "left", `${lerp(a.x, b.x, e).toFixed(2)}px`);
      set(pill, "width", `${lerp(a.w, b.w, e).toFixed(2)}px`);
    }
    const ce = clamp(e);
    chips.forEach((c, i) => {
      const on = from === to ? (i === from ? 1 : 0) : i === to ? ce : i === from ? 1 - ce : 0;
      set(c.k, "opacity", on.toFixed(3));
      set(c.w, "opacity", (1 - on).toFixed(3));
    });

    const trackFor = { 0: "history", 3: "link", 4: "color", 6: "code" };
    const vis = { history: 0, link: 0, color: 0, code: 0, recent: 0 };
    if (late) vis.recent = 1;
    else { vis[trackFor[from]] += from === to ? 1 : 1 - ce; if (from !== to) vis[trackFor[to]] += ce; }
    const drift = -54 * out3(seg(p, 0.335, 0.4));
    tracks.forEach((t) => {
      const v = vis[t.name];
      set(t.el, "opacity", v.toFixed(3));
      set(t.el, "transform", `translate3d(${(t.name === "history" ? drift : (1 - v) * 14).toFixed(1)}px, 0, 0)`);
    });

    // ⌃⌘V, then "4471" — typed, and later taken back
    let n = 0;
    [0.705, 0.712, 0.719, 0.726].forEach((th) => { if (p >= th) n += 1; });
    [0.812, 0.816, 0.82, 0.824].forEach((th) => { if (p >= th) n -= 1; });
    n = clamp(n, 0, 4);
    setText(qt, "4471".slice(0, n));
    const focused = p >= 0.69 && p < 0.835;
    set(ph, "opacity", n > 0 ? "0" : "1");
    set(magW, "opacity", focused ? "1" : "0");
    set(caret, "opacity", focused && Math.floor(now / 530) % 2 === 0 ? "1" : "0");

    // only the receipt matches
    const filtered = seg(p, 0.728, 0.74) * (1 - seg(p, 0.824, 0.836));
    const removed = SPR.select(seg(p, 0.87, 0.886)) * (1 - SPR.select(seg(p, 0.908, 0.924)));
    const hover = seg(p, 0.848, 0.853) * (1 - seg(p, 0.868, 0.872));
    T.recent.cards.forEach((c, i) => {
      if (i === 0) return;
      let o = 1 - filtered;
      let x = 0;
      let s = 1;
      if (i === 2) { o *= clamp(1 - removed * 1.4); s = (1 + 0.02 * hover) * (1 - 0.06 * clamp(removed)); }
      if (i > 2) x = -216 * removed;
      set(c, "opacity", o.toFixed(3));
      set(c, "transform", `translate3d(${x.toFixed(1)}px, 0, 0) scale(${s.toFixed(4)})`);
    });
    set(receiptSel, "opacity", (seg(p, 0.742, 0.75) * (1 - seg(p, 0.8, 0.808))).toFixed(3));

    // hover a card: eye and star top right, the trash top left — red under the pointer
    set(victimParts.corner, "opacity", hover.toFixed(3));
    set(victimParts.trash, "opacity", hover.toFixed(3));
    set(victimParts.edge, "boxShadow", `inset 0 0 0 1px rgba(255,255,255,${(0.12 + 0.18 * hover).toFixed(3)})`);
    victimParts.trash.classList.toggle("is-warn", p >= 0.861 && p < 0.872);

    // Deleted · Undo
    const u = seg(p, 0.876, 0.888) * (1 - seg(p, 0.906, 0.916));
    set(undo, "opacity", u.toFixed(3));
    set(undo, "transform", `scale(${(0.94 + 0.06 * u).toFixed(4)})`);
    set(undoBtn, "transform", `scale(${(1 - 0.05 * bump(p, 0.902, 0.908)).toFixed(4)})`);

    // the pointer
    const P0 = { x: 660, y: 430 };
    const P1 = { x: 588, y: 195.5 }; // the card
    const P2 = { x: 506, y: 139 }; // its trash
    const P3 = undoAt;
    const P4 = { x: 760, y: 440 };
    let q = at(P0, P1, inOut3(seg(p, 0.836, 0.85)));
    if (p >= 0.855) q = at(P1, P2, inOut3(seg(p, 0.855, 0.864)));
    if (p >= 0.889) q = at(P2, P3, inOut3(seg(p, 0.889, 0.902)));
    if (p >= 0.918) q = at(P3, P4, inOut3(seg(p, 0.918, 0.94)));
    const click = Math.max(bump(p, 0.865, 0.869), bump(p, 0.903, 0.907));
    set(pointer, "opacity", (seg(p, 0.835, 0.842) * (1 - seg(p, 0.93, 0.94))).toFixed(3));
    set(pointer, "transform", `translate3d(${(q.x - 1.5).toFixed(1)}px, ${(q.y - 1.5).toFixed(1)}px, 0) scale(${(1 - 0.12 * click).toFixed(3)})`);

    // Space: the preview, with the words Cache read
    const pvIn = out3(seg(p, 0.745, 0.765));
    const pvOut = seg(p, 0.8, 0.815);
    set(preview, "opacity", (pvIn * (1 - pvOut)).toFixed(3));
    set(preview, "transform", `translate3d(0, ${((1 - pvIn) * -8).toFixed(1)}px, 0) scale(${(pk * (0.97 + 0.03 * pvIn)).toFixed(4)})`);
    pvBoxes.forEach((box, i) => set(box, "opacity", seg(p, 0.765 + i * 0.004, 0.772 + i * 0.004).toFixed(3)));
    cardBoxes.forEach((box, i) => set(box, "opacity", (seg(p, 0.765 + i * 0.004, 0.772 + i * 0.004) * (1 - seg(p, 0.8, 0.81))).toFixed(3)));
    const hit = p >= 0.79 && p < 0.815;
    ocrHits.forEach((box) => box.classList.toggle("hit", hit));
    set(mark, "background", hit ? "rgba(172,118,251,.45)" : "transparent");
  }

  // ——————————————————————————————— the clock ———————————————————————————————

  let pNow = 0;
  let running = false;
  function kick() {
    if (!running) { running = true; requestAnimationFrame(tick); }
  }
  function tick(now) {
    running = false;
    let busy = !!pulse;
    if (timeline) {
      const target = clamp((scrollY - storyTop) / storyLen);
      const d = target - pNow;
      // a long jump (a menu link, a reload halfway down) lands at once instead of
      // racing through every beat on the way
      if (Math.abs(d) > 0.06) pNow = target;
      else if (Math.abs(d) > 0.00004) { pNow += d * 0.2; busy = true; } else pNow = target;
      renderStory(pNow, now);
      renderNotch(pNow, now);
      if (pNow > 0.69 && pNow < 0.835) busy = true; // the caret blinks
    } else {
      renderNotch(0, now);
    }
    if (busy) kick();
  }

  function decide() {
    const t = mqBig.matches && !mqCalm.matches;
    if (t !== timeline) {
      timeline = t;
      doc.classList.toggle("is-timeline", t);
      resetInline();
      if (!t) [mask, panel].forEach((el) => { el.__s = null; });
    }
    measure();
    kick();
  }
  mqBig.addEventListener ? mqBig.addEventListener("change", decide) : mqBig.addListener(decide);
  mqCalm.addEventListener ? mqCalm.addEventListener("change", decide) : mqCalm.addListener(decide);
  addEventListener("scroll", kick, { passive: true });
  addEventListener("resize", () => { measure(); kick(); });
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(() => { measure(); kick(); });
  addEventListener("load", () => { measure(); kick(); });

  measure();
  kick();

  // the hero idles the way the app does: a copy, a peek, back to black
  const idle = ["violet", "text", "receipt"];
  let idleIndex = 0;
  function idlePeek() {
    if (mqCalm.matches || document.hidden || pulse) return;
    const atTop = timeline ? pNow < 0.012 : scrollY < vh * 0.5;
    if (!atTop) return;
    const kind = idle[idleIndex++ % idle.length];
    firePulse(kind, kind === "receipt" ? "Saved" : "Copied");
  }
  setTimeout(idlePeek, 1300);
  setInterval(idlePeek, 5200);

  // copy anything on the page and the notch confirms it, like Cache would
  document.addEventListener("copy", () => firePulse("text", "Copied"));
  $$("[data-download]").forEach((a) => a.addEventListener("click", () => firePulse("app", "Saved")));

  // ——————————————————————————————— the rest of the page ———————————————————————————————

  // fade sections up as they arrive
  const reveals = $$(".reveal");
  reveals.forEach((el) => {
    const sibs = Array.from(el.parentElement.children).filter((c) => c.classList.contains("reveal"));
    el.style.transitionDelay = `${Math.min(sibs.indexOf(el), 6) * 70}ms`;
  });
  if ("IntersectionObserver" in window) {
    const ro = new IntersectionObserver((entries) => entries.forEach((en) => {
      if (en.isIntersecting) { en.target.classList.add("is-in"); ro.unobserve(en.target); }
    }), { rootMargin: "0px 0px -8% 0px", threshold: 0.12 });
    reveals.forEach((el) => ro.observe(el));

    // "No account. No sync. No network requests." light up one at a time
    const lo = new IntersectionObserver((entries) => entries.forEach((en) => {
      if (en.isIntersecting) en.target.classList.add("is-lit");
    }), { rootMargin: "-36% 0px -36% 0px" });
    $$(".stack span").forEach((s) => (mqCalm.matches ? s.classList.add("is-lit") : lo.observe(s)));

    // the film on the stacked page plays itself, muted, while it's on screen
    const inline = $(".film-inline video");
    if (inline && !mqCalm.matches) {
      new IntersectionObserver(([en]) => {
        if (doc.classList.contains("is-timeline")) return;
        if (en.isIntersecting) inline.play().catch(() => {});
        else inline.pause();
      }, { threshold: 0.4 }).observe(inline);
    }
  } else {
    reveals.forEach((el) => el.classList.add("is-in"));
    $$(".stack span").forEach((s) => s.classList.add("is-lit"));
  }

  // the film
  const dialog = $("#film");
  const film = dialog && $("video", dialog);
  $$("[data-film]").forEach((b) => b.addEventListener("click", () => {
    if (!dialog || typeof dialog.showModal !== "function") { window.open(film.src, "_blank"); return; }
    dialog.showModal();
    film.currentTime = 0;
    film.play().catch(() => {});
  }));
  if (dialog) {
    dialog.addEventListener("close", () => film.pause());
    dialog.addEventListener("click", (e) => { if (e.target === dialog) dialog.close(); });
    $("[data-film-close]", dialog).addEventListener("click", () => dialog.close());
  }

  // the details: little pieces of the app, drawn from the same parts
  const art = {
    colour: () =>
      `<div style="display:flex;flex-wrap:wrap;align-items:center;justify-content:center;gap:28px;padding:28px">` +
      `<div style="position:relative;width:204px;height:153px;transform:scale(1.15)">${card("a-sky", C.sky(), 0)}</div>` +
      `<div class="notation"><div><b>HEX</b><span>#5CB4FC</span></div><div><b>RGB</b><span>rgb(92, 180, 252)</span></div><div><b>HSL</b><span>hsl(207, 96%, 67%)</span></div><div><b>CMYK</b><span>cmyk(63%, 29%, 0%, 1%)</span></div></div></div>`,
    peek: () =>
      `<div style="position:relative;width:300px;height:150px;border-radius:18px;overflow:hidden"><div class="wall"></div>` +
      `<div style="position:absolute;left:50%;top:0;width:349px;height:37px;margin-left:-174.5px;transform:scale(0.86);transform-origin:50% 0">` +
      `<div style="position:absolute;inset:0;background:#000;clip-path:path('${notchPath(349, S.peek)}')"></div>` +
      `<div class="nt-glimpse" style="opacity:1"><div style="background:#743AF0"></div></div><div class="nt-label" style="opacity:1">Copied</div></div></div>`,
    collections: () =>
      `<div class="chips-art"><div class="p-chip on"><span class="l"><b>Receipts</b><i>4</i></span></div><div class="p-chip"><span class="l"><b>Brand</b><i>12</i></span></div>` +
      `<div class="p-chip"><span class="l"><b>Snippets</b><i>7</i></span></div><div class="p-chip"><span class="l"><b>Starred</b><i>18</i></span></div></div>`,
    drag: () =>
      `<div style="position:relative;width:280px;height:190px"><div style="position:absolute;right:0;bottom:0;width:150px;height:110px;border-radius:16px;border:1.5px dashed rgba(255,255,255,.22)"></div>` +
      `<div style="position:absolute;left:16px;top:10px;width:204px;height:153px;transform:rotate(-6deg)">${card("a-photo", C.photo(), 0)}</div>` +
      `<svg viewBox="0 0 18 27" width="18" height="27" style="position:absolute;left:182px;top:128px" aria-hidden="true"><path d="M1.5 1.5 L1.5 21 L6.3 16.6 L9.6 24.4 L13 23 L9.7 15.3 L16 15.3 Z" fill="#000" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg></div>`,
    nonotch: () =>
      `<div style="position:relative;width:300px;height:170px;border-radius:18px;overflow:hidden"><div class="wall"></div><div class="menubar-art"><b>Studio</b><span>File</span><span>Edit</span></div>` +
      `<div class="flatpanel"><i style="width:60%"></i><i style="width:85%;height:44px;border-radius:9px"></i><i style="width:40%"></i></div></div>`,
  };
  $$("[data-art]").forEach((el) => { const make = art[el.dataset.art]; if (make) el.innerHTML = make(); });
  $$("[data-art] .slot").forEach((s) => { s.style.left = "0"; });

  // the newest release, when GitHub answers; the links above already point at 2.1.0
  if (window.fetch) {
    fetch(`https://api.github.com/repos/${REPO}/releases/latest`, { headers: { Accept: "application/vnd.github+json" } })
      .then((r) => (r.ok ? r.json() : null))
      .then((rel) => {
        if (!rel || !Array.isArray(rel.assets)) return;
        const dmg = rel.assets.find((x) => /\.dmg$/i.test(x.name));
        const v = String(rel.tag_name || "").replace(/^v/, "");
        if (!dmg || !v) return;
        $$("[data-download]").forEach((x) => { x.href = dmg.browser_download_url; });
        $$("[data-version]").forEach((x) => { x.textContent = v.split(".").slice(0, 2).join("."); });
        $$("[data-dl-meta]").forEach((x) => { x.textContent = `Version ${v} · ${(dmg.size / 1e6).toFixed(1)} MB disk image`; });
      })
      .catch(() => {});
  }
})();
