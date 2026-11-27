// WholeClass service worker: caches only the app's own static files so it opens fast and offline.
// Account data from the database is never cached.
const CACHE = 'wholeclass-static-v8';
const STATIC = /\.(?:html|js|css|png|jpe?g|webp|svg|ico|json|woff2?)$/i;
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.hostname.endsWith('.supabase.co') || url.hostname.endsWith('stripe.com')) return;
  if (url.search.includes('seat=') || url.search.includes('paid=')) return;
  const isStatic = url.pathname.endsWith('/') || STATIC.test(url.pathname) || url.hostname.includes('fonts.g') || url.hostname.includes('jsdelivr.net');
  if (!isStatic) return;
  e.respondWith(fetch(req).then(res => { if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)); } return res; })
    .catch(async () => (await caches.match(req)) || (await caches.match(req, { ignoreSearch: true })) || new Response('You are offline. Check your connection and try again.', { status: 503, headers: { 'Content-Type': 'text/plain' } })));
});
