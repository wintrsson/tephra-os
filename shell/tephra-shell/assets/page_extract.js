// Tephra's page reader. Runs inside the browser's page and returns the page as a short list of blocks that
// Tephra draws itself (page_view.gd): headings, paragraphs with links, list items, pictures, buttons, text fields.
// Every link, button and field it finds is given a number (data-tp="N") so Tephra can press it afterwards.
// It returns one JSON string: {u: address, t: title, b: [blocks], n: how many things can be pressed, x: cut short}.
// Blocks: {t:"h", l:level, r:runs} {t:"p", r:runs, q:1?} {t:"li", r:runs, d:depth, n:number?} {t:"img", s:src, a:alt,
// w, h, id?} {t:"b", x:label, id} {t:"in", k:kind, x:label, v:value, id} {t:"sel", x:label, v:chosen, id}
// {t:"pre", x:text} {t:"row", r:runs} {t:"hr"} {t:"note", x:text}. A run is [text, linkId] (linkId 0 = plain text).
return (function () {
  var MAX_BLOCKS = 700, MAX_CHARS = 50000;
  var blocks = [], runs = [], chars = 0, nextId = 1, cut = false;
  var curLink = 0, quote = 0, bullet = null, listStack = [];
  Array.prototype.forEach.call(document.querySelectorAll("[data-tp]"), function (e) { e.removeAttribute("data-tp"); });

  var SKIP = {SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, SVG: 1, TEMPLATE: 1, HEAD: 1, CANVAS: 1, OBJECT: 1, EMBED: 1, AUDIO: 1, MAP: 1, DIALOG: 0};
  function norm(s) { return s.replace(/\s+/g, " "); }
  function visible(el) {
    if (el.hidden) return false;
    var cs;
    try { cs = getComputedStyle(el); } catch (e) { return true; }
    if (cs.display === "none" || cs.visibility === "hidden" || cs.visibility === "collapse") return false;
    if (el.getAttribute("aria-hidden") === "true" && !el.querySelector("a,button,input")) return false;
    return true;
  }
  function mark(el) { var id = nextId++; el.setAttribute("data-tp", String(id)); return id; }
  function full() { return blocks.length >= MAX_BLOCKS || chars >= MAX_CHARS; }
  function push(b) { if (full()) { cut = true; return; } blocks.push(b); }

  function addText(s) {
    s = norm(s);
    if (!s) return;
    var last = runs.length ? runs[runs.length - 1] : null;
    if (s === " " && (!last || / $/.test(last[0]))) return;
    if (!last && s.charAt(0) === " ") s = s.slice(1);
    if (last && last[1] === curLink) { last[0] += s; } else { runs.push([s, curLink]); }
    chars += s.length;
  }
  function flush(kind, extra) {
    if (!runs.length) return;
    var r = runs; runs = [];
    var lastRun = r[r.length - 1];
    lastRun[0] = lastRun[0].replace(/ $/, "");
    if (!lastRun[0]) r.pop();
    if (!r.length) return;
    var b = {t: kind || (bullet ? "li" : "p"), r: r};
    if (!kind && bullet) { b.d = bullet.d; if (bullet.n) b.n = bullet.n; bullet = null; }
    if (quote && b.t === "p") b.q = 1;
    if (extra) for (var k in extra) b[k] = extra[k];
    push(b);
  }
  function isBlock(el) {
    var d;
    try { d = getComputedStyle(el).display; } catch (e) { return true; }
    return d !== "inline" && d !== "contents" && d !== "inline-block" && d !== "inline-flex" && d !== "inline-grid" && d !== "ruby";
  }
  function labelOf(el) {
    var t = el.getAttribute("aria-label") || el.getAttribute("title") || el.getAttribute("placeholder") || el.getAttribute("alt") || "";
    if (!t && el.id) { var l = document.querySelector('label[for="' + el.id.replace(/"/g, '\\"') + '"]'); if (l) t = l.textContent; }
    if (!t && el.labels && el.labels.length) t = el.labels[0].textContent;
    return norm(t || "").trim();
  }
  function imgSrc(el) {
    return el.currentSrc || el.src || el.getAttribute("data-src") || el.getAttribute("data-lazy-src") || "";
  }

  function walk(el) {
    if (full()) { cut = true; return; }
    if (el.nodeType === 3) { addText(el.nodeValue); return; }
    if (el.nodeType !== 1) return;
    var tag = el.tagName.toUpperCase();
    if (SKIP[tag]) return;
    if (!visible(el)) return;

    if (tag === "BR") { flush(); return; }
    if (tag === "HR") { flush(); push({t: "hr"}); return; }
    if (/^H[1-6]$/.test(tag)) {
      flush();
      walkChildren(el);
      flush("h", {l: parseInt(tag.charAt(1), 10)});
      return;
    }
    if (tag === "IMG" || tag === "PICTURE") {
      var im = tag === "PICTURE" ? el.querySelector("img") : el;
      if (!im) return;
      var r = im.getBoundingClientRect();
      var w = im.naturalWidth || r.width, h = im.naturalHeight || r.height;
      if (r.width < 40 || r.height < 30 || w < 40 || h < 30) return;
      var s = imgSrc(im);
      if (!s || /^data:image\/svg/.test(s) || (/^data:/.test(s) && s.length > 250000)) return;
      flush();
      var b = {t: "img", s: s, a: norm(im.getAttribute("alt") || "").trim(), w: Math.round(w), h: Math.round(h)};
      if (curLink) b.id = curLink;
      push(b);
      return;
    }
    if (tag === "VIDEO") { flush(); push({t: "note", x: "A video is here. Open the live page to watch it."}); return; }
    if (tag === "IFRAME") { flush(); push({t: "note", x: "Embedded content. Open the live page to see it."}); return; }
    if (tag === "INPUT") {
      var ty = (el.getAttribute("type") || "text").toLowerCase();
      if (ty === "hidden") return;
      flush();
      if (ty === "submit" || ty === "button" || ty === "reset" || ty === "image") {
        push({t: "b", x: norm(el.value || labelOf(el) || "Go").trim(), id: mark(el)});
      } else if (ty === "checkbox" || ty === "radio") {
        push({t: "b", x: (el.checked ? "[x] " : "[ ] ") + (labelOf(el) || ty), id: mark(el), k: ty});
      } else {
        push({t: "in", k: ty, x: labelOf(el), v: ty === "password" ? (el.value ? "••••" : "") : (el.value || ""), id: mark(el)});
      }
      return;
    }
    if (tag === "TEXTAREA") { flush(); push({t: "in", k: "textarea", x: labelOf(el), v: el.value || "", id: mark(el)}); return; }
    if (tag === "SELECT") {
      flush();
      var so = el.options && el.selectedIndex >= 0 ? el.options[el.selectedIndex] : null;
      push({t: "sel", x: labelOf(el), v: so ? norm(so.textContent).trim() : "", id: mark(el)});
      return;
    }
    if (tag === "BUTTON" || el.getAttribute("role") === "button") {
      flush();
      var txt = norm(el.innerText || el.textContent || "").trim() || labelOf(el);
      if (txt || el.querySelector("img")) { push({t: "b", x: txt || "Button", id: mark(el)}); }
      return;
    }
    if (tag === "PRE") {
      flush();
      var pt = (el.innerText || el.textContent || "").replace(/\s+$/, "");
      if (pt) { chars += pt.length; push({t: "pre", x: pt.slice(0, 1500)}); }
      return;
    }
    if (tag === "TABLE") {
      flush();
      Array.prototype.forEach.call(el.rows || [], function (row) {
        if (full()) return;
        var save = runs; runs = [];
        Array.prototype.forEach.call(row.cells || [], function (cell, i) {
          if (!visible(cell)) return;
          if (i > 0 && runs.length) addText("  ·  ");
          walkChildren(cell);
        });
        flush("row");
        runs = save;
      });
      return;
    }
    if (tag === "A" && el.getAttribute("href") !== null && !/^javascript:/i.test(el.getAttribute("href"))) {
      var outer = curLink;
      var id = mark(el);
      curLink = id;
      var blockish = isBlock(el);
      if (blockish) flush();
      walkChildren(el);
      if (blockish) flush();
      curLink = outer;
      return;
    }
    if (tag === "UL" || tag === "OL") {
      flush();
      listStack.push({o: tag === "OL", i: 0});
      walkChildren(el);
      flush();
      listStack.pop();
      return;
    }
    if (tag === "LI") {
      flush();
      var ls = listStack.length ? listStack[listStack.length - 1] : null;
      if (ls) ls.i++;
      bullet = {d: Math.max(listStack.length - 1, 0), n: ls && ls.o ? ls.i : 0};
      walkChildren(el);
      flush();
      bullet = null;
      return;
    }
    if (tag === "BLOCKQUOTE") {
      flush(); quote++;
      walkChildren(el);
      flush(); quote--;
      return;
    }
    if (tag === "LABEL" && el.querySelector("input[type=checkbox],input[type=radio]")) {
      walk(el.querySelector("input[type=checkbox],input[type=radio]"));
      return;
    }
    var block = isBlock(el);
    if (block) flush();
    walkChildren(el);
    if (block) flush();
  }
  function walkChildren(el) {
    var kids = el.childNodes;
    for (var i = 0; i < kids.length; i++) { walk(kids[i]); if (full()) { cut = true; break; } }
  }

  var root = document.body || document.documentElement;
  var main = document.querySelector("main, [role=main], article");
  if (main && (main.innerText || "").length > 400) root = main;
  walk(root);
  flush();
  return JSON.stringify({u: location.href, t: document.title || "", b: blocks, n: nextId - 1, x: cut ? 1 : 0});
})();
