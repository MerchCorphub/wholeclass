// Turns the Word manuscript (converted to HTML by mammoth) into app chapters.
// "A Note for My Reader" becomes chapter 0, "Chapter N - Title" headings become chapters,
// any later top-level section (e.g. Practice Dialogue Template) joins the chapter before it.
// Rows of the 25-hole tables get anchors (#hole-trust) so the app can link straight to a hole.
window.WCBook = (function () {
  const HOLES = ['Trust','Emotional Safety','Respect','Communication','Security','Loyalty','Physical Intimacy','Affection','Quality Time','Appreciation','Being Needed','Support','Validation','Romance','Adventure','TLC','Fun & Play','Intellectual Connection','Status & Pride','Shared Goals','Social Connection','Gift & Gesture','Aesthetic Attraction','Conflict Resolution','Freedom'];
  const slug = k => 'hole-' + k.toLowerCase().replace(/[^a-z]+/g, '-').replace(/^-|-$/g, '');
  const text = el => (el.textContent || '').replace(/\s+/g, ' ').trim();

  function split(html) {
    const doc = new DOMParser().parseFromString('<div id="r">' + html + '</div>', 'text/html');
    const root = doc.getElementById('r');
    root.querySelectorAll('img').forEach(i => { const p = i.closest('p'); (p && !text(p) ? p : i).remove(); });
    root.querySelectorAll('p').forEach(p => { if (!text(p) && !p.querySelector('br')) p.remove(); });
    root.querySelectorAll('a[id^="_"]').forEach(a => a.replaceWith(...a.childNodes));
    root.querySelectorAll('[style],[class]').forEach(el => { el.removeAttribute('style'); el.removeAttribute('class'); });

    const out = []; let cur = null, copyright = '';
    for (const node of Array.from(root.childNodes)) {
      if (node.nodeType === 1 && node.tagName === 'H1') {
        const t = text(node);
        const m = t.match(/^Chapter\s*(\d+)\s*[-–—:]?\s*(.*)$/i);
        if (/note for my reader/i.test(t)) { cur = { n: 0, title: 'A Note for My Reader', html: '', free: true }; out.push(cur); }
        else if (/table of contents/i.test(t)) { cur = { skip: true, html: '' }; }
        else if (m) { cur = { n: +m[1], title: m[2].trim() || ('Chapter ' + m[1]), html: '', free: +m[1] === 1 }; out.push(cur); }
        else if (cur && !cur.skip) { cur.html += '<h2>' + node.innerHTML + '</h2>'; }
        else { cur = { skip: true, html: '' }; }
        continue;
      }
      const h = node.nodeType === 1 ? node.outerHTML : (node.textContent.trim() ? '<p>' + node.textContent + '</p>' : '');
      if (!cur) continue;
      if (cur.skip) {
        // keep the copyright notice that sits after the table of contents
        if (node.nodeType === 1 && node.tagName === 'P' && !node.querySelector('a') &&
            /copyright|all rights reserved|published by|work of self-discovery|printed in/i.test(text(node))) copyright += h;
        continue;
      }
      cur.html += h;
    }
    const note = out.find(c => c.n === 0);
    if (note && copyright) note.html += '<hr>' + copyright;
    // anchor hole rows
    out.forEach(c => {
      const d = new DOMParser().parseFromString('<div id="r">' + c.html + '</div>', 'text/html');
      const seen = {};
      d.querySelectorAll('tr').forEach(tr => {
        const td = tr.querySelector('td'); if (!td) return;
        const name = text(td);
        const k = HOLES.find(h => h.toLowerCase() === name.toLowerCase());
        if (k && !seen[k] && !document.getElementById(slug(k))) { tr.id = slug(k); seen[k] = 1; }
      });
      c.html = d.getElementById('r').innerHTML;
      c.anchors = Object.keys(seen).length;
    });
    out.sort((a, b) => a.n - b.n);
    return out;
  }
  // The audiobook script: "Introduction –" and "Chapter N –" headings, lines inside paragraphs split by
  // line breaks, [bracketed] lines become stage notes (shown, never read aloud), "- " lines become bullets.
  function splitSeries(html) {
    const doc = new DOMParser().parseFromString('<div id="r">' + html + '</div>', 'text/html');
    const root = doc.getElementById('r');
    const esc = t => t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const out = []; let cur = null;
    for (const node of Array.from(root.children)) {
      if (/^H[1-3]$/.test(node.tagName)) {
        const t = text(node);
        const m = t.match(/^Chapter\s*(\d+)\s*[-–—:]\s*(.*)$/i);
        if (m) { cur = { n: +m[1], title: m[2].trim() || ('Chapter ' + m[1]), lines: [] }; out.push(cur); }
        else if (/^introduction/i.test(t)) { cur = { n: 0, title: t.replace(/^introduction\s*[-–—:]?\s*/i, '') || 'Introduction', lines: [] }; out.push(cur); }
        else cur = null;
        continue;
      }
      if (!cur) continue;
      if (node.tagName === 'UL' || node.tagName === 'OL') { node.querySelectorAll('li').forEach(li => cur.lines.push('- ' + text(li))); continue; }
      node.innerHTML.split(/<br\s*\/?>/i).forEach(part => { const d = doc.createElement('div'); d.innerHTML = part; const t = (d.textContent || '').replace(/\s+/g, ' ').trim(); if (t) cur.lines.push(t); });
    }
    return out.map(c => {
      let h = '', inList = false;
      c.lines.forEach(l => {
        if (/^[-•]\s+/.test(l)) { if (!inList) { h += '<ul>'; inList = true; } h += '<li>' + esc(l.replace(/^[-•]\s+/, '')) + '</li>'; return; }
        if (inList) { h += '</ul>'; inList = false; }
        const cue = l.match(/^\[([^\]]+)\]$/);
        h += cue ? '<p class="cue">' + esc(cue[1]) + '</p>' : '<p>' + esc(l) + '</p>';
      });
      if (inList) h += '</ul>';
      return { n: c.n, title: c.title, html: h, free: c.n <= 1 };
    }).sort((a, b) => a.n - b.n);
  }
  return { split, splitSeries, HOLES, slug };
})();
