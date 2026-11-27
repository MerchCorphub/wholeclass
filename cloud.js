// WholeClass — connection to the WholeClass database (Supabase).
// Members only ever read and write their own rows; access and payments change only through server functions.
(function () {
  const URL_ = 'https://uiwbwiznuradpmfdeeuy.supabase.co';
  const KEY_ = 'sb_publishable_30tCXrsJgIoyAdROi6WhcQ_mV-vEz5t';
  let client = null, loading = null;

  function lib() {
    if (window.supabase && window.supabase.createClient) return Promise.resolve(window.supabase);
    if (!loading) loading = new Promise((res, rej) => {
      const s = document.createElement('script');
      s.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js';
      s.onload = () => res(window.supabase); s.onerror = rej; document.head.appendChild(s);
    });
    return loading;
  }
  async function sb() {
    if (!client) { const L = await lib(); client = L.createClient(URL_, KEY_, { auth: { persistSession: true, storageKey: 'wholeclass-auth', detectSessionInUrl: true } }); }
    return client;
  }
  const ok = r => { if (r.error) throw r.error; return r.data; };
  const here = () => location.origin + location.pathname.replace(/[^/]*$/, '');

  async function session() { const c = await sb(); return (await c.auth.getSession()).data.session; }
  async function onAuth(fn) { const c = await sb(); c.auth.onAuthStateChange((ev, s) => fn(ev, s)); }
  async function signUp(email, password, meta) {
    const c = await sb();
    const d = ok(await c.auth.signUp({ email, password, options: { data: meta || {}, emailRedirectTo: here() } }));
    return { user: d.user, session: d.session };
  }
  async function signIn(email, password) { const c = await sb(); return ok(await c.auth.signInWithPassword({ email, password })).session; }
  async function signOut() { try { const c = await sb(); await c.auth.signOut(); } catch (e) {} }
  async function resetPassword(email) { const c = await sb(); ok(await c.auth.resetPasswordForEmail(email, { redirectTo: here() + '?reset=1' })); }
  async function setPassword(pw) { const c = await sb(); ok(await c.auth.updateUser({ password: pw })); }
  async function rpc(name, args) { const c = await sb(); return ok(await c.rpc(name, args || {})); }

  async function ensureMember(meta) {
    const s = await session(); if (!s) return null;
    const m = (s.user && s.user.user_metadata) || {};
    meta = meta || {};
    return rpc('ensure_member', { p_first: meta.first || m.first || '', p_last: meta.last || m.last || '', p_faith: meta.faith || m.faith || 'biblical',
      p_adult: !!(meta.adult || m.adult), p_agreed: !!(meta.agreed || m.agreed) });
  }
  async function loadProgress() { const c = await sb(), s = await session(); return ok(await c.from('progress').select('*').eq('member_id', s.user.id).maybeSingle()); }
  async function saveProgress(p) {
    const c = await sb(), s = await session(); if (!s) return;
    ok(await c.from('progress').upsert({ member_id: s.user.id, ...p }, { onConflict: 'member_id' }));
  }
  async function saveDay(entry) {
    const c = await sb(), s = await session(); if (!s) return;
    ok(await c.from('day_entries').upsert({ member_id: s.user.id, ...entry }, { onConflict: 'member_id,day' }));
  }
  async function updateMember(patch) { const c = await sb(), s = await session(); if (!s) return; ok(await c.from('members').update(patch).eq('id', s.user.id)); }
  async function access() { return rpc('my_access'); }
  async function price() { const c = await sb(); const r = ok(await c.from('prices').select('amount').eq('kind', 'individual').maybeSingle()); return r ? Number(r.amount) : 20; }
  async function interest(course) { const c = await sb(), s = await session(); if (!s) return; ok(await c.from('course_interest').upsert({ member_id: s.user.id, course }, { onConflict: 'member_id,course' })); }

  async function pay(action, extra) {
    const c = await sb(), s = await session(); if (!s) throw new Error('Please sign in again.');
    const r = await fetch(URL_ + '/functions/v1/stripe-pay', { method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + s.access_token, apikey: KEY_ },
      body: JSON.stringify({ action, ...(extra || {}) }) });
    let d = {}; try { d = await r.json(); } catch (e) {}
    if (!r.ok) throw new Error(d.error || 'Payment could not be started.');
    return d;
  }
  async function checkout(product) { const d = await pay('checkout', product ? { product } : {}); location.href = d.url; }
  async function confirmPayment(id) { return pay('confirm', { session_id: id }); }

  window.WC = { session, onAuth, signUp, signIn, signOut, resetPassword, setPassword, ensureMember, loadProgress, saveProgress, saveDay, updateMember,
    access, price, interest, checkout, confirmPayment,
    redeemKey: code => rpc('redeem_book_key', { p_code: code }),
    joinGroup: code => rpc('join_group', { p_code: code }),
    giveSeat: to => rpc('give_seat', { p_to: to || '' }),
    acceptSeat: code => rpc('accept_seat', { p_code: code }),
    exportData: () => rpc('export_my_data'),
    bookContents: () => rpc('book_contents'),
    seriesContents: () => rpc('series_contents'),
    episodes: () => rpc('series_episode_list'),
    episodeUrl: async path => { const c = await sb(); return ok(await c.storage.from('episodes').createSignedUrl(path, 4 * 3600)).signedUrl; },
    uploadEpisode: async (path, file) => { const c = await sb(); return ok(await c.storage.from('episodes').upload(path, file, { upsert: true, contentType: file.type || 'audio/mpeg', cacheControl: '3600' })); },
    removeEpisodeFile: async path => { const c = await sb(); return ok(await c.storage.from('episodes').remove([path])); },
    lesson: async n => { const c = await sb(); return ok(await c.from('series_lessons').select('n,title,html').eq('n', n).maybeSingle()); },
    chapter: async n => { const c = await sb(); return ok(await c.from('book_chapters').select('n,title,html').eq('n', n).maybeSingle()); },
    rpc,
    eraseAnswers: () => rpc('erase_my_answers') };
})();
