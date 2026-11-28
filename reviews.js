// WholeClass reviews: Day 7 check-in, guided reviews, course review blocks, helpful votes and private feedback.
// Shared by the app (index.html), the Series page (listen.html) and the reviews page (reviews.html).
// Every sheet is drawn outside the app's own screens so it never interferes with them.
window.WCReviews = (function(){
  const HOLES = ['Trust','Emotional Safety','Respect','Communication','Security','Loyalty','Physical Intimacy','Affection','Quality Time','Appreciation','Being Needed','Support','Validation','Romance','Adventure','TLC','Fun & Play','Intellectual Connection','Status & Pride','Shared Goals','Social Connection','Gift & Gesture','Aesthetic Attraction','Conflict Resolution','Freedom'];
  const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const errMsg = e => (e && (e.message || e.details)) || 'Something went wrong. Please try again.';
  const courseName = (c, s) => c === 'class' ? 'the 14-Day Discovery Class' : 'Season ' + s;
  const starsText = n => '★★★★★'.slice(0, Math.round(n)) + '☆☆☆☆☆'.slice(0, 5 - Math.round(n));
  const CSS = `
.wcr-back{position:fixed;inset:0;z-index:1000;background:rgba(1,30,34,.55);display:flex;align-items:flex-end;justify-content:center;animation:wcrf .2s}
.wcr-sheet{background:#FEF9F2;color:#2A3446;width:100%;max-width:560px;max-height:92vh;overflow-y:auto;border-radius:22px 22px 0 0;padding:20px 20px calc(22px + env(safe-area-inset-bottom));font-family:'Manrope',system-ui,sans-serif;box-shadow:0 -10px 30px rgba(0,0,0,.2);animation:wcru .25s}
@keyframes wcrf{from{opacity:0}}@keyframes wcru{from{transform:translateY(30px)}}
.wcr-sheet h3{font-family:'Sora',sans-serif;color:#01434B;font-size:20px;line-height:1.25;margin:4px 0 6px}
.wcr-k{font-family:'Sora',sans-serif;font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:#8A5A00;margin:0}
.wcr-p{font-size:14px;color:#4A5468;line-height:1.5;margin:0 0 12px}
.wcr-stars{display:flex;gap:6px;margin:6px 0 12px}
.wcr-stars button{flex:1;border:1.5px solid #E3D7BF;background:#fff;border-radius:14px;padding:10px 0;font-size:26px;line-height:1;cursor:pointer;color:#C9B994}
.wcr-stars button.on{color:#C48504;border-color:#E9B53F;background:#FFF6DF}
.wcr-l{display:block;font-weight:800;font-size:13.5px;color:#01434B;margin:12px 0 5px}
.wcr-in,.wcr-ta,.wcr-sel{width:100%;box-sizing:border-box;border:1.5px solid #D5DCE7;border-radius:12px;padding:11px 12px;font:500 14.5px 'Manrope',sans-serif;background:#fff;color:#2A3446}
.wcr-ta{min-height:86px;resize:vertical}
.wcr-opts{display:flex;gap:8px;flex-wrap:wrap}
.wcr-opts label{flex:1;min-width:140px;border:1.5px solid #D5DCE7;border-radius:12px;padding:10px 12px;background:#fff;font-size:13.5px;font-weight:700;color:#01434B;cursor:pointer;display:flex;gap:8px;align-items:center}
.wcr-opts input{accent-color:#01434B}
.wcr-check{display:flex;gap:10px;align-items:flex-start;margin-top:14px;font-size:13.5px;color:#2A3446;line-height:1.4}
.wcr-check input{width:20px;height:20px;accent-color:#01434B;flex:none;margin-top:1px}
.wcr-go{display:block;width:100%;border:none;border-radius:999px;padding:14px;margin-top:16px;font:700 15px 'Sora',sans-serif;cursor:pointer;background:#01434B;color:#fff}
.wcr-go.gold{background:linear-gradient(135deg,#E9B53F,#C48504);color:#2A1C00}
.wcr-go:disabled{opacity:.6}
.wcr-skip{display:block;width:100%;border:none;background:none;color:#5A6478;font:600 14px 'Manrope',sans-serif;padding:12px;cursor:pointer}
.wcr-msg{border-radius:12px;padding:10px 12px;margin-top:10px;font-size:13.5px;line-height:1.4}
.wcr-msg.ok{background:#E3F2F1;color:#0A5656}.wcr-msg.err{background:#FDECEA;color:#8A1F11}
.wcr-box{background:#fff;border:1px solid #EADFCB;border-radius:18px;padding:16px;margin-top:14px;color:#2A3446;font-family:'Manrope',system-ui,sans-serif;text-align:left}
.wcr-sum{display:flex;align-items:center;gap:12px}
.wcr-avg{font:800 30px 'Sora',sans-serif;color:#01434B}
.wcr-gold{color:#C48504;letter-spacing:1px}
.wcr-rev{border-top:1px solid #F0E8DA;padding:12px 0 2px}
.wcr-rev .q{font-size:14px;line-height:1.5;color:#2A3446;margin:6px 0 0}
.wcr-rev .qq{font-size:12px;font-weight:800;color:#5A6478;text-transform:uppercase;letter-spacing:.06em;margin-top:8px}
.wcr-meta{font-size:12.5px;color:#5A6478;font-weight:600}
.wcr-tag{display:inline-block;border-radius:999px;background:#E8F0EF;color:#01434B;font-size:11.5px;font-weight:800;padding:3px 9px;margin-left:6px}
.wcr-help{border:1.5px solid #D5DCE7;background:#fff;border-radius:999px;padding:6px 12px;font:700 12.5px 'Manrope',sans-serif;color:#01434B;cursor:pointer;margin-top:8px}
.wcr-help.on{background:#01434B;color:#fff;border-color:#01434B}
.wcr-link{display:inline-block;margin-top:10px;font-weight:800;color:#0E6B6B;text-decoration:none;font-size:14px;background:none;border:none;cursor:pointer;padding:0}
.wcr-dark{background:#01434B;color:#fff;border:none}
.wcr-dark .wcr-avg,.wcr-dark h4{color:#fff}.wcr-dark .wcr-meta{color:#CFE3E1}.wcr-dark .wcr-rev{border-color:#165F66}.wcr-dark .q{color:#fff}.wcr-dark .qq{color:#9CC7C4}`;
  function ensureCss(){ if (document.getElementById('wcr-css')) return; const st = document.createElement('style'); st.id = 'wcr-css'; st.textContent = CSS; document.head.appendChild(st); }

  function sheet(html){
    ensureCss();
    const back = document.createElement('div'); back.className = 'wcr-back';
    back.innerHTML = '<div class="wcr-sheet" role="dialog" aria-modal="true">' + html + '</div>';
    const close = () => { back.remove(); document.removeEventListener('keydown', onKey); };
    const onKey = e => { if (e.key === 'Escape') close(); };
    back.addEventListener('click', e => { if (e.target === back) close(); });
    document.addEventListener('keydown', onKey);
    document.body.appendChild(back);
    const box = back.firstElementChild, q = sel => box.querySelector(sel);
    const first = box.querySelector('button, input, textarea, select'); if (first) setTimeout(() => first.focus(), 50);
    return { box, q, close };
  }
  const msg = (el, text, ok) => { el.innerHTML = '<div class="wcr-msg ' + (ok ? 'ok' : 'err') + '">' + esc(text) + '</div>'; };
  function starPicker(el, value, onPick){
    el.innerHTML = [1,2,3,4,5].map(n => '<button type="button" data-s="' + n + '" aria-label="' + n + ' star' + (n > 1 ? 's' : '') + '">★</button>').join('');
    const paint = v => el.querySelectorAll('button').forEach(b => { b.classList.toggle('on', +b.dataset.s <= v); b.setAttribute('aria-pressed', +b.dataset.s === v ? 'true' : 'false'); });
    paint(value || 0);
    el.querySelectorAll('button').forEach(b => b.onclick = () => { paint(+b.dataset.s); onPick(+b.dataset.s); });
  }

  // 1. Day 7 check-in: one tap saves the stars, the comment is optional
  function checkin(){
    const s = sheet('<p class="wcr-k">Day 7 check-in</p><h3>Halfway there. How is the class going for you?</h3><p class="wcr-p">One tap. This goes only to the WholeClass team.</p>' +
      '<div class="wcr-stars" id="wcrS"></div><div id="wcrMore" hidden><label class="wcr-l" for="wcrC">Anything to add? <span style="font-weight:600;color:#5A6478">(optional, one line)</span></label>' +
      '<input class="wcr-in" id="wcrC" maxlength="200" placeholder="e.g. Day 4 really opened my eyes"><button class="wcr-go" id="wcrSend">Send</button></div><div id="wcrM"></div><button class="wcr-skip" id="wcrX">Not now</button>');
    let stars = 0;
    s.q('#wcrX').onclick = s.close;
    starPicker(s.q('#wcrS'), 0, async v => {
      stars = v; s.q('#wcrMore').hidden = false; s.q('#wcrX').textContent = 'Done';
      try { await WC.rpc('submit_checkin', { p_stars: v, p_comment: null }); msg(s.q('#wcrM'), 'Thank you. Your check-in was saved.', true); } catch (e) { msg(s.q('#wcrM'), errMsg(e)); }
    });
    s.q('#wcrSend').onclick = async () => {
      const b = s.q('#wcrSend'); b.disabled = true;
      try { await WC.rpc('submit_checkin', { p_stars: stars, p_comment: s.q('#wcrC').value }); msg(s.q('#wcrM'), 'Thank you. See you tomorrow for Day 8.', true); setTimeout(s.close, 1200); }
      catch (e) { b.disabled = false; msg(s.q('#wcrM'), errMsg(e)); }
    };
  }

  // 2. Guided review (Day 14 for the class; also used for a Series season)
  async function reviewForm(opts){
    const course = opts.course || 'class', season = course === 'series' ? (opts.season || 1) : 0;
    let mine = null; try { mine = await WC.rpc('my_review', { p_course: course, p_season: season }); } catch (e) {}
    if (mine && mine.can_review === false) { const s = sheet('<h3>Reviews come from members who have this course open</h3><p class="wcr-p">Open ' + esc(courseName(course, season)) + ' to share how it went.</p><button class="wcr-go" id="x">OK</button>'); s.q('#x').onclick = s.close; return; }
    const r = (mine && mine.review) || {};
    const hole = r.hole || opts.hole || '';
    const isClass = course === 'class';
    const title = isClass ? 'You finished. Help the next person find their holes.' : 'How did Season ' + season + (opts.title ? ': ' + esc(opts.title) : '') + ' land for you?';
    const s = sheet('<p class="wcr-k">' + (isClass ? 'Your review · 14-Day Discovery Class' : 'Your review · The Know Your Holes Series') + '</p><h3>' + title + '</h3>' +
      (r.status ? '<p class="wcr-p">You reviewed this before' + (r.status === 'approved' ? ' and it is live' : r.status === 'pending' ? ' and it is waiting for approval' : '') + '. Saving changes sends it for approval again.</p>' : '<p class="wcr-p">Reviews are checked by the WholeClass team before they appear.</p>') +
      '<label class="wcr-l">Your rating</label><div class="wcr-stars" id="wcrS"></div>' +
      '<label class="wcr-l" for="wcrH">' + (isClass ? 'What hole did you discover?' : 'Which hole did this season speak to? <span style="font-weight:600;color:#5A6478">(optional)</span>') + '</label>' +
      '<select class="wcr-sel" id="wcrH"><option value="">' + (isClass ? 'Choose a hole' : 'No particular hole') + '</option>' + HOLES.map(h => '<option' + (h === hole ? ' selected' : '') + '>' + esc(h) + '</option>').join('') + (hole && !HOLES.includes(hole) ? '<option selected>' + esc(hole) + '</option>' : '') + '</select>' +
      '<label class="wcr-l" for="wcrA">What changed in how you see your relationships?</label><textarea class="wcr-ta" id="wcrA" maxlength="1500" placeholder="In your own words">' + esc(r.changed || '') + '</textarea>' +
      '<label class="wcr-l" for="wcrB">Who would you recommend this to?</label><input class="wcr-in" id="wcrB" maxlength="600" value="' + esc(r.recommend || '') + '" placeholder="e.g. Engaged couples, my small group, anyone starting over">' +
      '<label class="wcr-l">Show my name as</label><div class="wcr-opts"><label><input type="radio" name="wcrD" value="initial"' + (r.display !== 'anonymous' ? ' checked' : '') + '> First name and last initial</label><label><input type="radio" name="wcrD" value="anonymous"' + (r.display === 'anonymous' ? ' checked' : '') + '> Anonymous</label></div>' +
      '<label class="wcr-check"><input type="checkbox" id="wcrMk"' + (r.marketing_ok ? ' checked' : '') + '><span>OK to use my review in WholeClass marketing.</span></label>' +
      '<button class="wcr-go gold" id="wcrGo">Send my review</button><div id="wcrM"></div><button class="wcr-skip" id="wcrX">Not now</button>');
    let stars = r.stars || 0;
    starPicker(s.q('#wcrS'), stars, v => { stars = v; });
    s.q('#wcrX').onclick = () => { s.close(); if (opts.onClose) opts.onClose(false); };
    s.q('#wcrGo').onclick = async () => {
      const b = s.q('#wcrGo');
      if (!stars) return msg(s.q('#wcrM'), 'Tap the stars to choose a rating.');
      if (isClass && !s.q('#wcrH').value) return msg(s.q('#wcrM'), 'Choose the hole you discovered.');
      if (!s.q('#wcrA').value.trim() && !s.q('#wcrB').value.trim()) return msg(s.q('#wcrM'), 'Answer at least one of the two questions.');
      b.disabled = true; b.textContent = 'Sending…';
      try {
        await WC.rpc('submit_review', { p_course: course, p_season: season, p_stars: stars, p_hole: s.q('#wcrH').value, p_changed: s.q('#wcrA').value, p_recommend: s.q('#wcrB').value,
          p_display: (s.box.querySelector('input[name=wcrD]:checked') || {}).value || 'initial', p_marketing: s.q('#wcrMk').checked });
        s.close();
        if (opts.onClose) opts.onClose(true);
        else { const t = sheet('<h3>Thank you</h3><p class="wcr-p">Your review was sent. It appears on the course page once the WholeClass team approves it.</p><button class="wcr-go" id="x">Done</button>'); t.q('#x').onclick = t.close; }
      } catch (e) { b.disabled = false; b.textContent = 'Send my review'; msg(s.q('#wcrM'), errMsg(e)); }
    };
  }

  // one review card
  function card(r, signedIn){
    return '<div class="wcr-rev" data-id="' + r.id + '"><div><span class="wcr-gold">' + starsText(r.stars) + '</span>' + (r.hole ? '<span class="wcr-tag">' + esc(r.hole) + '</span>' : '') + '</div>' +
      (r.changed ? '<div class="qq">What changed</div><p class="q">' + esc(r.changed) + '</p>' : '') +
      (r.recommend ? '<div class="qq">I’d recommend it to</div><p class="q">' + esc(r.recommend) + '</p>' : '') +
      '<div class="wcr-meta" style="margin-top:8px">' + esc(r.name) + ' · ' + esc(r.month) + (r.helpful ? ' · ' + r.helpful + ' found this helpful' : '') + '</div>' +
      (r.mine ? '<div class="wcr-meta" style="margin-top:6px">Your review</div>' : '<button class="wcr-help' + (r.voted ? ' on' : '') + '" data-help="' + r.id + '" aria-pressed="' + (r.voted ? 'true' : 'false') + '">👍 Was this helpful?' + (r.voted ? ' Yes' : '') + '</button>') + '</div>';
  }
  function wireHelp(root){
    root.querySelectorAll('[data-help]').forEach(b => b.onclick = async () => {
      b.disabled = true;
      try {
        const x = await WC.rpc('vote_helpful', { p_review: b.dataset.help });
        b.classList.toggle('on', x.voted); b.setAttribute('aria-pressed', x.voted ? 'true' : 'false'); b.textContent = '👍 Was this helpful?' + (x.voted ? ' Yes' : '');
        const meta = b.parentNode.querySelector('.wcr-meta'); if (meta) meta.textContent = meta.textContent.replace(/ · \d+ found this helpful$/, '') + (x.helpful ? ' · ' + x.helpful + ' found this helpful' : '');
      } catch (e) { b.textContent = /sign in/i.test(errMsg(e)) ? 'Sign in to vote' : errMsg(e); }
      b.disabled = false;
    });
  }
  const allLink = (course, season) => 'reviews.html?c=' + course + (course === 'series' ? '&s=' + season : '');

  // 3. Review block for a course page: average, count, top 3 by helpful votes, link to all
  async function summary(el, course, season, opts){
    opts = opts || {}; ensureCss();
    let d; try { d = await WC.rpc('course_reviews', { p_course: course, p_season: course === 'series' ? season : 0, p_hole: null, p_limit: 3, p_offset: 0 }); } catch (e) { el.innerHTML = ''; return; }
    const signed = !!opts.signedIn;
    const write = opts.canWrite ? '<button class="wcr-link" data-write="1">✎ Write a review</button>' : '';
    if (!d.count) { el.innerHTML = '<div class="wcr-box' + (opts.dark ? ' wcr-dark' : '') + '"><h4 style="font-family:Sora,sans-serif;margin:0;color:#01434B">Member reviews</h4><p class="wcr-meta" style="margin:6px 0 0">No reviews yet.' + (opts.canWrite ? ' Be the first to share how it went.' : '') + '</p>' + write + '</div>'; }
    else el.innerHTML = '<div class="wcr-box' + (opts.dark ? ' wcr-dark' : '') + '"><div class="wcr-sum"><div class="wcr-avg">' + Number(d.average).toFixed(1) + '</div><div><div class="wcr-gold" style="font-size:18px">' + starsText(d.average) + '</div><div class="wcr-meta">' + d.count + ' review' + (d.count === 1 ? '' : 's') + '</div></div></div>' +
      d.reviews.map(r => card(r, signed)).join('') +
      '<div style="display:flex;gap:16px;flex-wrap:wrap"><a class="wcr-link" href="' + allLink(course, season) + '">See all ' + d.count + ' review' + (d.count === 1 ? '' : 's') + ' ›</a>' + write + '</div></div>';
    wireHelp(el);
    const w = el.querySelector('[data-write]'); if (w) w.onclick = () => reviewForm({ course, season, title: opts.title, onClose: ok => { if (ok) { const t = sheet('<h3>Thank you</h3><p class="wcr-p">Your review was sent. It appears here once the WholeClass team approves it.</p><button class="wcr-go" id="x">Done</button>'); t.q('#x').onclick = t.close; } } });
    return d;
  }

  // 4. Completion cross-sell: Season 1 with its reviews and a free Episode 1
  async function crossSell(){
    const s = sheet('<p class="wcr-k">What’s next</p><h3>Members who finished the Discovery Class went on to Season 1: The Missing Fit</h3>' +
      '<p class="wcr-p">Real situations, read by C.P. Parker, that show how holes shape the way we love, argue and choose. Episode 1 is free.</p>' +
      '<a class="wcr-go gold" style="text-align:center;text-decoration:none;box-sizing:border-box" href="listen.html?s=1&ep=1">▶ Play Episode 1 free</a><div id="wcrRev"></div>' +
      '<a class="wcr-skip" style="text-align:center;text-decoration:none;box-sizing:border-box" href="listen.html?s=1">See all Season 1 episodes</a><button class="wcr-skip" id="wcrX">Close</button>');
    s.q('#wcrX').onclick = s.close;
    summary(s.q('#wcrRev'), 'series', 1, { signedIn: true });
  }

  // 6. Private feedback
  function feedback(page){
    const s = sheet('<p class="wcr-k">Tell us how to improve</p><h3>What would make WholeClass better for you?</h3><p class="wcr-p">This goes privately to the WholeClass team. It is never posted.</p>' +
      '<textarea class="wcr-ta" id="wcrF" maxlength="3000" placeholder="An idea, something confusing, a bug, anything" style="min-height:120px"></textarea>' +
      '<button class="wcr-go" id="wcrGo">Send to the team</button><div id="wcrM"></div><button class="wcr-skip" id="wcrX">Cancel</button>');
    s.q('#wcrX').onclick = s.close;
    s.q('#wcrGo').onclick = async () => {
      const b = s.q('#wcrGo'), t = s.q('#wcrF').value.trim();
      if (t.length < 3) return msg(s.q('#wcrM'), 'Tell us a little more.');
      b.disabled = true;
      try { await WC.rpc('send_feedback', { p_message: t, p_page: page || location.pathname }); msg(s.q('#wcrM'), 'Thank you. The WholeClass team reads every note.', true); s.q('#wcrX').textContent = 'Close'; s.q('#wcrF').disabled = true; }
      catch (e) { b.disabled = false; msg(s.q('#wcrM'), errMsg(e)); }
    };
  }

  return { HOLES, checkin, reviewForm, summary, crossSell, feedback, card, wireHelp, starsText, esc, errMsg, ensureCss };
})();
