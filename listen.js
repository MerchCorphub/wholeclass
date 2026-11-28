// WholeClass Listen player: reads a chapter or lesson aloud with the device's built-in voice.
// Shared by read.html (the book) and listen.html (the Know Your Holes Series).
window.WCListen = (function(){
  const supported = 'speechSynthesis' in window && 'SpeechSynthesisUtterance' in window;
  const CSS = `.speaking{background:#FFF4DE;box-shadow:0 0 0 6px #FFF4DE;border-radius:4px}
.listen{position:fixed;left:0;right:0;bottom:0;z-index:6;background:#01434B;color:#fff;padding:10px 12px calc(10px + env(safe-area-inset-bottom));display:none}
.listen.on{display:block}
.listen .in{max-width:720px;margin:0 auto;display:flex;align-items:center;gap:8px}
.listen button,.listen select{font:700 14px 'Manrope',sans-serif;border-radius:999px;border:1.5px solid #2A6E74;background:#0A525A;color:#fff;padding:9px 12px;cursor:pointer}
.listen .play{background:#E9B53F;border-color:#E9B53F;color:#2A1C00;min-width:92px}
.listen .where{flex:1;min-width:0;font-size:12.5px;color:#CFE3E1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.listen select{padding:8px 6px;max-width:120px}
.listen #lAwake[aria-pressed=true]{background:#E9B53F33;border-color:#E9B53F}
.listen .tip{max-width:720px;margin:6px auto 0;font-size:12px;color:#CFE3E1;text-align:center}
.lbtn{display:inline-flex;align-items:center;gap:8px;border:none;border-radius:999px;padding:11px 18px;background:#01434B;color:#fff;font:700 14px 'Sora',sans-serif;cursor:pointer;margin:0 0 18px}
body.listening main{padding-bottom:120px}
@media (max-width:420px){.listen .where{display:none}}`;
  const BAR = `<div class="listen" id="lbar" role="region" aria-label="Listen to this chapter"><div class="in">
  <button id="lPrev" aria-label="Back one paragraph">⏮</button>
  <button class="play" id="lPlay">▶ Play</button>
  <button id="lNext" aria-label="Forward one paragraph">⏭</button>
  <span class="where" id="lWhere" aria-live="polite"></span>
  <button id="lAwake" aria-pressed="true" title="Keep the screen on while listening">☀</button>
  <select id="lRate" aria-label="Reading speed"><option value="0.8">0.8×</option><option value="1" selected>1×</option><option value="1.2">1.2×</option><option value="1.5">1.5×</option></select>
  <button id="lClose" aria-label="Close the player">✕</button>
</div><div class="tip" id="lTip"></div></div>`;
  function ensureUi(){
    if (document.getElementById('lbar')) return;
    const st = document.createElement('style'); st.textContent = CSS; document.head.appendChild(st);
    const w = document.createElement('div'); w.innerHTML = BAR; document.body.appendChild(w.firstElementChild);
  }
  // ---------- Pronunciation list: fixes words the phone voice says wrong (read/red, live/lyve) ----------
  // The admin keeps the list in the console. Only what the voice SAYS changes; the page text stays as written.
  let fixes = [], fixesReady = null;
  const escRe = t => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  function loadFixes(){
    if (fixesReady) return fixesReady;
    fixesReady = (async () => {
      let list = null;
      try { const c = sessionStorage.getItem('wc-pron'); if (c) list = JSON.parse(c); } catch (e) {}
      if (!list && window.WC) { try { list = await window.WC.rpc('list_pronunciations'); sessionStorage.setItem('wc-pron', JSON.stringify(list)); } catch (e) { list = []; } }
      fixes = (list || []).filter(f => f.phrase && f.say_as).sort((a, b) => b.phrase.length - a.phrase.length)
        .map(f => ({ re: new RegExp('(^|[^A-Za-z\'])' + escRe(f.phrase.replace(/[\u2018\u2019]/g, "'")) + '(?=$|[^A-Za-z\'])', 'gi'), say: f.say_as }));
    })();
    return fixesReady;
  }
  function spoken(text){
    let t = text.replace(/[\u2018\u2019]/g, "'");
    fixes.forEach(f => { t = t.replace(f.re, (m, pre) => pre + f.say); });
    return t;
  }

  // ---------- Listen: reads the chapter aloud with the device's built-in voice ----------
  function setup(opts){
    const n = opts.n, title = opts.title, main = opts.main, keyPrefix = opts.keyPrefix || 'wc-listen-', headPrefix = opts.headPrefix;
    ensureUi();
    const synth = window.speechSynthesis, bar = document.getElementById('lbar');
    const book = main.querySelector('.book');
    const clean = t => t.replace(/_{3,}/g, ' blank ').replace(/[“”]/g, '"').replace(/\s+/g, ' ').trim();
    // one item per paragraph, list item, heading or table row
    const items = [];
    const addText = (el, text) => {
      text = clean(text); if (!text || !/[A-Za-z0-9]/.test(text)) return;
      // long paragraphs are split by sentence so no single utterance runs too long
      const parts = text.length > 280 ? (text.match(/[^.!?]+[.!?]+["')\]]*\s*|[^.!?]+$/g) || [text]) : [text];
      let buf = '';
      parts.forEach(pt => { if ((buf + pt).length > 280 && buf) { items.push({el, text: buf.trim()}); buf = ''; } buf += pt; });
      if (buf.trim()) items.push({el, text: buf.trim()});
    };
    addText(main.querySelector('h1'), (headPrefix != null ? headPrefix : (n === 0 ? '' : 'Chapter ' + n + '. ')) + title + (/[.!?]$/.test(title) ? '' : '.'));
    book.querySelectorAll('p, li, h2, h3, tr').forEach(el => {
      if (el.classList.contains('cue')) return; // stage directions are shown, never read aloud
      if (el.tagName === 'P' && el.closest('li, td, th')) return;
      if (el.tagName === 'LI' && el.querySelector('li')) { // read only this item's own text, nested items come next
        const c = el.cloneNode(true); c.querySelectorAll('ul,ol').forEach(x => x.remove()); return addText(el, c.textContent);
      }
      if (el.tagName === 'TR') {
        const table = el.closest('table'); const heads = Array.from(table.querySelectorAll('thead th')).map(th => clean(th.textContent));
        if (el.closest('thead')) return;
        const cells = Array.from(el.children).map(td => clean(td.textContent));
        return addText(el, cells.map((c, i) => i === 0 || !heads[i] ? c : heads[i] + ': ' + c).join('. ') + '.');
      }
      addText(el, el.textContent);
    });
    if (!items.length) return;
    loadFixes();
    const key = keyPrefix + n;
    let i = 0, playing = false, voice = null, rate = 1;
    try { i = Math.min(+localStorage.getItem(key) || 0, items.length - 1); rate = +localStorage.getItem('wc-listen-rate') || 1; } catch (e) {}
    document.getElementById('lRate').value = String(rate);
    const pickVoice = () => {
      const vs = synth.getVoices().filter(v => /^en(-|_|$)/i.test(v.lang));
      voice = vs.find(v => /en-US/i.test(v.lang) && /natural|enhanced|premium|samantha|google us/i.test(v.name)) || vs.find(v => /en-US/i.test(v.lang)) || vs[0] || null;
    };
    pickVoice(); if (synth.onvoiceschanged !== undefined) synth.onvoiceschanged = pickVoice;
    const mark = () => {
      document.querySelectorAll('.speaking').forEach(x => x.classList.remove('speaking'));
      const it = items[i]; if (!it) return;
      it.el.classList.add('speaking');
      const r = it.el.getBoundingClientRect();
      if (r.top < 70 || r.bottom > innerHeight - 110) it.el.scrollIntoView({block: 'center', behavior: 'smooth'});
      document.getElementById('lWhere').textContent = 'Part ' + (i + 1) + ' of ' + items.length;
      try { localStorage.setItem(key, i); } catch (e) {}
    };
    const playBtn = document.getElementById('lPlay');
    const setBtn = () => { playBtn.textContent = playing ? '❚❚ Pause' : '▶ Play'; };
    let token = 0;
    const speak = () => {
      const my = ++token; synth.cancel();
      if (i >= items.length) { playing = false; setBtn(); awake(false); i = 0; document.getElementById('lWhere').textContent = 'Finished this chapter'; try { localStorage.removeItem(key); } catch (e) {} return; }
      mark();
      const u = new SpeechSynthesisUtterance(spoken(items[i].text));
      if (voice) u.voice = voice; u.lang = voice ? voice.lang : 'en-US'; u.rate = rate;
      u.onend = () => { if (my !== token || !playing) return; i++; speak(); };
      u.onerror = e => { if (my !== token || !playing || e.error === 'interrupted' || e.error === 'canceled') return; i++; speak(); };
      synth.speak(u);
    };
    // the phone's voice stops when the screen sleeps, so keep the screen on while it reads
    const A = window.WCAwake, awBtn = document.getElementById('lAwake'), tip = document.getElementById('lTip');
    const awake = v => { if (A) v ? A.on() : A.off(); };
    const showAwake = () => {
      const on = !A || A.enabled();
      awBtn.setAttribute('aria-pressed', on ? 'true' : 'false');
      awBtn.setAttribute('aria-label', on ? 'Screen stays on while listening. Tap to let it sleep.' : 'Screen may sleep. Tap to keep it on while listening.');
      tip.textContent = !A || !A.supported ? 'Keep this screen open while listening. Reading stops if the phone locks.'
        : on ? 'The screen stays on while this reads aloud. Reading stops if the phone is locked.' : 'Screen can sleep. Reading stops when it does. Tap ☀ to keep it on.';
    };
    if (A && A.supported) awBtn.onclick = () => { A.setEnabled(!A.enabled()); showAwake(); if (playing) awake(true); }; else awBtn.hidden = true;
    showAwake();
    const play = () => { playing = true; setBtn(); awake(true); speak(); };
    const pause = () => { playing = false; token++; synth.cancel(); setBtn(); awake(false); }; // stop and resume from the same part (pause() is unreliable on some phones)
    const open = () => { bar.classList.add('on'); document.body.classList.add('listening'); };
    document.getElementById('listenBtn').onclick = () => { open(); play(); };
    playBtn.onclick = () => playing ? pause() : play();
    document.getElementById('lPrev').onclick = () => { i = Math.max(0, i - 1); playing ? speak() : mark(); };
    document.getElementById('lNext').onclick = () => { i = Math.min(items.length - 1, i + 1); playing ? speak() : mark(); };
    document.getElementById('lRate').onchange = e => { rate = +e.target.value; try { localStorage.setItem('wc-listen-rate', rate); } catch (er) {} if (playing) speak(); };
    document.getElementById('lClose').onclick = () => { pause(); bar.classList.remove('on'); document.body.classList.remove('listening'); document.querySelectorAll('.speaking').forEach(x => x.classList.remove('speaking')); };
    // tap any paragraph while the player is open to listen from there
    book.addEventListener('click', e => { if (!bar.classList.contains('on')) return; const el = e.target.closest('p, li, h2, h3, tr'); const j = items.findIndex(it => it.el === el || it.el.contains(el)); if (j >= 0) { i = j; playing ? speak() : mark(); } });
    addEventListener('pagehide', () => synth.cancel());
    if (i > 0) document.getElementById('listenBtn').textContent = '🔊 Keep listening where you left off';
  }

  return { supported, setup, spoken, loadFixes, reloadFixes(){ try { sessionStorage.removeItem('wc-pron'); } catch (e) {} fixesReady = null; return loadFixes(); } };
})();
