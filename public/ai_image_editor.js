(() => {
  'use strict';
  const el = id => document.getElementById(id);
  let assetId, current, timer, generation = 0, busy = false;
  const money = v => v == null ? 'Non disponibile' : '$' + Number(v).toFixed(6);
  async function api(path, method = 'GET', data) {
    const r = await fetch(path, {method, body: data, headers: {'Accept': 'application/json'}});
    const result = await r.json();
    if (!r.ok) throw new Error(result.error || 'Operazione non completata');
    return result;
  }
  const base = () => `/assets/${assetId}/ai-edits`;
  function error(e) { el('aiError').textContent = e.message; el('aiError').classList.remove('d-none'); }
  function controls() {
    const ready = current?.status === 'ready';
    const ratioChanged = current?.result_width && Math.abs((current.result_width / current.result_height) / (current.width / current.height) - 1) > .01;
    el('aiAspect').classList.toggle('d-none', !ready || !ratioChanged);
    el('aiAccept').disabled = busy || !ready || (ratioChanged && !el('aiAllowAspect').checked);
    el('aiDiscard').disabled = busy || !ready;
    el('aiGenerate').disabled = busy || ['queued', 'processing'].includes(current?.status);
    el('aiHistory').disabled = busy;
    el('aiBackground').disabled = busy || ['queued', 'processing'].includes(current?.status);
  }
  function render(edit) {
    current = edit;
    const labels = {queued:'In coda…', processing:'Miglioramento in corso. Puoi chiudere il modal e tornare più tardi.', ready:'Risultato pronto: confronta prima di accettare.', accepted:'Versione AI accettata. Reset recupera il file originale.', discarded:'Proposta scartata: file operativo invariato.', failed:'Elaborazione non riuscita.'};
    el('aiStatus').textContent = labels[edit.status] || '';
    el('aiBefore').src = el('aiWipeBefore').src = edit.source_url;
    if (edit.result_width) el('aiAfter').src = el('aiWipeAfter').src = edit.result_url;
    else { el('aiAfter').removeAttribute('src'); el('aiWipeAfter').removeAttribute('src'); }
    el('aiCost').textContent = `Costo elaborazione: ${money(edit.cost_usd)} USD`;
    el('aiSize').textContent = `${edit.width}×${edit.height} px · ${Number(edit.dpi).toFixed(1)} DPI` + (edit.result_width ? ` | AI: ${edit.result_width}×${edit.result_height} px` : '');
    if (edit.error) error(new Error(edit.error));
    controls();
  }
  async function poll(editId, epoch) {
    if (epoch !== generation) return;
    try {
      const edit = await api(`${base()}/${editId}`);
      if (epoch !== generation) return;
      render(edit);
      if (['queued','processing'].includes(edit.status)) timer = setTimeout(() => poll(editId, epoch), 2500);
    } catch (e) { if (epoch === generation) error(e); }
  }
  async function open(id) {
    assetId = id; current = null; busy = false;
    clearTimeout(timer); const epoch = ++generation;
    el('aiError').classList.add('d-none'); el('aiAllowAspect').checked = false;
    el('aiStatus').textContent = 'Caricamento…'; el('aiCost').textContent = 'Costo: —';
    el('aiBefore').src = `/file/${id}?v=${Date.now()}`; el('aiAfter').removeAttribute('src');
    el('aiOverlay').checked = false; el('aiOverlay').dispatchEvent(new Event('change'));
    el('aiSize').textContent = ''; controls();
    bootstrap.Modal.getOrCreateInstance(el('aiImageModal')).show();
    try {
      const data = await api(base()); if (epoch !== generation) return;
      el('aiHistory').replaceChildren(...data.edits.map(e => { const o = document.createElement('option'); o.value = e.id; o.textContent = `#${e.id} · ${new Date(e.created_at).toLocaleString()} · ${money(e.cost_usd)}`; return o; }));
      if (data.edits.length) { render(data.edits[0]); poll(data.edits[0].id, epoch); }
      else el('aiStatus').textContent = 'Genera una proposta con le istruzioni salvate nelle impostazioni.';
      if (!data.configured) { el('aiGenerate').disabled = true; el('aiStatus').textContent = 'Configura una chiave API nelle impostazioni per iniziare.'; }
    } catch(e) {error(e);}
  }
  document.querySelectorAll('.btn-ai-image').forEach(b => b.addEventListener('click', () => open(b.dataset.assetId)));
  el('aiImageModal').addEventListener('hidden.bs.modal', () => { ++generation; clearTimeout(timer); });
  el('aiHistory').addEventListener('change', () => {clearTimeout(timer); el('aiError').classList.add('d-none'); el('aiAllowAspect').checked = false; poll(el('aiHistory').value, ++generation);});
  el('aiGenerate').addEventListener('click', async () => {
    busy = true; controls(); el('aiError').classList.add('d-none');
    const epoch = ++generation; clearTimeout(timer);
    try {const form = new FormData();form.set('background', el('aiBackground').value);const edit = await api(base(), 'POST', form); if(epoch !== generation)return; const o = document.createElement('option'); o.value=edit.id;o.textContent=`#${edit.id} · nuova elaborazione`;el('aiHistory').prepend(o);el('aiHistory').value=edit.id;el('aiAllowAspect').checked=false;render(edit);poll(edit.id,epoch);}
    catch(e){if(epoch===generation)error(e);} finally{if(epoch===generation){busy=false;controls();}}
  });
  el('aiAccept').addEventListener('click', async () => {
    busy=true;controls(); const endpoint = `${base()}/${current.id}/accept`;
    try {const form = new FormData();form.set('allow_aspect_change',el('aiAllowAspect').checked?'1':'0');await api(endpoint,'POST',form);location.reload();}
    catch(e){error(e);busy=false;controls();}
  });
  el('aiDiscard').addEventListener('click', async () => {
    busy=true;controls();try{render(await api(`${base()}/${current.id}/discard`,'POST'));}catch(e){error(e);}finally{busy=false;controls();}
  });
  el('aiAllowAspect').addEventListener('change', controls);
  el('aiOverlay').addEventListener('change', () => {el('aiCompare').classList.toggle('d-none',el('aiOverlay').checked);el('aiWipeBox').classList.toggle('d-none',!el('aiOverlay').checked);});
  el('aiWipe').addEventListener('input', () => {el('aiWipeAfter').style.clipPath=`inset(0 ${100-el('aiWipe').value}% 0 0)`;});
  el('aiZoom').addEventListener('input', () => {const width=`${Number(el('aiZoom').value)*100}%`;el('aiBefore').style.width=width;el('aiAfter').style.width=width;el('aiWipeStage').style.width=width;});
  const panes = [...el('aiCompare').querySelectorAll('.ai-image-scroll')];
  panes.forEach((pane,i) => pane.addEventListener('scroll', () => {const other=panes[1-i]; if(Math.abs(other.scrollLeft-pane.scrollLeft)>1)other.scrollLeft=pane.scrollLeft;if(Math.abs(other.scrollTop-pane.scrollTop)>1)other.scrollTop=pane.scrollTop;}));
})();
