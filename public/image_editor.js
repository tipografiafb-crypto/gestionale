import { Canvas, FabricImage, Rect } from '/vendor/fabric/fabric-7.4.0.min.mjs';

const modalElement = document.getElementById('imageAdjustModal');

if (modalElement) {
  const elements = {
    canvas: document.getElementById('adjustCanvas'),
    stage: document.getElementById('imageEditorStage'),
    loading: document.getElementById('imageEditorLoading'),
    error: document.getElementById('imageEditorError'),
    sourceSize: document.getElementById('imageEditorSourceSize'),
    outputSize: document.getElementById('imageEditorOutputSize'),
    printSize: document.getElementById('imageEditorPrintSize'),
    dpi: document.getElementById('imageEditorDpi'),
    cropControls: document.getElementById('imageCropControls'),
    modeHelp: document.getElementById('imageEditorModeHelp'),
    zoomSlider: document.getElementById('zoomSlider'),
    zoomInput: document.getElementById('zoomInput'),
    offsetX: document.getElementById('offsetXInput'),
    offsetY: document.getElementById('offsetYInput'),
    outputWidthMm: document.getElementById('outputWidthMm'),
    outputHeightMm: document.getElementById('outputHeightMm'),
    center: document.getElementById('centerImageBtn'),
    reset: document.getElementById('resetOffsetBtn'),
    editCrop: document.getElementById('editCropBtn'),
    editImage: document.getElementById('editImageBtn'),
    detection: document.getElementById('cropDetectionMode'),
    margin: document.getElementById('cropMarginMm'),
    cropX: document.getElementById('cropXInput'),
    cropY: document.getElementById('cropYInput'),
    cropWidth: document.getElementById('cropWidthInput'),
    cropHeight: document.getElementById('cropHeightInput'),
    autoCrop: document.getElementById('autoCropBtn'),
    save: document.getElementById('saveAdjustedImageBtn')
  };

  const state = {
    assetId: null,
    width: 0,
    height: 0,
    dpi: 300,
    mode: 'fixed',
    outputRatio: 1,
    outputScale: 1,
    canvas: null,
    image: null,
    crop: null,
    modal: bootstrap.Modal.getOrCreateInstance(modalElement),
    loading: false
  };

  const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
  const rounded = (value) => Math.round(Number(value) || 0);

  function showError(message = '') {
    elements.error.textContent = message;
    elements.error.classList.toggle('d-none', !message);
  }

  function setLoading(loading, message = 'Caricamento immagine…') {
    state.loading = loading;
    elements.loading.innerHTML = loading
      ? `<span class="spinner-border spinner-border-sm"></span> ${message}`
      : '';
    elements.loading.classList.toggle('d-none', !loading);
    elements.save.disabled = loading;
  }

  function sourceCenter() {
    return { x: state.width / 2, y: state.height / 2 };
  }

  function imageOffset() {
    const center = sourceCenter();
    return {
      x: rounded(state.image.left - center.x),
      y: rounded(state.image.top - center.y)
    };
  }

  function cropBounds() {
    if (!state.crop || state.mode !== 'crop') {
      return { x: 0, y: 0, width: state.width, height: state.height };
    }
    const bounds = state.crop.getBoundingRect();
    const x = clamp(rounded(bounds.left), 0, state.width - 1);
    const y = clamp(rounded(bounds.top), 0, state.height - 1);
    const width = clamp(rounded(bounds.width), 1, state.width - x);
    const height = clamp(rounded(bounds.height), 1, state.height - y);
    return { x, y, width, height };
  }

  function printDimensions(width, height) {
    return {
      width: width / state.dpi * 2.54,
      height: height / state.dpi * 2.54
    };
  }

  function requestedOutputDimensions(bounds) {
    const widthMm = Number(elements.outputWidthMm?.value);
    const heightMm = Number(elements.outputHeightMm?.value);
    const width = Number.isFinite(widthMm) && widthMm > 0
      ? Math.max(1, Math.round(widthMm / 25.4 * state.dpi)) : bounds.width;
    const height = Number.isFinite(heightMm) && heightMm > 0
      ? Math.max(1, Math.round(heightMm / 25.4 * state.dpi)) : bounds.height;
    return { width, height };
  }

  function syncOutputFields(bounds) {
    if (!elements.outputWidthMm || !elements.outputHeightMm) return;
    state.outputRatio = bounds.width / Math.max(bounds.height, 1);
    state.outputScale = 1;
    syncOutputFromBounds(bounds);
  }

  function syncOutputFromBounds(bounds) {
    if (!elements.outputWidthMm || !elements.outputHeightMm) return;
    elements.outputWidthMm.value = (bounds.width * state.outputScale / state.dpi * 25.4).toFixed(2);
    elements.outputHeightMm.value = (bounds.height * state.outputScale / state.dpi * 25.4).toFixed(2);
  }

  function applyOutputWidth() {
    const width = Number(elements.outputWidthMm.value);
    if (!Number.isFinite(width) || width <= 0 || !state.outputRatio) return;
    const bounds = cropBounds();
    state.outputScale = (width / 25.4 * state.dpi) / Math.max(bounds.width, 1);
    elements.outputHeightMm.value = (width / state.outputRatio).toFixed(2);
    updateReadout();
  }

  function applyOutputHeight() {
    const height = Number(elements.outputHeightMm.value);
    if (!Number.isFinite(height) || height <= 0 || !state.outputRatio) return;
    const bounds = cropBounds();
    state.outputScale = (height / 25.4 * state.dpi) / Math.max(bounds.height, 1);
    elements.outputWidthMm.value = (height * state.outputRatio).toFixed(2);
    updateReadout();
  }

  function updateReadout() {
    if (!state.image) return;
    const offset = imageOffset();
    const bounds = cropBounds();
    const print = printDimensions(bounds.width, bounds.height);
    const scale = state.image.scaleX || 1;

    elements.zoomSlider.value = scale;
    elements.zoomInput.value = Math.round(scale * 100);
    elements.offsetX.value = offset.x;
    elements.offsetY.value = offset.y;
    elements.sourceSize.textContent = `${state.width} × ${state.height} px`;
    const output = requestedOutputDimensions(bounds);
    const outputPrint = printDimensions(output.width, output.height);
    elements.outputSize.textContent = `${output.width} × ${output.height} px`;
    elements.printSize.textContent = `${outputPrint.width.toFixed(2)} × ${outputPrint.height.toFixed(2)} cm`;
    if (state.mode === 'crop') {
      state.outputRatio = bounds.width / Math.max(bounds.height, 1);
      syncOutputFromBounds(bounds);
    }
    elements.dpi.textContent = `${Math.round(state.dpi)} DPI`;
    if (state.crop && elements.cropX && state.mode === 'crop') {
      elements.cropX.value = bounds.x;
      elements.cropY.value = bounds.y;
      elements.cropWidth.value = bounds.width;
      elements.cropHeight.value = bounds.height;
    }
  }

  function fitCanvasToStage() {
    if (!state.canvas || !state.width || !state.height) return;
    const availableWidth = Math.max(280, elements.stage.clientWidth - 28);
    const availableHeight = Math.max(280, Math.min(window.innerHeight * 0.62, 650));
    const ratio = Math.min(1, availableWidth / state.width, availableHeight / state.height);
    state.canvas.setDimensions(
      { width: Math.round(state.width * ratio), height: Math.round(state.height * ratio) },
      { cssOnly: true }
    );
    state.canvas.calcOffset();
  }

  function makeImageInteractive(interactive) {
    if (!state.image) return;
    state.image.set({ selectable: interactive, evented: interactive });
    if (interactive) state.canvas.setActiveObject(state.image);
  }

  function makeCropInteractive(interactive) {
    if (!state.crop) return;
    state.crop.set({ selectable: interactive, evented: interactive });
    if (interactive) state.canvas.setActiveObject(state.crop);
  }

  function editTarget(target) {
    if (state.mode !== 'crop') return;
    const cropActive = target === 'crop';
    makeCropInteractive(cropActive);
    makeImageInteractive(!cropActive);
    elements.editCrop.className = `btn btn-sm ${cropActive ? 'btn-primary' : 'btn-outline-primary'}`;
    elements.editImage.className = `btn btn-sm ${cropActive ? 'btn-outline-primary' : 'btn-primary'}`;
    state.canvas.requestRenderAll();
  }

  function ensureCrop(recipe = null) {
    if (state.crop) return;
    const saved = recipe?.crop || {};
    const insetX = Math.round(state.width * 0.08);
    const insetY = Math.round(state.height * 0.08);
    const x = Number.isFinite(Number(saved.x)) ? Number(saved.x) : insetX;
    const y = Number.isFinite(Number(saved.y)) ? Number(saved.y) : insetY;
    const width = Number.isFinite(Number(saved.width)) ? Number(saved.width) : state.width - insetX * 2;
    const height = Number.isFinite(Number(saved.height)) ? Number(saved.height) : state.height - insetY * 2;

    state.crop = new Rect({
      left: clamp(x, 0, state.width - 1),
      top: clamp(y, 0, state.height - 1),
      width: clamp(width, 1, state.width - x),
      height: clamp(height, 1, state.height - y),
      originX: 'left',
      originY: 'top',
      fill: 'rgba(13, 110, 253, 0.04)',
      stroke: '#0d6efd',
      strokeWidth: 5,
      strokeDashArray: [16, 8],
      strokeUniform: true,
      transparentCorners: false,
      cornerColor: '#00e5ff',
      cornerStrokeColor: '#082f49',
      // Large, high-contrast handles: the canvas is often displayed scaled
      // down, so the default Fabric hit area is too hard to grab precisely.
      cornerSize: 36,
      touchCornerSize: 48,
      padding: 6,
      shadow: { color: 'rgba(0, 0, 0, 0.85)', blur: 4, offsetX: 0, offsetY: 0 },
      lockRotation: true,
      hasRotatingPoint: false
    });
    state.crop.setControlsVisibility({ mtr: false });
    state.canvas.add(state.crop);
  }

  function normalizeCropObject() {
    if (!state.crop) return;
    const bounds = state.crop.getBoundingRect();
    let width = clamp(Math.round(bounds.width), 1, state.width);
    let height = clamp(Math.round(bounds.height), 1, state.height);
    let left = clamp(Math.round(bounds.left), 0, state.width - width);
    let top = clamp(Math.round(bounds.top), 0, state.height - height);
    if (left + width > state.width) width = state.width - left;
    if (top + height > state.height) height = state.height - top;
    state.crop.set({ left, top, width, height, scaleX: 1, scaleY: 1 });
    state.crop.setCoords();
  }

  function setMode(mode, recipe = null) {
    state.mode = mode === 'crop' ? 'crop' : 'fixed';
    document.getElementById(`imageEditMode${state.mode === 'crop' ? 'Crop' : 'Fixed'}`).checked = true;
    elements.cropControls.classList.toggle('d-none', state.mode !== 'crop');
    elements.modeHelp.textContent = state.mode === 'fixed'
      ? 'L’uscita manterrà esattamente larghezza e altezza originali.'
      : 'Il rettangolo blu diventerà il nuovo formato del file.';

    if (state.mode === 'crop') {
      ensureCrop(recipe);
      state.crop.visible = true;
      editTarget('crop');
    } else {
      if (state.crop) state.crop.visible = false;
      makeImageInteractive(true);
    }
    syncOutputFields(cropBounds());
    state.canvas.requestRenderAll();
    updateReadout();
  }

  function applyImageTransform({ scale, left, top }) {
    const safeScale = clamp(Number(scale) || 1, 0.05, 10);
    state.image.set({
      scaleX: safeScale,
      scaleY: safeScale,
      left: Number.isFinite(Number(left)) ? Number(left) : state.width / 2,
      top: Number.isFinite(Number(top)) ? Number(top) : state.height / 2
    });
    state.image.setCoords();
    state.canvas.requestRenderAll();
    updateReadout();
  }

  function resetEditor() {
    applyImageTransform({ scale: 1, left: state.width / 2, top: state.height / 2 });
    if (state.crop) {
      state.canvas.remove(state.crop);
      state.crop = null;
    }
    if (state.mode === 'crop') {
      ensureCrop();
      editTarget('crop');
    }
    state.canvas.requestRenderAll();
    updateReadout();
  }

  function centerImage() {
    const target = state.mode === 'crop' ? cropBounds() : { x: 0, y: 0, width: state.width, height: state.height };
    state.image.set({ left: target.x + target.width / 2, top: target.y + target.height / 2 });
    state.image.setCoords();
    state.canvas.requestRenderAll();
    updateReadout();
  }

  function contentBounds(mode) {
    const source = state.image.getElement();
    const analysis = document.createElement('canvas');
    analysis.width = state.width;
    analysis.height = state.height;
    const context = analysis.getContext('2d', { willReadFrequently: true });
    context.drawImage(source, 0, 0, state.width, state.height);
    const pixels = context.getImageData(0, 0, state.width, state.height).data;
    const whiteThreshold = 248;
    let minX = state.width;
    let minY = state.height;
    let maxX = -1;
    let maxY = -1;

    for (let y = 0; y < state.height; y += 1) {
      for (let x = 0; x < state.width; x += 1) {
        const index = (y * state.width + x) * 4;
        const alpha = pixels[index + 3];
        const visible = mode === 'white'
          ? alpha > 8 && !(pixels[index] >= whiteThreshold && pixels[index + 1] >= whiteThreshold && pixels[index + 2] >= whiteThreshold)
          : alpha > 8;
        if (!visible) continue;
        minX = Math.min(minX, x);
        minY = Math.min(minY, y);
        maxX = Math.max(maxX, x);
        maxY = Math.max(maxY, y);
      }
    }

    if (maxX < minX || maxY < minY) throw new Error('Non è stato trovato alcun contenuto da ritagliare.');
    return { x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1 };
  }

  function autoCrop() {
    if (!state.image || !state.crop) return;
    showError('');
    elements.autoCrop.disabled = true;
    elements.autoCrop.innerHTML = '<span class="spinner-border spinner-border-sm"></span> Analisi…';
    window.setTimeout(() => {
      try {
        const content = contentBounds(elements.detection.value);
        const scale = state.image.scaleX || 1;
        const imageLeft = state.image.left - state.width * scale / 2;
        const imageTop = state.image.top - state.height * scale / 2;
        const marginPx = Math.max(0, Number(elements.margin.value) || 0) / 25.4 * state.dpi;
        let left = imageLeft + content.x * scale - marginPx;
        let top = imageTop + content.y * scale - marginPx;
        let width = content.width * scale + marginPx * 2;
        let height = content.height * scale + marginPx * 2;
        left = clamp(Math.floor(left), 0, state.width - 1);
        top = clamp(Math.floor(top), 0, state.height - 1);
        width = clamp(Math.ceil(width), 1, state.width - left);
        height = clamp(Math.ceil(height), 1, state.height - top);
        state.crop.set({ left, top, width, height, scaleX: 1, scaleY: 1 });
        state.crop.setCoords();
        editTarget('crop');
        updateReadout();
      } catch (error) {
        showError(error.message);
      } finally {
        elements.autoCrop.disabled = false;
        elements.autoCrop.innerHTML = '<i class="fas fa-magic"></i> Automatico';
      }
    }, 20);
  }

  async function disposeCanvas() {
    if (!state.canvas) return;
    await state.canvas.dispose();
    state.canvas = null;
    state.image = null;
    state.crop = null;
  }

  async function openEditor(assetId) {
    showError('');
    setLoading(true);
    state.assetId = assetId;
    state.modal.show();

    try {
      const response = await fetch(`/assets/${assetId}/edit-state`, { headers: { Accept: 'application/json' } });
      const payload = await response.json();
      if (!response.ok || !payload.success) throw new Error(payload.error || 'Impossibile aprire l’editor');

      await disposeCanvas();
      state.width = Number(payload.source_width);
      state.height = Number(payload.source_height);
      state.dpi = Number(payload.dpi) || 300;
      const saved = payload.edit_data || {};

      state.canvas = new Canvas(elements.canvas, {
        width: state.width,
        height: state.height,
        preserveObjectStacking: true,
        selection: false,
        backgroundColor: 'rgba(0,0,0,0)'
      });
      state.image = await FabricImage.fromURL(payload.source_url, { crossOrigin: 'anonymous' });
      state.image.set({
        originX: 'center',
        originY: 'center',
        left: Number(saved.image_left) || state.width / 2,
        top: Number(saved.image_top) || state.height / 2,
        scaleX: Number(saved.scale) || 1,
        scaleY: Number(saved.scale) || 1,
        lockRotation: true,
        centeredScaling: true,
        transparentCorners: false,
        cornerColor: '#ffffff',
        cornerStrokeColor: '#0d6efd',
        borderColor: '#0d6efd',
        cornerSize: 18
      });
      state.image.setControlsVisibility({ mt: false, mb: false, ml: false, mr: false, mtr: false });
      state.canvas.add(state.image);

      state.canvas.on('object:moving', updateReadout);
      state.canvas.on('object:scaling', updateReadout);
      state.canvas.on('object:modified', (event) => {
        if (event.target === state.crop) normalizeCropObject();
        if (event.target === state.image) {
          const scale = clamp(state.image.scaleX || 1, 0.05, 10);
          state.image.set({ scaleX: scale, scaleY: scale });
        }
        updateReadout();
      });

      fitCanvasToStage();
      setMode(saved.mode || 'fixed', saved);
      updateReadout();
      setLoading(false);
    } catch (error) {
      setLoading(false);
      showError(error.message);
    }
  }

  const crcTable = (() => {
    const table = new Uint32Array(256);
    for (let n = 0; n < 256; n += 1) {
      let value = n;
      for (let k = 0; k < 8; k += 1) value = (value & 1) ? (0xEDB88320 ^ (value >>> 1)) : (value >>> 1);
      table[n] = value;
    }
    return table;
  })();

  function crc32(buffer) {
    let value = 0xFFFFFFFF;
    for (let index = 0; index < buffer.length; index += 1) {
      value = crcTable[(value ^ buffer[index]) & 0xFF] ^ (value >>> 8);
    }
    return (value ^ 0xFFFFFFFF) >>> 0;
  }

  function pngWithDpi(dataUrl, dpi) {
    const binary = atob(dataUrl.split(',')[1]);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
    const pixelsPerMeter = Math.round(dpi / 0.0254);
    const chunk = new Uint8Array(21);
    const view = new DataView(chunk.buffer);
    view.setUint32(0, 9);
    chunk.set([0x70, 0x48, 0x59, 0x73], 4);
    view.setUint32(8, pixelsPerMeter);
    view.setUint32(12, pixelsPerMeter);
    chunk[16] = 1;
    view.setUint32(17, crc32(chunk.subarray(4, 17)));
    const output = new Uint8Array(bytes.length + chunk.length);
    output.set(bytes.subarray(0, 33), 0);
    output.set(chunk, 33);
    output.set(bytes.subarray(33), 54);
    let encoded = '';
    const block = 0x8000;
    for (let index = 0; index < output.length; index += block) {
      encoded += String.fromCharCode.apply(null, output.subarray(index, Math.min(index + block, output.length)));
    }
    return `data:image/png;base64,${btoa(encoded)}`;
  }

  async function saveImage() {
    if (!state.canvas || !state.image || state.loading) return;
    showError('');
    setLoading(true, 'Preparazione PNG…');
    elements.save.innerHTML = '<span class="spinner-border spinner-border-sm"></span> Salvataggio…';

    try {
      const bounds = cropBounds();
      const cropWasVisible = state.crop?.visible;
      state.canvas.discardActiveObject();
      if (state.crop) state.crop.visible = false;
      state.canvas.requestRenderAll();

      let imageData = state.canvas.toDataURL({
        format: 'png',
        left: bounds.x,
        top: bounds.y,
        width: bounds.width,
        height: bounds.height,
        multiplier: 1,
        enableRetinaScaling: false
      });
      const outputDimensions = requestedOutputDimensions(bounds);
      imageData = pngWithDpi(imageData, state.dpi);

      if (state.crop) state.crop.visible = cropWasVisible;
      state.canvas.requestRenderAll();

      const offset = imageOffset();
      const recipe = {
        mode: state.mode,
        source_width: state.width,
        source_height: state.height,
        image_left: state.image.left,
        image_top: state.image.top,
        scale: state.image.scaleX,
        offset_x: offset.x,
        offset_y: offset.y,
        dpi: state.dpi,
        output_width: outputDimensions.width,
        output_height: outputDimensions.height,
        crop: state.mode === 'crop' ? bounds : null
      };

      setLoading(true, 'Invio al gestionale…');
      const response = await fetch(`/assets/${state.assetId}/adjust`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({ image_data: imageData, recipe, apply_to_group: true })
      });
      const payload = await response.json();
      if (!response.ok || !payload.success) throw new Error(payload.error || 'Salvataggio fallito');

      state.modal.hide();
      window.location.reload();
    } catch (error) {
      showError(error.message);
      setLoading(false);
      elements.save.disabled = false;
    } finally {
      elements.save.innerHTML = '<i class="fas fa-save"></i> Salva immagine';
    }
  }

  document.querySelectorAll('.btn-adjust-image').forEach((button) => {
    button.addEventListener('click', () => openEditor(button.dataset.assetId));
  });
  document.querySelectorAll('input[name="imageEditMode"]').forEach((input) => {
    input.addEventListener('change', () => setMode(input.value));
  });
  elements.zoomSlider.addEventListener('input', () => applyImageTransform({
    scale: elements.zoomSlider.value,
    left: state.image.left,
    top: state.image.top
  }));
  const applyZoomInput = () => applyImageTransform({
    scale: Number(elements.zoomInput.value) / 100,
    left: state.image.left,
    top: state.image.top
  });
  const applyOffsetXInput = () => applyImageTransform({
    scale: state.image.scaleX,
    left: state.width / 2 + Number(elements.offsetX.value || 0),
    top: state.image.top
  });
  const applyOffsetYInput = () => applyImageTransform({
    scale: state.image.scaleX,
    left: state.image.left,
    top: state.height / 2 + Number(elements.offsetY.value || 0)
  });
  const applyCropNumeric = () => {
    if (!state.crop || state.mode !== 'crop') return;
    const width = clamp(rounded(elements.cropWidth.value), 1, state.width);
    const height = clamp(rounded(elements.cropHeight.value), 1, state.height);
    const left = clamp(rounded(elements.cropX.value), 0, state.width - width);
    const top = clamp(rounded(elements.cropY.value), 0, state.height - height);
    state.crop.set({ left, top, width, height, scaleX: 1, scaleY: 1 });
    state.crop.setCoords();
    state.canvas.requestRenderAll();
    updateReadout();
  };
  elements.zoomInput.addEventListener('input', applyZoomInput);
  elements.zoomInput.addEventListener('change', applyZoomInput);
  elements.offsetX.addEventListener('input', applyOffsetXInput);
  elements.offsetX.addEventListener('change', applyOffsetXInput);
  elements.offsetY.addEventListener('input', applyOffsetYInput);
  elements.offsetY.addEventListener('change', applyOffsetYInput);
  [elements.cropX, elements.cropY, elements.cropWidth, elements.cropHeight].forEach((input) => {
    input.addEventListener('change', applyCropNumeric);
  });
  // Recalculate only after the operator finishes typing. Updating on every
  // keystroke reformatted values such as "20" into "2.00" mid-entry.
  elements.outputWidthMm.addEventListener('change', applyOutputWidth);
  elements.outputHeightMm.addEventListener('change', applyOutputHeight);
  elements.center.addEventListener('click', centerImage);
  elements.reset.addEventListener('click', resetEditor);
  elements.editCrop.addEventListener('click', () => editTarget('crop'));
  elements.editImage.addEventListener('click', () => editTarget('image'));
  elements.autoCrop.addEventListener('click', autoCrop);
  elements.save.addEventListener('click', saveImage);
  window.addEventListener('resize', fitCanvasToStage);
  modalElement.addEventListener('hidden.bs.modal', () => {
    showError('');
    setLoading(false);
  });
}
