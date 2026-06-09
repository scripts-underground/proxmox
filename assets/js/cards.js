const PAL = ["#fef2e6","#fdf3e0","#f0f5ea","#e6f0f2","#f5eae6","#f0eaf2","#f5f0e6","#e6f0ea"];
const TC = ["#d95f14","#b85a12","#3f7a3f","#127a7a","#b83a3a","#7a3a8a","#8a6a12","#1a7a6a"];
const DPAL = ["#2a1405","#221805","#0a1a0a","#0a1a18","#220a0a","#180a22","#221805","#0a1a12"];
const DTC = ["#ff8a3a","#e0a030","#50b850","#30b0b0","#e05050","#a050c0","#c0a020","#30a090"];

function init(s) {
  let r = s.title.replace(/[-_.]/g, " ").replace(/([a-z])([A-Z])/g, "$1 $2");
  let w = r.split(/ +/).filter(Boolean);
  let sk = ["for","the","and","of","to","in","a","an","with","by","or"];
  let res = "";
  for (let x of w) { if (sk.includes(x.toLowerCase())) continue; res += x[0].toUpperCase(); if (res.length >= 2) break; }
  return res || r[0].toUpperCase();
}

function cs(i) {
  let d = document.documentElement.classList.contains("dark");
  return { bg: d ? DPAL[i%8] : PAL[i%8], tc: d ? DTC[i%8] : TC[i%8] };
}

function fb(inits, w, h, i) {
  let c = cs(i);
  return "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h + '"><rect x="2" y="2" width="' + (w-4) + '" height="' + (h-4) + '" rx="6" fill="' + c.bg + '"/><text x="' + (w/2) + '" y="' + (h/2) + '" text-anchor="middle" dominant-baseline="central" font-family="sans-serif" font-size="' + Math.round(w*0.4) + '" font-weight="700" fill="' + c.tc + '">' + inits + '</text></svg>');
}

function resolveCSS(v) {
  return getComputedStyle(document.documentElement).getPropertyValue(v).trim();
}

function sortBtns(mode, t) {
  t = t || "";
  return '<span class="sort-bar">' +
    '<a href="#" onclick="toggleSort(\'' + t + '\');render();return false" class="sort-link ' + (mode === "name" ? 'sort-link-active' : 'sort-link-inactive') + '">A</a> ' +
    '<a href="#" onclick="toggleSort(\'' + t + '\');render();return false" class="sort-link ' + (mode === "date" ? 'sort-link-active' : 'sort-link-inactive') + '"><span class="sort-icon">⏱</span></a>' +
    '</span>';
}

function cardHTML(s, idx) {
  let inits = init(s);
  let i = idx % 8;
  let date = s.updated_at ? s.updated_at.slice(0,10).split("-").join("/") : "";
  let res = date ? '<span>' + date + '</span>' : "";
  let tags = (s.tags || []).slice(0, 4).map(function(t) { return '<a href="/?tag=' + encodeURIComponent(t) + '" class="tag" onclick="if(window.setF){event.stopPropagation();setF(\'' + t + '\');return false}">' + t + '</a>'; }).join("");
  let d = (s.description || "").length > 120 ? s.description.slice(0, 120) + "…" : (s.description || "");
  let logo = '<img src="' + (s.logo || "") + '" alt="' + inits + '" class="script-card-logo" width="40" height="40" loading="lazy" onerror="this.src=\'' + fb(inits, 40, 40, i) + '\';this.onerror=null">';
  let top = logo + (res ? '<div class="script-card-resources">' + res + '</div>' : "");
  let titleLink = '<a href="' + s.page + '">' + s.title + '</a>';
  return '<div class="script-card" onclick="location.href=\'' + s.page + '\'"><div class="script-card-top">' + top + '</div><div class="script-card-info"><div class="script-card-title">' + titleLink + '</div>' + (d ? '<div class="script-card-desc">' + d + '</div>' : "") + (tags ? '<div class="script-card-tags">' + tags + '</div>' : "") + '</div></div>';
}
