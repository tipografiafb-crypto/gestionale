(() => {
  'use strict';

  const initialElement = document.getElementById('automation-initial-data');
  if (!initialElement) return;

  const initial = JSON.parse(initialElement.textContent);
  const state = {
    flow: initial.flow,
    graph: initial.version.graph || {schema_version: 1, nodes: [], edges: []},
    catalog: initial.node_catalog || [],
    fieldCatalog: initial.field_catalog || [],
    presets: initial.presets || [],
    agents: initial.agents || [],
    flows: initial.flows || [],
    selectedNodeId: null,
    pendingConnection: null,
    dirty: false
  };

  const canvas = document.getElementById('automation-canvas');
  const nodesLayer = document.getElementById('automation-nodes');
  const edgesLayer = document.getElementById('automation-edges');
  const scrollArea = document.getElementById('automation-canvas-scroll');
  const message = document.getElementById('automation-message');
  const nodeForm = document.getElementById('automation-node-form');
  const nodeEmpty = document.getElementById('automation-node-empty');
  const nodeIdInput = document.getElementById('automation-node-id');
  const nodeTypeInput = document.getElementById('automation-node-type');
  const nodeLabelInput = document.getElementById('automation-node-label');
  const nodeConfigInput = document.getElementById('automation-node-config');
  const nodeConfigForm = document.getElementById('automation-node-config-form');

  const defaults = {
    trigger: {operation_type: 'any'},
    router: {
      cases: [{port: 'yes', label: 'Condizione', field: 'item.sku', operator: 'contains', value: 'CODICE'}],
      default_port: 'other'
    },
    set_variables: {values: {preset: 'STANDARD'}},
    calculate_copies: {
      quantity_field: 'item.quantity',
      output_key: 'production_copies',
      range_overrides: [],
      exact_overrides: {'25': 26, '50': 52, '100': 105}
    },
    duplicate_pages: {
      copies_field: 'variables.production_copies',
      output_kind: 'multipage_pdf'
    },
    pair_sides: {
      front_suffix: '_F',
      back_suffix: '_R',
      group_field: 'item.id',
      timeout_minutes: 15,
      missing_policy: 'route_incomplete',
      output_kind: 'paired_pdf'
    },
    photoshop: {
      agent_key: '',
      action_set: 'AZIONI',
      action_name: 'azione',
      width_mm: 0,
      height_mm: 0,
      dpi: 300,
      output_kind: 'photoshop_pdf'
    },
    illustrator: {
      agent_key: '',
      script_name: 'plettro2.jsx',
      template_path: 'STANDARD.ai',
      pdf_preset: 'PDF PLANCE',
      output_kind: 'unit_pdf'
    },
    step_repeat: {
      preset_code: 'STANDARD_MONO',
      output_kind: 'imposition_pdf'
    },
    barcode: {
      data_field: 'order.code',
      width_mm: 70,
      height_mm: 35,
      bar_height_mm: 18,
      output_kind: 'barcode_pdf'
    },
    hot_folder: {
      preset_code: 'LOCAL_TEST',
      destination_key: 'print_destination',
      artifact_kind: 'imposition_pdf',
      filename: '{{order.code}}-plancia.pdf',
      output_kind: 'delivered'
    },
    approval: {},
    handoff: {target_flow_id: ''},
    finish: {result_artifact_kind: ''}
  };

  const simpleConfigSchemas = {
    trigger: [
      {
        key: 'operation_type',
        label: 'Azione accettata',
        default: 'any',
        choices: [
          ['any', 'Qualsiasi azione / test manuale'],
          ['preprint', 'Prestampa'],
          ['print', 'Stampa'],
          ['label', 'Etichetta']
        ],
        help: 'Il flusso rifiuta automaticamente azioni di tipo diverso.'
      }
    ],
    photoshop: [
      {
        key: 'agent_key',
        label: 'Macchina Adobe',
        choices: 'agents',
        help: 'Seleziona il Mac che eseguirà realmente questo blocco.'
      },
      {key: 'action_set', label: 'Gruppo azioni Photoshop'},
      {key: 'action_name', label: 'Azione Photoshop'},
      {
        key: 'width_mm',
        label: 'Larghezza finale (mm)',
        type: 'number',
        default: 0,
        help: 'Inserisci 0 per non modificare le dimensioni.'
      },
      {
        key: 'height_mm',
        label: 'Altezza finale (mm)',
        type: 'number',
        default: 0,
        help: 'Larghezza e altezza devono essere entrambe compilate oppure entrambe a 0.'
      },
      {
        key: 'dpi',
        label: 'Risoluzione di stampa (DPI)',
        type: 'number',
        default: 300,
        help: 'Con dimensioni a 0 cambia solo la risoluzione. Con dimensioni compilate determina i pixel finali.'
      },
      {key: 'output_kind', label: 'Tipo risultato', default: 'photoshop_pdf'}
    ],
    illustrator: [
      {
        key: 'agent_key',
        label: 'Macchina Adobe',
        choices: 'agents',
        help: 'Il percorso della maschera viene interpretato su questa macchina.'
      },
      {
        key: 'script_name',
        label: 'Script JSX Illustrator',
        choices: 'illustrator_scripts',
        default: 'plettro2.jsx'
      },
      {
        key: 'template_path',
        label: 'Maschera Illustrator',
        choices: 'illustrator_templates',
        default: 'STANDARD.ai'
      },
      {key: 'pdf_preset', label: 'Preset PDF Illustrator', default: 'PDF PLANCE'},
      {key: 'output_kind', label: 'Tipo risultato', default: 'unit_pdf'}
    ],
    duplicate_pages: [
      {
        key: 'copies_field',
        label: 'Numero di pagine da',
        choices: [
          ['variables.production_copies', 'Copie calcolate'],
          ['item.quantity', 'Quantità ordinata']
        ],
        default: 'variables.production_copies'
      },
      {key: 'output_kind', label: 'Tipo risultato', default: 'multipage_pdf'}
    ],
    pair_sides: [
      {
        key: 'front_suffix',
        label: 'Suffisso fronte',
        default: '_F',
        help: 'Viene cercato alla fine del nome, prima dell’estensione.'
      },
      {
        key: 'back_suffix',
        label: 'Suffisso retro',
        default: '_R',
        help: 'Maiuscole e minuscole sono considerate equivalenti.'
      },
      {
        key: 'group_field',
        label: 'Abbina usando',
        choices: [
          ['item.id', 'Riga ordine (consigliato)'],
          ['order.code', 'Codice ordine'],
          ['operation.id', 'Identificativo operazione']
        ],
        default: 'item.id'
      },
      {
        key: 'timeout_minutes',
        label: 'Attesa lato mancante (minuti)',
        type: 'number',
        default: 15
      },
      {
        key: 'missing_policy',
        label: 'Allo scadere dell’attesa',
        choices: [
          ['route_incomplete', 'Invia all’uscita Incompleto'],
          ['treat_as_mono', 'Considera monofacciale'],
          ['fail', 'Ferma il flusso con errore']
        ],
        default: 'route_incomplete'
      },
      {key: 'output_kind', label: 'Tipo risultato bifacciale', default: 'paired_pdf'}
    ],
    step_repeat: [
      {key: 'preset_code', label: 'Preset plancia', choices: 'imposition'},
      {key: 'output_kind', label: 'Tipo risultato', default: 'imposition_pdf'}
    ],
    barcode: [
      {key: 'data_field', label: 'Valore barcode', choices: 'fields', default: 'order.code'},
      {key: 'width_mm', label: 'Larghezza (mm)', type: 'number', default: 70},
      {key: 'height_mm', label: 'Altezza (mm)', type: 'number', default: 35},
      {key: 'bar_height_mm', label: 'Altezza barre (mm)', type: 'number', default: 18},
      {key: 'output_kind', label: 'Tipo risultato', default: 'barcode_pdf'}
    ],
    hot_folder: [
      {key: 'preset_code', label: 'Preset destinazione', choices: 'output'},
      {key: 'destination_key', label: 'Destinazione del preset', default: 'print_destination'},
      {key: 'artifact_kind', label: 'File da consegnare'},
      {
        key: 'filename',
        label: 'Nome file',
        default: '{{order.code}}-output.pdf',
        help: 'Puoi usare {{order.code}}, {{item.sku}} e {{file.filename}}.'
      },
      {key: 'output_kind', label: 'Tipo risultato', default: 'delivered'}
    ],
    handoff: [
      {
        key: 'target_flow_id',
        label: 'Automazione successiva',
        choices: 'flows',
        help: 'Il file corrente, SKU, quantità e variabili passano al flusso scelto. Il blocco deve essere l’ultimo del modulo.'
      }
    ],
    finish: [
      {
        key: 'result_artifact_kind',
        label: 'Risultato della lavorazione',
        help: 'Lascia vuoto per usare l’ultimo file prodotto. In prestampa verrà registrato come print_output.'
      }
    ]
  };

  const catalogFor = (type) => state.catalog.find((item) => item.type === type) || {};
  const nodeFor = (id) => state.graph.nodes.find((node) => node.id === id);

  function showMessage(text, type = 'info') {
    message.textContent = text;
    message.className = `automation-message is-visible is-${type}`;
  }

  function markDirty() {
    state.dirty = true;
    showMessage('Modifiche non ancora salvate.');
  }

  function uniqueId(type) {
    let suffix = 1;
    let candidate = `${type}_${suffix}`;
    while (nodeFor(candidate)) {
      suffix += 1;
      candidate = `${type}_${suffix}`;
    }
    return candidate;
  }

  function portsFor(node) {
    if (node.type !== 'router') {
      const labels = {
        mono: 'Monofacciale',
        bifa: 'Bifacciale',
        incomplete: 'Incompleto'
      };
      return Array.from(catalogFor(node.type).outputs || []).map((key) => ({
        key,
        label: labels[key] || ''
      }));
    }
    const cases = Array.isArray(node.config?.cases) ? node.config.cases : [];
    const ports = cases.map((rule, index) => ({
      key: String(rule.port || `case_${index + 1}`),
      label: String(rule.label || rule.value || `Caso ${index + 1}`)
    }));
    ports.push({
      key: String(node.config?.default_port || 'default'),
      label: 'Altrimenti'
    });
    return ports;
  }

  function choicesFor(value) {
    if (value === 'fields') {
      return state.fieldCatalog.map((field) => [field.path, field.label]);
    }
    if (value === 'imposition' || value === 'output') {
      return [
        ['', '-- Seleziona preset --'],
        ...state.presets
          .filter((preset) => preset.kind === value)
          .map((preset) => [preset.code, `${preset.name} (${preset.code})`])
      ];
    }
    if (value === 'agents') {
      return [
        ['', '-- Qualsiasi macchina compatibile --'],
        ...state.agents.map((agent) => [
          agent.key,
          `${agent.name}${agent.online ? ' · online' : ' · offline'}`
        ])
      ];
    }
    if (value === 'flows') {
      return [
        ['', '-- Seleziona automazione pubblicata --'],
        ...state.flows.map((flow) => [flow.id, `${flow.name} · v${flow.version}`])
      ];
    }
    if (value === 'illustrator_scripts' || value === 'illustrator_templates') {
      const metadataKey = value === 'illustrator_scripts'
        ? 'illustrator_scripts'
        : 'illustrator_templates';
      const values = [...new Set(state.agents.flatMap(
        (agent) => Array.isArray(agent.metadata?.[metadataKey]) ? agent.metadata[metadataKey] : []
      ))].sort();
      return [
        ['', value === 'illustrator_scripts' ? '-- Seleziona script --' : '-- Seleziona maschera --'],
        ...values.map((name) => [name, name])
      ];
    }
    return value || null;
  }

  function configField(field, value, role = field.key) {
    const wrapper = document.createElement('div');
    wrapper.className = 'mb-2';
    const label = document.createElement('label');
    label.className = 'form-label small mb-1';
    label.textContent = field.label;
    const choices = choicesFor(field.choices);
    let input;
    if (choices) {
      input = document.createElement('select');
      input.className = 'form-select form-select-sm';
      choices.forEach(([choiceValue, choiceLabel]) => {
        const option = document.createElement('option');
        option.value = choiceValue;
        option.textContent = choiceLabel;
        option.selected = String(choiceValue) === String(value ?? field.default ?? '');
        input.appendChild(option);
      });
    } else if (field.multiline) {
      input = document.createElement('textarea');
      input.className = 'form-control form-control-sm';
      input.rows = field.rows || 3;
      input.value = value ?? field.default ?? '';
    } else {
      input = document.createElement('input');
      input.className = 'form-control form-control-sm';
      input.type = field.type || 'text';
      input.step = field.type === 'number' ? 'any' : '';
      input.value = value ?? field.default ?? '';
    }
    input.dataset.configRole = role;
    wrapper.append(label, input);
    if (field.help) {
      const help = document.createElement('div');
      help.className = 'form-text';
      help.textContent = field.help;
      wrapper.appendChild(help);
    }
    return wrapper;
  }

  function configValue(role, root = nodeConfigForm) {
    return root.querySelector(`[data-config-role="${role}"]`)?.value ?? '';
  }

  function configHint(text) {
    const hint = document.createElement('div');
    hint.className = 'alert alert-light border small py-2';
    hint.textContent = text;
    nodeConfigForm.appendChild(hint);
  }

  function appendRouterCase(container, rule = {}, index = 0) {
    const card = document.createElement('div');
    card.className = 'automation-config-case border rounded p-2 mb-2';
    const heading = document.createElement('div');
    heading.className = 'd-flex align-items-center justify-content-between mb-2';
    const title = document.createElement('strong');
    title.className = 'small';
    title.textContent = `Condizione ${index + 1}`;
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'btn btn-sm btn-outline-danger py-0 px-2';
    remove.textContent = '×';
    remove.addEventListener('click', () => card.remove());
    heading.append(title, remove);
    card.append(
      heading,
      configField({label: 'Campo', choices: 'fields'}, rule.field || 'item.sku', 'case_field'),
      configField({
        label: 'Confronto',
        choices: [
          ['equals', 'è uguale a'],
          ['contains', 'contiene'],
          ['starts_with', 'inizia con'],
          ['greater_than', 'è maggiore di'],
          ['greater_or_equal', 'è maggiore o uguale a'],
          ['less_than', 'è minore di'],
          ['less_or_equal', 'è minore o uguale a'],
          ['matches', 'corrisponde a espressione']
        ]
      }, rule.operator || 'contains', 'case_operator'),
      configField({
        label: 'Valore',
        help: 'Per usare OR separa più valori con ; — esempio: AA001;AA002;AA003'
      }, rule.value ?? '', 'case_value'),
      configField({label: 'Nome uscita'}, rule.label || rule.value || `Caso ${index + 1}`, 'case_label'),
      configField({
        label: 'Codice uscita',
        help: 'Identifica il pallino di uscita del blocco.'
      }, rule.port || `case_${index + 1}`, 'case_port')
    );
    container.appendChild(card);
  }

  function renderRouterConfig(node) {
    configHint('Le condizioni vengono controllate dall’alto verso il basso. La prima corrispondenza decide l’uscita.');
    const cases = document.createElement('div');
    const rules = Array.isArray(node.config?.cases) ? node.config.cases : [];
    rules.forEach((rule, index) => appendRouterCase(cases, rule, index));
    nodeConfigForm.appendChild(cases);
    const add = document.createElement('button');
    add.type = 'button';
    add.className = 'btn btn-sm btn-outline-primary w-100 mb-3';
    add.textContent = '+ Aggiungi condizione';
    add.addEventListener('click', () => appendRouterCase(
      cases,
      {},
      cases.querySelectorAll('.automation-config-case').length
    ));
    nodeConfigForm.append(
      add,
      configField(
        {label: 'Uscita se nessuna condizione corrisponde'},
        node.config?.default_port || 'default',
        'default_port'
      )
    );
  }

  function appendVariableRow(container, key = '', value = '') {
    const row = document.createElement('div');
    row.className = 'automation-variable-row d-flex gap-2 mb-2';
    const keyInput = document.createElement('input');
    keyInput.className = 'form-control form-control-sm';
    keyInput.placeholder = 'Nome variabile';
    keyInput.value = key;
    keyInput.dataset.configRole = 'variable_key';
    const valueInput = document.createElement('input');
    valueInput.className = 'form-control form-control-sm';
    valueInput.placeholder = 'Valore';
    valueInput.value = value;
    valueInput.dataset.configRole = 'variable_value';
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'btn btn-sm btn-outline-danger';
    remove.textContent = '×';
    remove.addEventListener('click', () => row.remove());
    row.append(keyInput, valueInput, remove);
    container.appendChild(row);
  }

  function renderNodeConfigForm(node) {
    nodeConfigForm.replaceChildren();
    if (node.type === 'router') {
      renderRouterConfig(node);
      return;
    }
    if (node.type === 'set_variables') {
      configHint('Salva valori riutilizzabili nei blocchi successivi, ad esempio maschera o preset.');
      const rows = document.createElement('div');
      Object.entries(node.config?.values || {}).forEach(([key, value]) => appendVariableRow(rows, key, value));
      nodeConfigForm.appendChild(rows);
      const add = document.createElement('button');
      add.type = 'button';
      add.className = 'btn btn-sm btn-outline-primary w-100';
      add.textContent = '+ Aggiungi variabile';
      add.addEventListener('click', () => appendVariableRow(rows));
      nodeConfigForm.appendChild(add);
      return;
    }
    if (node.type === 'calculate_copies') {
      const exactOverrides = Object.entries(node.config?.exact_overrides || {})
        .map(([from, to]) => `${from}=${to}`)
      const rangeOverrides = Array.isArray(node.config?.range_overrides)
        ? node.config.range_overrides.map((rule) => `da ${rule.from} a ${rule.to} = ${rule.copies}`)
        : [];
      const overrides = [...exactOverrides, ...rangeOverrides].join('\n');
      nodeConfigForm.append(
        configField({label: 'Quantità di partenza', choices: 'fields'}, node.config?.quantity_field || 'item.quantity', 'quantity_field'),
        configField({label: 'Nome del risultato'}, node.config?.output_key || 'production_copies', 'output_key'),
        configField({
          label: 'Eccezioni quantità',
          multiline: true,
          rows: 6,
          help: 'Una per riga. Valore esatto: 25=26. Intervallo: da 200 a 1000 = 105.'
        }, overrides, 'exact_overrides')
      );
      return;
    }

    const schema = simpleConfigSchemas[node.type];
    if (!schema) {
      configHint('Questo blocco non richiede configurazione.');
      return;
    }
    if (node.type === 'trigger') {
      configHint('Questo ingresso può essere avviato manualmente o da un’azione del gestionale.');
    }
    if (node.type === 'pair_sides') {
      configHint('I file senza suffisso escono subito come monofacciali. I file fronte e retro vengono attesi, ordinati e uniti in un PDF a due pagine.');
    }
    schema.forEach((field) => {
      nodeConfigForm.appendChild(configField(field, node.config?.[field.key]));
    });
  }

  function collectNodeConfig(node) {
    if (node.type === 'router') {
      return {
        cases: Array.from(nodeConfigForm.querySelectorAll('.automation-config-case')).map((card, index) => ({
          port: configValue('case_port', card) || `case_${index + 1}`,
          label: configValue('case_label', card) || `Condizione ${index + 1}`,
          field: configValue('case_field', card) || 'item.sku',
          operator: configValue('case_operator', card) || 'equals',
          value: configValue('case_value', card)
        })),
        default_port: configValue('default_port') || 'default'
      };
    }
    if (node.type === 'set_variables') {
      const values = {};
      nodeConfigForm.querySelectorAll('.automation-variable-row').forEach((row) => {
        const key = configValue('variable_key', row).trim();
        if (key) values[key] = configValue('variable_value', row);
      });
      return {values};
    }
    if (node.type === 'calculate_copies') {
      const exactOverrides = {};
      const rangeOverrides = [];
      configValue('exact_overrides').split(/\r?\n/).forEach((line) => {
        const exactMatch = line.match(/^\s*(\d+)\s*[=:]\s*(\d+)\s*$/);
        if (exactMatch) {
          exactOverrides[exactMatch[1]] = Number(exactMatch[2]);
          return;
        }
        const rangeMatch = line.match(
          /^\s*(?:da\s+)?(\d+)\s*(?:a|-|\.\.)\s*(\d+)\s*[=:]\s*(\d+)\s*$/i
        );
        if (rangeMatch) {
          if (Number(rangeMatch[1]) > Number(rangeMatch[2])) {
            throw new Error(`Intervallo quantità invertito: ${line.trim()}`);
          }
          rangeOverrides.push({
            from: Number(rangeMatch[1]),
            to: Number(rangeMatch[2]),
            copies: Number(rangeMatch[3])
          });
          return;
        }
        if (line.trim()) throw new Error(`Eccezione quantità non riconosciuta: ${line.trim()}`);
      });
      return {
        quantity_field: configValue('quantity_field') || 'item.quantity',
        output_key: configValue('output_key') || 'production_copies',
        range_overrides: rangeOverrides,
        exact_overrides: exactOverrides
      };
    }

    const schema = simpleConfigSchemas[node.type];
    if (!schema) return {};
    return Object.fromEntries(schema.map((field) => {
      const value = configValue(field.key);
      return [field.key, field.type === 'number' ? Number(value || field.default || 0) : value];
    }));
  }

  function addNode(type, position = {}) {
    const item = catalogFor(type);
    const id = uniqueId(type);
    const x = Math.max(10, Number(position.x ?? (scrollArea.scrollLeft + 100)));
    const y = Math.max(10, Number(position.y ?? (scrollArea.scrollTop + 100 + (state.graph.nodes.length % 5) * 24)));
    state.graph.nodes.push({
      id,
      type,
      label: item.label || type,
      position: {x, y},
      config: JSON.parse(JSON.stringify(defaults[type] || {}))
    });
    state.selectedNodeId = id;
    markDirty();
    render();
  }

  function selectNode(id, options = {}) {
    state.selectedNodeId = id;
    const node = nodeFor(id);
    nodeEmpty.hidden = !!node;
    nodeForm.hidden = !node;
    if (node) {
      nodeIdInput.value = node.id;
      nodeTypeInput.value = node.type;
      nodeLabelInput.value = node.label || '';
      nodeConfigInput.value = JSON.stringify(node.config || {}, null, 2);
      nodeConfigInput.dataset.dirty = '0';
      renderNodeConfigForm(node);
    }
    if (options.render !== false) renderNodes();
  }

  function markNodeSelected(element, id) {
    state.selectedNodeId = id;
    document.querySelectorAll('.automation-node.is-selected').forEach((nodeElement) => {
      nodeElement.classList.remove('is-selected');
    });
    element.classList.add('is-selected');
  }

  function deleteNode(requestedId = state.selectedNodeId) {
    const id = requestedId;
    if (!id) return;
    const node = nodeFor(id);
    if (!node) return;
    const connections = state.graph.edges.filter((edge) => edge.source === id || edge.target === id).length;
    const detail = connections > 0 ? ` e ${connections} collegamento/i` : '';
    if (!window.confirm(`Eliminare il blocco “${node.label || node.id}”${detail}?`)) return;
    state.graph.nodes = state.graph.nodes.filter((node) => node.id !== id);
    state.graph.edges = state.graph.edges.filter((edge) => edge.source !== id && edge.target !== id);
    state.selectedNodeId = null;
    state.pendingConnection = null;
    nodeEmpty.hidden = false;
    nodeForm.hidden = true;
    markDirty();
    render();
    showMessage('Blocco eliminato dalla bozza. Premi “Salva bozza” per confermare la modifica.', 'success');
  }

  function startConnection(nodeId, port) {
    state.pendingConnection = {source: nodeId, source_port: port};
    showMessage(`Uscita “${port}” selezionata. Ora clicca il blocco di destinazione (oppure il suo ingresso a sinistra).`);
    renderNodes();
  }

  function finishConnection(target) {
    const pending = state.pendingConnection;
    if (!pending || pending.source === target) return;
    state.graph.edges = state.graph.edges.filter(
      (edge) => !(edge.source === pending.source && String(edge.source_port || 'default') === pending.source_port)
    );
    state.graph.edges.push({
      id: `edge_${Date.now()}_${Math.random().toString(16).slice(2, 7)}`,
      source: pending.source,
      target,
      source_port: pending.source_port
    });
    state.pendingConnection = null;
    markDirty();
    render();
  }

  function removeEdge(id) {
    state.graph.edges = state.graph.edges.filter((edge) => edge.id !== id);
    markDirty();
    renderEdges();
  }

  function renderPalette() {
    const list = document.getElementById('automation-palette-list');
    list.replaceChildren();
    state.catalog.forEach((item) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'automation-palette-button';
      button.draggable = true;
      button.title = 'Clicca oppure trascina sul piano';
      const icon = document.createElement('i');
      icon.className = `fas ${item.icon || 'fa-cube'}`;
      const label = document.createElement('span');
      label.textContent = item.label;
      button.append(icon, label);
      button.addEventListener('click', () => addNode(item.type));
      button.addEventListener('dragstart', (event) => {
        event.dataTransfer.effectAllowed = 'copy';
        event.dataTransfer.setData('application/x-automation-node', item.type);
        event.dataTransfer.setData('text/plain', item.type);
        button.classList.add('is-dragging');
      });
      button.addEventListener('dragend', () => button.classList.remove('is-dragging'));
      list.appendChild(button);
    });
  }

  function renderNodes() {
    nodesLayer.replaceChildren();
    state.graph.nodes.forEach((node) => {
      const element = document.createElement('article');
      element.className = 'automation-node';
      if (state.selectedNodeId === node.id) element.classList.add('is-selected');
      if (state.pendingConnection?.source === node.id) element.classList.add('is-connection-source');
      element.dataset.nodeId = node.id;
      element.style.left = `${Number(node.position?.x || 0)}px`;
      element.style.top = `${Number(node.position?.y || 0)}px`;

      const header = document.createElement('div');
      header.className = 'automation-node-header';
      const icon = document.createElement('i');
      icon.className = `fas ${catalogFor(node.type).icon || 'fa-cube'}`;
      const label = document.createElement('span');
      label.className = 'automation-node-label';
      label.textContent = node.label || node.id;
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'automation-node-delete';
      remove.title = 'Elimina blocco';
      remove.setAttribute('aria-label', `Elimina blocco ${node.label || node.id}`);
      remove.innerHTML = '<i class="fas fa-trash"></i>';
      remove.addEventListener('pointerdown', (event) => event.stopPropagation());
      remove.addEventListener('click', (event) => {
        event.stopPropagation();
        deleteNode(node.id);
      });
      header.append(icon, label, remove);

      const body = document.createElement('div');
      body.className = 'automation-node-body';
      body.textContent = `${node.type} · ${node.id}`;
      element.append(header, body);

      if (node.type !== 'trigger') {
        const input = document.createElement('button');
        input.type = 'button';
        input.className = 'automation-handle automation-handle-input';
        input.title = 'Ingresso';
        input.setAttribute('aria-label', `Ingresso di ${node.label || node.id}`);
        input.addEventListener('pointerdown', (event) => event.stopPropagation());
        input.addEventListener('click', (event) => {
          event.stopPropagation();
          finishConnection(node.id);
        });
        element.appendChild(input);
      }

      const ports = portsFor(node);
      const requiredHeight = Math.max(92, 62 + ports.length * 24);
      element.style.minHeight = `${requiredHeight}px`;
      ports.forEach((port, index) => {
        const top = 49 + index * 24;
        const output = document.createElement('button');
        output.type = 'button';
        output.className = 'automation-handle automation-handle-output';
        output.style.top = `${top}px`;
        output.title = `Uscita: ${port.key}`;
        output.setAttribute('aria-label', `Uscita ${port.key} di ${node.label || node.id}`);
        output.addEventListener('pointerdown', (event) => event.stopPropagation());
        output.addEventListener('click', (event) => {
          event.stopPropagation();
          startConnection(node.id, port.key);
        });
        element.appendChild(output);
        if (port.label) {
          const portLabel = document.createElement('span');
          portLabel.className = 'automation-port-label';
          portLabel.style.top = `${top}px`;
          portLabel.textContent = port.label;
          element.appendChild(portLabel);
        }
      });

      element.addEventListener('click', () => {
        if (state.pendingConnection && state.pendingConnection.source !== node.id) {
          finishConnection(node.id);
          return;
        }
        selectNode(node.id);
      });
      enableDragging(element, header, node);
      nodesLayer.appendChild(element);
    });
  }

  function enableDragging(element, handle, node) {
    handle.addEventListener('pointerdown', (event) => {
      if (event.button !== undefined && event.button !== 0) return;
      event.preventDefault();
      markNodeSelected(element, node.id);
      selectNode(node.id, {render: false});
      const startX = event.clientX;
      const startY = event.clientY;
      const originX = Number(node.position?.x || 0);
      const originY = Number(node.position?.y || 0);
      let moved = false;

      const onMove = (moveEvent) => {
        if (moveEvent.pointerId !== event.pointerId) return;
        const deltaX = moveEvent.clientX - startX;
        const deltaY = moveEvent.clientY - startY;
        if (!moved && Math.abs(deltaX) < 3 && Math.abs(deltaY) < 3) return;
        moved = true;
        moveEvent.preventDefault();
        node.position = {
          x: Math.max(10, originX + deltaX),
          y: Math.max(10, originY + deltaY)
        };
        element.style.left = `${node.position.x}px`;
        element.style.top = `${node.position.y}px`;
        renderEdges();
      };
      const onUp = (upEvent) => {
        if (upEvent.pointerId !== event.pointerId) return;
        window.removeEventListener('pointermove', onMove);
        window.removeEventListener('pointerup', onUp);
        window.removeEventListener('pointercancel', onUp);
        element.classList.remove('is-dragging');
        if (moved) markDirty();
      };
      element.classList.add('is-dragging');
      window.addEventListener('pointermove', onMove, {passive: false});
      window.addEventListener('pointerup', onUp);
      window.addEventListener('pointercancel', onUp);
    });
  }

  function connectionPoint(node, port, output) {
    const x = Number(node.position?.x || 0);
    const y = Number(node.position?.y || 0);
    if (!output) return {x: x - 1, y: y + 51};
    const index = Math.max(0, portsFor(node).findIndex((candidate) => candidate.key === port));
    return {x: x + 195, y: y + 56 + index * 24};
  }

  function renderEdges() {
    edgesLayer.replaceChildren();
    state.graph.edges.forEach((edge) => {
      const source = nodeFor(edge.source);
      const target = nodeFor(edge.target);
      if (!source || !target) return;
      const start = connectionPoint(source, String(edge.source_port || 'default'), true);
      const end = connectionPoint(target, null, false);
      const bend = Math.max(70, Math.abs(end.x - start.x) * 0.45);
      const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      path.setAttribute('class', 'automation-edge');
      path.setAttribute('d', `M ${start.x} ${start.y} C ${start.x + bend} ${start.y}, ${end.x - bend} ${end.y}, ${end.x} ${end.y}`);
      path.setAttribute('title', 'Clicca per eliminare il collegamento');
      path.addEventListener('click', () => removeEdge(edge.id));
      edgesLayer.appendChild(path);
    });
  }

  function render() {
    renderNodes();
    renderEdges();
    if (state.selectedNodeId) selectNode(state.selectedNodeId);
  }

  async function request(url, options) {
    const response = await fetch(url, options);
    const payload = await response.json();
    if (!response.ok) throw new Error((payload.errors || [payload.error || `HTTP ${response.status}`]).join(' · '));
    return payload;
  }

  function syncSelectedNodeConfig() {
    const node = nodeFor(state.selectedNodeId);
    if (!node) return;
    node.config = nodeConfigInput.dataset.dirty === '1'
      ? JSON.parse(nodeConfigInput.value || '{}')
      : collectNodeConfig(node);
    node.label = nodeLabelInput.value.trim() || node.id;
  }

  async function save() {
    try {
      syncSelectedNodeConfig();
      const payload = await request(`/api/automations/${state.flow.id}/editor`, {
        method: 'PUT',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          flow: {
            name: document.getElementById('automation-flow-name').value,
            description: document.getElementById('automation-flow-description').value
          },
          graph: state.graph
        })
      });
      state.dirty = false;
      if (payload.valid) {
        showMessage(
          `Bozza salvata alle ${new Date(payload.saved_at).toLocaleTimeString('it-IT')}. Premi “Pubblica” per usarla nelle esecuzioni.`,
          'success'
        );
      } else {
        showMessage(`Bozza salvata, ma non pubblicabile: ${payload.errors.join(' · ')}`, 'error');
      }
      return true;
    } catch (error) {
      showMessage(`Salvataggio fallito: ${error.message}`, 'error');
      return false;
    }
  }

  async function validate() {
    try {
      syncSelectedNodeConfig();
      const payload = await request(`/api/automations/${state.flow.id}/validate`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({graph: state.graph})
      });
      if (payload.success) {
        showMessage(`Flusso valido: ${payload.nodes_count} blocchi e ${payload.edges_count} collegamenti.`, 'success');
      } else {
        showMessage(`Il flusso non è valido: ${payload.errors.join(' · ')}`, 'error');
      }
    } catch (error) {
      showMessage(`Il flusso non è valido: ${error.message}`, 'error');
    }
  }

  document.getElementById('apply-node').addEventListener('click', () => {
    const node = nodeFor(state.selectedNodeId);
    if (!node) return;
    try {
      syncSelectedNodeConfig();
      markDirty();
      render();
      selectNode(node.id);
    } catch (error) {
      showMessage(`Configurazione non valida: ${error.message}`, 'error');
    }
  });

  nodeConfigInput.addEventListener('input', () => {
    nodeConfigInput.dataset.dirty = '1';
  });

  document.getElementById('delete-node').addEventListener('click', deleteNode);
  document.getElementById('save-automation').addEventListener('click', save);
  document.getElementById('validate-automation').addEventListener('click', validate);
  document.getElementById('fit-automation').addEventListener('click', () => scrollArea.scrollTo({left: 0, top: 0, behavior: 'smooth'}));

  scrollArea.addEventListener('dragover', (event) => {
    if (!event.dataTransfer.types.includes('application/x-automation-node')) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = 'copy';
    scrollArea.classList.add('is-drop-target');
  });
  scrollArea.addEventListener('dragleave', (event) => {
    if (!scrollArea.contains(event.relatedTarget)) scrollArea.classList.remove('is-drop-target');
  });
  scrollArea.addEventListener('drop', (event) => {
    const type = event.dataTransfer.getData('application/x-automation-node') ||
      event.dataTransfer.getData('text/plain');
    scrollArea.classList.remove('is-drop-target');
    if (!catalogFor(type).type) return;
    event.preventDefault();
    const canvasRect = canvas.getBoundingClientRect();
    addNode(type, {
      x: event.clientX - canvasRect.left - 97,
      y: event.clientY - canvasRect.top - 30
    });
  });

  document.getElementById('publish-automation-form').addEventListener('submit', async (event) => {
    const form = event.currentTarget;
    if (form.dataset.ready === '1') return;
    event.preventDefault();
    const button = form.querySelector('button[type="submit"], button:not([type])');
    if (button) {
      button.disabled = true;
      button.innerHTML = '<i class="fas fa-spinner fa-spin me-1"></i>Pubblicazione…';
    }
    const saved = await save();
    if (!saved) {
      if (button) {
        button.disabled = false;
        button.innerHTML = '<i class="fas fa-cloud-arrow-up me-1"></i>Pubblica';
      }
      return;
    }
    form.dataset.ready = '1';
    form.submit();
  });

  document.addEventListener('keydown', (event) => {
    if (!['Delete', 'Backspace'].includes(event.key) || !state.selectedNodeId) return;
    const target = event.target;
    if (target instanceof HTMLInputElement ||
        target instanceof HTMLTextAreaElement ||
        target instanceof HTMLSelectElement ||
        target?.isContentEditable) return;
    event.preventDefault();
    deleteNode();
  });

  window.addEventListener('beforeunload', (event) => {
    if (!state.dirty) return;
    event.preventDefault();
    event.returnValue = '';
  });

  renderPalette();
  render();
})();
