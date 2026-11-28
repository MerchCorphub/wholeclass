// WholeClass: keeps the phone screen from going to sleep while something is playing.
// Uses the Screen Wake Lock API (Android Chrome, iPhone iOS 16.4+ in Safari, iOS 18.4+ for home-screen apps).
// Members can turn it off; the choice is remembered on the device.
window.WCAwake = (function(){
  const KEY = 'wc-keep-awake';
  const supported = 'wakeLock' in navigator;
  let lock = null, wanted = false;
  const enabled = () => { try { return localStorage.getItem(KEY) !== '0'; } catch (e) { return true; } };
  async function grab(){
    if (!supported || !wanted || !enabled() || lock || document.visibilityState !== 'visible') return;
    try { lock = await navigator.wakeLock.request('screen'); lock.addEventListener('release', () => { lock = null; }); } catch (e) { lock = null; }
  }
  function drop(){ if (lock) { try { lock.release(); } catch (e) {} lock = null; } }
  // the system releases the lock when the page is hidden; take it back when the member returns
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') grab(); });
  const isIPhoneHomeApp = /iPhone|iPad|iPod/.test(navigator.userAgent) && (navigator.standalone === true || matchMedia('(display-mode: standalone)').matches);
  return {
    supported, isIPhoneHomeApp,
    enabled,
    setEnabled(v){ try { localStorage.setItem(KEY, v ? '1' : '0'); } catch (e) {} v ? grab() : drop(); },
    on(){ wanted = true; grab(); },
    off(){ wanted = false; drop(); },
  };
})();
