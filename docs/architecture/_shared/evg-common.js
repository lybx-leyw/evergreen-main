/* ============================================================================
   evg-common.js — 墨白风风格基座公共脚本（Evergreen 架构演示图共享）
   ----------------------------------------------------------------------------
   配套：evg-style.css（主题变量 + 组件类）
   功能：
   1) 明暗主题切换（?theme= > localStorage 'evg-theme' > 系统 prefers-color-scheme）
   2) 滚动入场动画（.evg-reveal + IntersectionObserver，data-delay 错峰）
   3) 共用工具函数（选择器 / SVG 路径 / 数字滚动 / 复制 / debounce ...）
   ----------------------------------------------------------------------------
   用法：
   <script src="_shared/evg-common.js"></script>
   · 页面加载后自动初始化（设 window.EVG_AUTO = false 可关闭自动初始化）
   · 手动初始化：EVG.init({ theme: true, reveal: true })
   · 主题开关：任意 <button data-evg-theme-toggle>；<span data-evg-theme-label> 同步显示 白/墨
   ========================================================================== */
(function (global) {
  "use strict";

  var doc = document;
  var root = doc.documentElement;
  var NS = "http://www.w3.org/2000/svg";
  var STORAGE_KEY = "evg-theme";

  /* ── 基础工具 ─────────────────────────────────────────────────────────── */
  var EVG = {
    $: function (sel, ctx) { return (ctx || doc).querySelector(sel); },
    $$: function (sel, ctx) {
      return Array.prototype.slice.call((ctx || doc).querySelectorAll(sel));
    },
    onReady: function (fn) {
      if (doc.readyState === "loading") {
        doc.addEventListener("DOMContentLoaded", fn);
      } else {
        fn();
      }
    },
    clamp: function (v, min, max) { return Math.max(min, Math.min(max, v)); },
    debounce: function (fn, ms) {
      var t;
      return function () {
        var args = arguments, self = this;
        clearTimeout(t);
        t = setTimeout(function () { fn.apply(self, args); }, ms);
      };
    },
    throttle: function (fn, ms) {
      var last = 0, t;
      return function () {
        var args = arguments, self = this, now = Date.now();
        if (now - last >= ms) { last = now; fn.apply(self, args); }
        else {
          clearTimeout(t);
          t = setTimeout(function () { last = Date.now(); fn.apply(self, args); }, ms - (now - last));
        }
      };
    },
    esc: function (s) {
      return String(s).replace(/[&<>"']/g, function (c) {
        return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
      });
    },
    copyText: function (txt, done) {
      function fallback() {
        var ta = doc.createElement("textarea");
        ta.value = txt;
        ta.style.position = "fixed";
        ta.style.opacity = "0";
        doc.body.appendChild(ta);
        ta.select();
        try { doc.execCommand("copy"); } catch (e) {}
        doc.body.removeChild(ta);
        if (done) done();
      }
      if (global.navigator && navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(txt).then(function () {
          if (done) done();
        }).catch(fallback);
      } else {
        fallback();
      }
    },

    /* ── SVG 工具 ──────────────────────────────────────────────────────── */
    svgEl: function (tag, attrs) {
      var n = doc.createElementNS(NS, tag);
      if (attrs) {
        for (var k in attrs) {
          if (Object.prototype.hasOwnProperty.call(attrs, k)) n.setAttribute(k, attrs[k]);
        }
      }
      return n;
    },
    /* 直线 path d */
    linePath: function (x1, y1, x2, y2) {
      return "M " + x1 + " " + y1 + " L " + x2 + " " + y2;
    },
    /* 水平贝塞尔曲线 path d（思维导图/流程连线）
       bend: 0=直线，0.5=标准 S 弯（默认），越大越平缓 */
    curvePath: function (x1, y1, x2, y2, bend) {
      if (bend == null) bend = 0.5;
      var dx = Math.abs(x2 - x1) * bend;
      var dir = x2 > x1 ? 1 : -1;
      return "M " + x1 + " " + y1 +
        " C " + (x1 + dx * dir) + " " + y1 +
        ", " + (x2 - dx * dir) + " " + y2 +
        ", " + x2 + " " + y2;
    },
    /* 向一个 SVG 注入标准箭头 marker（幂等，按 id 去重） */
    addArrowhead: function (svg, opts) {
      opts = opts || {};
      var id = opts.id || "evg-arrowhead";
      if (svg.querySelector("#" + id)) return id;
      var defs = svg.querySelector("defs");
      if (!defs) {
        defs = EVG.svgEl("defs");
        svg.insertBefore(defs, svg.firstChild);
      }
      var marker = EVG.svgEl("marker", {
        id: id,
        class: opts.muted ? "evg-arrowhead--muted" : "evg-arrowhead",
        viewBox: "0 0 10 10",
        refX: "8", refY: "5",
        markerWidth: "7", markerHeight: "7",
        orient: "auto-start-reverse"
      });
      marker.appendChild(EVG.svgEl("path", { d: "M0 0 L10 5 L0 10 z" }));
      defs.appendChild(marker);
      return id;
    }
  };

  /* ── 1. 明暗主题 ───────────────────────────────────────────────────────── */
  var theme = {
    current: null,      // 'light' | 'dark'（null 表示未手动设置，跟随系统）
    resolve: function () {
      // 1) URL 参数 ?theme=light|dark（不持久化，用于审查固定截图）
      try {
        var q = (global.location && global.location.search) || "";
        var m = q.match(/[?&]theme=(light|dark)/i);
        if (m) return m[1].toLowerCase();
      } catch (e) {}
      // 2) localStorage
      var saved = null;
      try { saved = global.localStorage && localStorage.getItem(STORAGE_KEY); } catch (e) {}
      if (saved === "light" || saved === "dark") return saved;
      // 3) 系统
      if (global.matchMedia && matchMedia("(prefers-color-scheme: light)").matches) return "light";
      return "dark";
    },
    apply: function (t) {
      if (t === "light" || t === "dark") root.setAttribute("data-theme", t);
      else root.removeAttribute("data-theme");
      theme.current = t;
      EVG.$$("[data-evg-theme-label]").forEach(function (el) {
        el.textContent = t === "dark" ? "墨" : "白";
      });
      var evt;
      try {
        evt = new CustomEvent("evg:themechange", { detail: { theme: t } });
        doc.dispatchEvent(evt);
      } catch (e) {}
      return t;
    },
    toggle: function () {
      var next = theme.current === "dark" ? "light" : "dark";
      try { localStorage.setItem(STORAGE_KEY, next); } catch (e) {}
      return theme.apply(next);
    },
    init: function (opts) {
      opts = opts || {};
      theme.apply(theme.resolve());

      var btn = opts.toggleSelector
        ? EVG.$(opts.toggleSelector)
        : EVG.$("[data-evg-theme-toggle]");
      if (btn) {
        btn.addEventListener("click", function (e) {
          if (e) e.preventDefault();
          theme.toggle();
        });
      }

      // 用户未手动设置时，跟随系统主题实时变化
      if (global.matchMedia) {
        var media = matchMedia("(prefers-color-scheme: light)");
        var onChange = function () {
          var saved = null;
          try { saved = global.localStorage && localStorage.getItem(STORAGE_KEY); } catch (e) {}
          if (saved !== "light" && saved !== "dark") theme.apply(theme.resolve());
        };
        if (media.addEventListener) media.addEventListener("change", onChange);
        else if (media.addListener) media.addListener(onChange);
      }
    }
  };
  EVG.theme = theme;

  /* ── 2. 滚动入场 ───────────────────────────────────────────────────────── */
  EVG.reveal = {
    init: function () {
      var els = EVG.$$(".evg-reveal");
      if (!els.length) return;
      if (!("IntersectionObserver" in global)) {
        els.forEach(function (el) { el.classList.add("is-visible"); });
        return;
      }
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (en) {
          if (!en.isIntersecting) return;
          var el = en.target;
          var delay = parseInt(el.getAttribute("data-delay") || "0", 10);
          if (delay > 0) el.style.transitionDelay = delay + "ms";
          el.classList.add("is-visible");
          io.unobserve(el);
        });
      }, { threshold: 0.12, rootMargin: "0px 0px -8% 0px" });
      els.forEach(function (el) { io.observe(el); });
    }
  };

  /* ── 3. 数字滚动（计数器/指标动图演示）────────────────────────────────── */
  EVG.countUp = function (el, to, dur, opts) {
    opts = opts || {};
    dur = dur || 900;
    var from = opts.from != null ? opts.from : 0;
    var suffix = opts.suffix != null ? opts.suffix : "";
    var start = null;
    function frame(ts) {
      if (start === null) start = ts;
      var p = Math.min((ts - start) / dur, 1);
      var eased = 1 - Math.pow(1 - p, 3); // ease-out cubic
      var v = Math.round(from + (to - from) * eased);
      el.textContent = String(v) + suffix;
      if (p < 1) global.requestAnimationFrame(frame);
      else if (opts.done) opts.done();
    }
    global.requestAnimationFrame(frame);
  };

  /* ── 4. 初始化 ─────────────────────────────────────────────────────────── */
  EVG.init = function (opts) {
    opts = opts || {};
    if (opts.theme !== false) theme.init(opts);
    if (opts.reveal !== false) EVG.reveal.init();
    return EVG;
  };

  // 自动初始化：设置 window.EVG_AUTO = false 可关闭
  EVG.onReady(function () {
    if (global.EVG_AUTO !== false) EVG.init({});
  });

  global.EVG = EVG;
})(window);
