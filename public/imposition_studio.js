const root = document.getElementById('impositionStudio');

if (root) {
  const config = JSON.parse(root.dataset.config || '{}');
  config.marks ||= {};
  const elements = {
    name: document.getElementById('impositionName'),
    folder: document.getElementById('impositionFolder'),
    description: document.getElementById('impositionDescription'),
    sheet: document.getElementById('impositionSheet'),
    sheetWrap: document.getElementById('impositionSheetWrap'),
    canvas: document.getElementById('impositionCanvas'),
    printable: document.getElementById('impositionPrintableArea'),
    placements: document.getElementById('impositionPlacements'),
    marks: document.getElementById('impositionMarks'),
    summary: document.getElementById('impositionSummary'),
    warnings: document.getElementById('impositionWarnings'),
    message: document.getElementById('impositionMessage'),
    saveState: document.getElementById('impositionSaveState'),
    previewTitle: document.getElementById('impositionPreviewTitle'),
    sheetSize: document.getElementById('impositionSheetSize'),
    utilization: document.getElementById('impositionUtilization'),
    placementCount: document.getElementById('impositionPlacementCount'),
    testConfig: document.getElementById('impositionTestConfig')
  };
  const state = { zoom: 1, side: 'front', dirty: false, lastLayout: null };
  const number = (value, fallback = 0) => Number.isFinite(Number(value)) ? Number(value) : fallback;
  const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
  const svgNS = 'http://www.w3.org/2000/svg';

  function fieldValue(input) {
    if (input.type === 'checkbox') return input.checked;
    if (input.type === 'number') return number(input.value);
    return input.value;
  }

  function bindControls() {
    document.querySelectorAll('[data-field]').forEach((input) => {
      const key = input.dataset.field;
      if (input.type === 'checkbox') input.checked = Boolean(config[key]);
      else input.value = config[key] ?? '';
      input.addEventListener(input.type === 'checkbox' || input.tagName === 'SELECT' ? 'change' : 'input', () => {
        config[key] = fieldValue(input);
        markDirty();
        render();
      });
    });
    document.querySelectorAll('[data-mark]').forEach((input) => {
      const key = input.dataset.mark;
      input.checked = Boolean(config.marks[key]);
      input.addEventListener('change', () => {
        config.marks[key] = input.checked;
        markDirty();
        render();
      });
    });
    document.querySelectorAll('[data-mark-number]').forEach((input) => {
      const key = input.dataset.markNumber;
      input.value = config.marks[key] ?? 0;
      input.addEventListener('input', () => {
        config.marks[key] = number(input.value);
        markDirty();
        render();
      });
    });
    [elements.name, elements.folder, elements.description].forEach((input) => input.addEventListener('input', markDirty));
    document.querySelectorAll('[data-mode]').forEach((button) => button.addEventListener('click', () => {
      config.layout_mode = button.dataset.mode;
      if (config.layout_mode === 'nesting') {
        config.double_sided_mode = 'none';
        syncField('double_sided_mode');
      }
      markDirty();
      render();
    }));
    document.querySelectorAll('[data-sheet-side]').forEach((button) => button.addEventListener('click', () => {
      state.side = button.dataset.sheetSide;
      render();
    }));
    document.getElementById('swapSheet').addEventListener('click', () => {
      [config.sheet_width_mm, config.sheet_height_mm] = [config.sheet_height_mm, config.sheet_width_mm];
      syncField('sheet_width_mm');
      syncField('sheet_height_mm');
      markDirty();
      render();
    });
    document.getElementById('impositionZoomOut').addEventListener('click', () => setZoom(state.zoom - .15));
    document.getElementById('impositionZoomIn').addEventListener('click', () => setZoom(state.zoom + .15));
    document.getElementById('impositionZoomReset').addEventListener('click', () => setZoom(1));
    document.getElementById('impositionFit').addEventListener('click', () => setZoom(1));
    document.getElementById('saveImposition').addEventListener('click', saveDraft);
    document.getElementById('publishImpositionForm').addEventListener('submit', async (event) => {
      event.preventDefault();
      if (!(await saveDraft())) return;
      event.target.submit();
    });
    document.getElementById('impositionTestForm').addEventListener('submit', () => {
      elements.testConfig.value = JSON.stringify(config);
    });
    window.addEventListener('resize', render);
  }

  function syncField(key) {
    const input = document.querySelector(`[data-field="${key}"]`);
    if (!input) return;
    if (input.type === 'checkbox') input.checked = Boolean(config[key]);
    else input.value = config[key];
  }

  function markDirty() {
    state.dirty = true;
    elements.saveState.classList.remove('saved');
    elements.saveState.textContent = 'Modifiche non salvate';
  }

  function setZoom(value) {
    state.zoom = clamp(value, .35, 2.5);
    document.getElementById('impositionZoomReset').textContent = `${Math.round(state.zoom * 100)}%`;
    render();
  }

  function dimensions() {
    return {
      sheetWidth: Math.max(1, number(config.sheet_width_mm, 320)),
      sheetHeight: Math.max(1, number(config.sheet_height_mm, 450)),
      itemWidth: Math.max(1, number(config.sample_width_mm, 90)),
      itemHeight: Math.max(1, number(config.sample_height_mm, 50)),
      marginLeft: Math.max(0, number(config.margin_left_mm, 0)),
      marginRight: Math.max(0, number(config.margin_right_mm, 0)),
      marginTop: Math.max(0, number(config.margin_top_mm, 0)),
      marginBottom: Math.max(0, number(config.margin_bottom_mm, 0)),
      gapX: Math.max(0, number(config.gap_x_mm, 0)),
      gapY: Math.max(0, number(config.gap_y_mm, 0)),
      bleed: config.bleed_mode === 'scale' ? Math.max(0, number(config.bleed_mm, 0)) : 0
    };
  }

  function gridLayout(dims) {
    const availableWidth = dims.sheetWidth - dims.marginLeft - dims.marginRight;
    const availableHeight = dims.sheetHeight - dims.marginTop - dims.marginBottom;
    const footprintWidth = dims.itemWidth + dims.bleed * 2;
    const footprintHeight = dims.itemHeight + dims.bleed * 2;
    const autoColumns = Math.max(0, Math.floor((availableWidth + dims.gapX) / (footprintWidth + dims.gapX)));
    const autoRows = Math.max(0, Math.floor((availableHeight + dims.gapY) / (footprintHeight + dims.gapY)));
    const columns = number(config.columns) || autoColumns;
    const rows = number(config.rows) || autoRows;
    const capacity = Math.max(0, columns * rows);
    const pageCount = Math.max(1, Math.round(number(config.sample_pages, 1)));
    const count = config.fill_last_sheet ? capacity : Math.min(capacity, pageCount);
    const usedWidth = columns * footprintWidth + Math.max(0, columns - 1) * dims.gapX;
    const usedHeight = rows * footprintHeight + Math.max(0, rows - 1) * dims.gapY;
    let startX = dims.marginLeft;
    let startY = dims.marginTop;
    if (config.anchor === 'center' || String(config.anchor).endsWith('center')) startX += (availableWidth - usedWidth) / 2;
    if (String(config.anchor).endsWith('right')) startX += availableWidth - usedWidth;
    if (config.anchor === 'center') startY += (availableHeight - usedHeight) / 2;
    if (String(config.anchor).startsWith('bottom')) startY += availableHeight - usedHeight;
    const placements = [];
    for (let index = 0; index < count; index += 1) {
      let row = Math.floor(index / Math.max(columns, 1));
      let column = index % Math.max(columns, 1);
      if (state.side === 'back' && config.double_sided_mode === 'horizontal') column = columns - 1 - column;
      if (state.side === 'back' && config.double_sided_mode === 'vertical') row = rows - 1 - row;
      placements.push({
        x: startX + column * (footprintWidth + dims.gapX) + dims.bleed,
        y: startY + row * (footprintHeight + dims.gapY) + dims.bleed,
        width: dims.itemWidth,
        height: dims.itemHeight,
        page: (index % pageCount) + 1,
        bleed: dims.bleed
      });
    }
    return { placements, columns, rows, capacity, sheets: capacity ? Math.ceil(pageCount / capacity) : 0, usedWidth, usedHeight };
  }

  function nestingLayout(dims) {
    const pageCount = Math.max(1, Math.round(number(config.sample_pages, 1)));
    const placements = [];
    const right = dims.sheetWidth - dims.marginRight;
    const bottom = dims.sheetHeight - dims.marginBottom;
    let x = dims.marginLeft + dims.bleed;
    let y = dims.marginTop + dims.bleed;
    let rowHeight = 0;
    for (let index = 0; index < pageCount; index += 1) {
      const variant = index % 3;
      let width = dims.itemWidth * (variant === 1 ? .72 : variant === 2 ? .55 : 1);
      let height = dims.itemHeight * (variant === 2 ? 1.25 : 1);
      if (config.rotate && height > width && x + height + dims.bleed > right && x + width + dims.bleed <= right) [width, height] = [height, width];
      if (x + width + dims.bleed > right) {
        x = dims.marginLeft + dims.bleed;
        y += rowHeight + dims.gapY + dims.bleed * 2;
        rowHeight = 0;
      }
      if (y + height + dims.bleed > bottom) break;
      placements.push({x, y, width, height, page: index + 1, bleed: dims.bleed});
      x += width + dims.gapX + dims.bleed * 2;
      rowHeight = Math.max(rowHeight, height);
    }
    const area = placements.reduce((sum, item) => sum + item.width * item.height, 0);
    const usable = Math.max(1, (right - dims.marginLeft) * (bottom - dims.marginTop));
    return {placements, capacity: placements.length, sheets: Math.ceil(pageCount / Math.max(placements.length, 1)), utilization: 100 * area / usable};
  }

  function bookletSequence(signaturePages, sheetIndex, side) {
    const left = side === 'front' ? signaturePages - sheetIndex * 2 : sheetIndex * 2 + 2;
    const right = side === 'front' ? sheetIndex * 2 + 1 : signaturePages - sheetIndex * 2 - 1;
    return config.binding === 'right' ? [right, left] : [left, right];
  }

  function bookletLayout(dims) {
    const signaturePages = number(config.signature_pages, 16);
    const halfWidth = (dims.sheetWidth - dims.marginLeft - dims.marginRight - number(config.gutter_mm)) / 2;
    const availableHeight = dims.sheetHeight - dims.marginTop - dims.marginBottom;
    const sourceRatio = dims.itemWidth / dims.itemHeight;
    let width = Math.min(halfWidth, availableHeight * sourceRatio);
    let height = width / sourceRatio;
    if (height > availableHeight) { height = availableHeight; width = height * sourceRatio; }
    const centerGap = number(config.gutter_mm);
    const totalWidth = width * 2 + centerGap;
    const startX = (dims.sheetWidth - totalWidth) / 2;
    const y = dims.marginTop + (availableHeight - height) / 2;
    const sheetIndex = 0;
    const pages = bookletSequence(signaturePages, sheetIndex, state.side);
    const creep = Math.max(0, number(config.creep_mm));
    return {
      placements: [
        {x: startX - creep / 2, y, width, height, page: pages[0], bleed: dims.bleed},
        {x: startX + width + centerGap + creep / 2, y, width, height, page: pages[1], bleed: dims.bleed}
      ],
      capacity: 2,
      sheets: Math.ceil(Math.max(1, number(config.sample_pages, signaturePages)) / signaturePages) * signaturePages / 4,
      signaturePages,
      foldX: dims.sheetWidth / 2
    };
  }

  function layout() {
    const dims = dimensions();
    const result = config.layout_mode === 'booklet'
      ? bookletLayout(dims)
      : config.layout_mode === 'nesting' ? nestingLayout(dims) : gridLayout(dims);
    return {...result, dims};
  }

  function svgElement(name, attributes = {}) {
    const element = document.createElementNS(svgNS, name);
    Object.entries(attributes).forEach(([key, value]) => element.setAttribute(key, value));
    return element;
  }

  function drawLine(x1, y1, x2, y2, color = '#111827', width = 1) {
    elements.marks.appendChild(svgElement('line', {x1, y1, x2, y2, stroke: color, 'stroke-width': width, 'vector-effect': 'non-scaling-stroke'}));
  }

  function renderMarks(result, pxPerMm) {
    elements.marks.replaceChildren();
    const marks = config.marks || {};
    const offsetMm = number(marks.offset_mm, 2);
    const lengthMm = number(marks.length_mm, 5);
    const offset = offsetMm * pxPerMm;
    const length = lengthMm * pxPerMm;
    if (marks.crop) {
      const outerBounds = (item) => {
        const bleed = number(item.bleed, 0);
        return {
          left: item.x - bleed,
          top: item.y - bleed,
          right: item.x + item.width + bleed,
          bottom: item.y + item.height + bleed
        };
      };
      const nearestGap = (index, direction) => {
        const current = outerBounds(result.placements[index]);
        const gaps = result.placements.flatMap((item, otherIndex) => {
          if (otherIndex === index) return [];
          const other = outerBounds(item);
          if (direction === 'left' || direction === 'right') {
            if (Math.min(current.bottom, other.bottom) - Math.max(current.top, other.top) <= .001) return [];
            if (direction === 'left' && other.right <= current.left + .001) return [current.left - other.right];
            if (direction === 'right' && other.left >= current.right - .001) return [other.left - current.right];
          } else {
            if (Math.min(current.right, other.right) - Math.max(current.left, other.left) <= .001) return [];
            if (direction === 'top' && other.bottom <= current.top + .001) return [current.top - other.bottom];
            if (direction === 'bottom' && other.top >= current.bottom - .001) return [other.top - current.bottom];
          }
          return [];
        });
        return gaps.length ? Math.min(...gaps) : null;
      };
      const fits = (gap) => gap === null || gap + .001 >= 2 * (offsetMm + lengthMm);
      result.placements.forEach((item, index) => {
        const x = item.x * pxPerMm; const y = item.y * pxPerMm;
        const right = (item.x + item.width) * pxPerMm; const bottom = (item.y + item.height) * pxPerMm;
        if (fits(nearestGap(index, 'left'))) {
          drawLine(x - offset - length, y, x - offset, y); drawLine(x - offset - length, bottom, x - offset, bottom);
        }
        if (fits(nearestGap(index, 'right'))) {
          drawLine(right + offset, y, right + offset + length, y); drawLine(right + offset, bottom, right + offset + length, bottom);
        }
        if (fits(nearestGap(index, 'top'))) {
          drawLine(x, y - offset - length, x, y - offset); drawLine(right, y - offset - length, right, y - offset);
        }
        if (fits(nearestGap(index, 'bottom'))) {
          drawLine(x, bottom + offset, x, bottom + offset + length); drawLine(right, bottom + offset, right, bottom + offset + length);
        }
      });
    }
    if (marks.fold && result.foldX) {
      const x = result.foldX * pxPerMm;
      drawLine(x, 0, x, length, '#087e8b');
      drawLine(x, result.dims.sheetHeight * pxPerMm - length, x, result.dims.sheetHeight * pxPerMm, '#087e8b');
    }
    if (marks.registration) {
      [[14, 14], [result.dims.sheetWidth - 14, 14], [14, result.dims.sheetHeight - 14], [result.dims.sheetWidth - 14, result.dims.sheetHeight - 14]].forEach(([xMm, yMm]) => {
        const group = svgElement('g'); const x = xMm * pxPerMm; const y = yMm * pxPerMm;
        group.appendChild(svgElement('circle', {cx: x, cy: y, r: 3 * pxPerMm, fill: 'none', stroke: '#111827', 'stroke-width': 1}));
        group.appendChild(svgElement('line', {x1: x - 4 * pxPerMm, y1: y, x2: x + 4 * pxPerMm, y2: y, stroke: '#111827'}));
        group.appendChild(svgElement('line', {x1: x, y1: y - 4 * pxPerMm, x2: x, y2: y + 4 * pxPerMm, stroke: '#111827'}));
        elements.marks.appendChild(group);
      });
    }
    if (marks.color_bars) {
      ['#00a8e8', '#e91e8c', '#f5d000', '#111827'].forEach((color, index) => elements.marks.appendChild(svgElement('rect', {
        x: (result.dims.sheetWidth / 2 - 12 + index * 6) * pxPerMm, y: 4 * pxPerMm,
        width: 6 * pxPerMm, height: 4 * pxPerMm, fill: color
      })));
    }
    if (marks.job_info) {
      const text = svgElement('text', {x: 8 * pxPerMm, y: (result.dims.sheetHeight - 4) * pxPerMm, fill: '#374151', 'font-size': 9});
      text.textContent = `${elements.name.value} · ${state.side === 'front' ? 'FRONTE' : 'RETRO'}`;
      elements.marks.appendChild(text);
    }
  }

  function render() {
    document.querySelectorAll('[data-mode]').forEach((button) => button.classList.toggle('active', button.dataset.mode === config.layout_mode));
    document.querySelectorAll('[data-mode-section]').forEach((section) => section.hidden = !section.dataset.modeSection.split(' ').includes(config.layout_mode));
    document.querySelectorAll('[data-grid-controls]').forEach((element) => element.hidden = config.layout_mode !== 'grid');
    document.querySelectorAll('[data-repeat-controls]').forEach((element) => element.hidden = config.layout_mode === 'booklet');
    document.querySelectorAll('[data-sheet-side]').forEach((button) => button.classList.toggle('active', button.dataset.sheetSide === state.side));

    const result = layout();
    state.lastLayout = result;
    const availableWidth = Math.max(320, elements.canvas.clientWidth - 100);
    const availableHeight = Math.max(420, elements.canvas.clientHeight - 90);
    const fitScale = Math.min(availableWidth / result.dims.sheetWidth, availableHeight / result.dims.sheetHeight);
    const pxPerMm = Math.max(.45, fitScale * state.zoom);
    elements.sheet.style.width = `${result.dims.sheetWidth * pxPerMm}px`;
    elements.sheet.style.height = `${result.dims.sheetHeight * pxPerMm}px`;
    elements.printable.style.left = `${result.dims.marginLeft * pxPerMm}px`;
    elements.printable.style.top = `${result.dims.marginTop * pxPerMm}px`;
    elements.printable.style.width = `${Math.max(0, result.dims.sheetWidth - result.dims.marginLeft - result.dims.marginRight) * pxPerMm}px`;
    elements.printable.style.height = `${Math.max(0, result.dims.sheetHeight - result.dims.marginTop - result.dims.marginBottom) * pxPerMm}px`;
    elements.placements.replaceChildren();
    result.placements.forEach((item) => {
      const element = document.createElement('div');
      element.className = `imposition-placement ${state.side === 'back' ? 'back' : ''}`;
      element.style.left = `${item.x * pxPerMm}px`; element.style.top = `${item.y * pxPerMm}px`;
      element.style.width = `${item.width * pxPerMm}px`; element.style.height = `${item.height * pxPerMm}px`;
      element.innerHTML = `<span class="page-label">${config.layout_mode === 'booklet' ? `Pag. ${item.page}` : item.page}</span>`;
      if (item.bleed > 0) {
        const outline = document.createElement('span'); outline.className = 'bleed-outline';
        outline.style.inset = `${-item.bleed * pxPerMm}px`;
        element.appendChild(outline);
      }
      elements.placements.appendChild(element);
    });
    renderMarks(result, pxPerMm);
    renderSummary(result);
    renderWarnings(result);
    elements.previewTitle.textContent = `Foglio 1 · ${state.side === 'front' ? 'Fronte' : 'Retro'}`;
    elements.sheetSize.textContent = `${result.dims.sheetWidth} × ${result.dims.sheetHeight} mm`;
    const area = result.placements.reduce((sum, item) => sum + item.width * item.height, 0);
    const sheetArea = result.dims.sheetWidth * result.dims.sheetHeight;
    elements.utilization.textContent = `Copertura ${Math.round(100 * area / sheetArea)}%`;
    elements.placementCount.textContent = `${result.placements.length} posizioni visibili`;
  }

  function renderSummary(result) {
    const modeLabels = {grid: 'Ripetizione', nesting: 'Nesting', booklet: 'Libretto'};
    const rows = [
      ['Metodo', modeLabels[config.layout_mode]],
      ['Foglio', `${result.dims.sheetWidth} × ${result.dims.sheetHeight} mm`],
      ['Posizioni', String(result.placements.length)],
      ['Fogli stimati', String(result.sheets || 1)],
      ['Abbondanza', config.bleed_mode === 'none' ? 'Nessuna' : `${number(config.bleed_mm)} mm`]
    ];
    if (config.layout_mode === 'grid') rows.splice(2, 0, ['Griglia', `${result.columns} × ${result.rows}`]);
    if (config.layout_mode === 'booklet') rows.splice(2, 0, ['Segnatura', `${result.signaturePages} pagine`]);
    elements.summary.innerHTML = rows.map(([label, value]) => `<div><dt>${label}</dt><dd>${value}</dd></div>`).join('');
  }

  function renderWarnings(result) {
    const warnings = [];
    const availableWidth = result.dims.sheetWidth - result.dims.marginLeft - result.dims.marginRight;
    const availableHeight = result.dims.sheetHeight - result.dims.marginTop - result.dims.marginBottom;
    if (availableWidth <= 0 || availableHeight <= 0) warnings.push('I margini non lasciano area utile sul foglio.');
    if (!result.placements.length) warnings.push('Nessun prodotto entra nell’area disponibile.');
    if (config.layout_mode === 'booklet' && number(config.sample_pages) % 4 !== 0) warnings.push('Il motore aggiungerà pagine bianche per completare il multiplo di 4.');
    if (config.bleed_mode === 'none') warnings.push('La plancia non aggiungerà né controllerà abbondanze.');
    if (config.marks.crop && result.dims.marginTop < number(config.marks.length_mm) + number(config.marks.offset_mm)) warnings.push('Il margine superiore può essere insufficiente per i crocini.');
    if (config.marks.crop && config.layout_mode === 'grid') {
      const requiredGap = 2 * (number(config.marks.offset_mm, 2) + number(config.marks.length_mm, 5));
      if (result.columns > 1 && result.dims.gapX < requiredGap) warnings.push('I crocini interni orizzontali saranno omessi: lo spazio X non li contiene senza invadere i prodotti.');
      if (result.rows > 1 && result.dims.gapY < requiredGap) warnings.push('I crocini interni verticali saranno omessi: lo spazio Y non li contiene senza invadere i prodotti.');
    }
    if (!warnings.length) {
      elements.warnings.innerHTML = '<div class="imposition-warning ok"><i class="fas fa-circle-check"></i><span>Configurazione coerente per la prova.</span></div>';
    } else {
      elements.warnings.innerHTML = warnings.map((message) => `<div class="imposition-warning"><i class="fas fa-triangle-exclamation"></i><span>${message}</span></div>`).join('');
    }
  }

  async function saveDraft() {
    showMessage('', '');
    const button = document.getElementById('saveImposition');
    button.disabled = true;
    button.innerHTML = '<span class="spinner-border spinner-border-sm"></span> Salvataggio';
    try {
      const response = await fetch(`/impositions/${root.dataset.templateId}`, {
        method: 'POST', headers: {'Content-Type': 'application/json', Accept: 'application/json'},
        body: JSON.stringify({name: elements.name.value, folder: elements.folder.value, description: elements.description.value, config})
      });
      const payload = await response.json();
      if (!response.ok || !payload.success) throw new Error(payload.error || 'Salvataggio non riuscito');
      state.dirty = false;
      elements.saveState.classList.add('saved');
      elements.saveState.textContent = `Bozza salvata · ${new Date(payload.saved_at).toLocaleTimeString('it-IT', {hour: '2-digit', minute: '2-digit'})}`;
      showMessage('Bozza salvata.', 'success');
      return true;
    } catch (error) {
      showMessage(error.message, 'error');
      return false;
    } finally {
      button.disabled = false;
      button.innerHTML = '<i class="fas fa-floppy-disk me-1"></i>Salva bozza';
    }
  }

  function showMessage(message, type) {
    elements.message.textContent = message;
    elements.message.className = `imposition-message ${message ? `visible ${type}` : ''}`;
  }

  bindControls();
  render();
}
