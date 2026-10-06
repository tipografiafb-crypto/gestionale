(() => {
  let timer, busy = false, changed = false;
  const emailInput = () => document.querySelector('#billing_email, #email, input[autocomplete="email"]');
  const requiresConsent = () => {
    if (typeof wosCapture === 'undefined' || !wosCapture) return false;
    const rc = wosCapture.requiresConsent;
    return rc === true || rc === 'yes' || rc === '1' || rc === 1;
  };
  function mount() {
    const input = emailInput();
    if (!input) return;
    if (!input.dataset.wosBound) {
      input.dataset.wosBound = '1';
      input.addEventListener('input', schedule);
      input.addEventListener('change', schedule);
    }
    const existing = document.getElementById('wos-email-consent');
    if (!requiresConsent()) {
      if (existing) {
        (document.getElementById('wos-email-consent-label') || existing.closest('label') || existing).remove();
      }
      return;
    }
    if (existing) return;
    const label = document.createElement('label');
    label.id = 'wos-email-consent-label';
    label.style.cssText = 'display:block;font-size:13px;margin:12px 0';
    const checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    checkbox.id = 'wos-email-consent';
    checkbox.addEventListener('change', schedule);
    label.append(checkbox, document.createTextNode(` ${wosCapture?.notice || ''}`));
    const container = input.closest('.form-row, .wc-block-components-text-input');
    if (container) {
      container.after(label);
    } else {
      input.after(label);
    }
  }
  function schedule() { changed = true; clearTimeout(timer); timer = setTimeout(capture, 1200); }
  async function capture() {
    const input = emailInput();
    if (busy || !input || !input.value || !input.checkValidity()) return;
    busy = true;
    try {
      const consentGiven = !requiresConsent() || !!document.getElementById('wos-email-consent')?.checked;
      const data = new URLSearchParams({
        nonce: wosCapture?.nonce || '',
        email: input.value,
        consent: consentGiven ? 'yes' : 'no'
      });
      const response = await fetch(wosCapture?.url || '', {method: 'POST', credentials: 'same-origin', body: data});
      if (response.ok) changed = false;
    } catch (_) { /* The next interaction retries without blocking checkout. */ }
    finally { busy = false; }
  }
  new MutationObserver(mount).observe(document.body, {childList: true, subtree: true});
  document.addEventListener('input', () => { changed = true; });
  // Activity keeps a checkout alive; an idle open tab does not prevent abandonment.
  setInterval(() => { if (changed && !document.hidden) capture(); }, 30000);
  mount();
})();

