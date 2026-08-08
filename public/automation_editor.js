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
    destinations: initial.destinations || [],
    agents: initial.agents || [],
    flows: initial.flows || [],
    selectedNodeId: null,
    selectedNodeIds: new Set(),
    pendingConnection: null,
    dirty: false,
    zoom: 1
  };

  const GRID_SIZE = 20;
  const CANVAS_WIDTH = 3600;
  const CANVAS_HEIGHT = 1400;
  const MIN_ZOOM = 0.2;
  const MAX_ZOOM = 1.5;
  const canvas = document.getElementById('automation-canvas');
  const canvasContent = document.getElementById('automation-canvas-content');
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
    trigger: {operation_type: 'any', source_type: 'any'},
    router: {
      cases: [{port: 'yes', label: 'Condizione', field: 'item.sku', operator: 'contains', value: 'CODICE'}],
      default_port: 'other'
    },
    fork: {},
    set_variables: {values: {preset: 'STANDARD'}},
    select_resource: {
      asset_type: 'print',
      asset_index: 1,
      resource_role: 'Graphics',
      resource_position: 1,
      missing_policy: 'fail',
      output_kind: 'selected_resource'
    },
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
    pdf_label: {
      text: '{{order.code}}',
      anchor: 'top_left',
      font: 'Times-Roman',
      font_size_pt: 8.5,
      offset_x_mm: 0,
      offset_y_mm: 5,
      output_kind: 'labeled_pdf'
    },
    resize_pdf: {
      width_mm: 297,
      height_mm: 210,
      mode: 'contain',
      output_kind: 'resized_pdf'
    },
    collect_group: {
      group_field: 'aggregation.token',
      expected_count: 0,
      expected_count_field: 'aggregation.expected_count',
      order_field: 'aggregation.position',
      timeout_minutes: 15,
      timeout_policy: 'fail',
      output_kind: 'aggregated_pdf'
    },
    insert_blanks: {
      quantity_field: 'item.quantity',
      rules: [{
        label: 'Regola 1',
        enabled: true,
        target: 'all',
        position: 'after',
        after_page: 9,
        count: 1,
        repeat: false,
        interval: 0,
        min_quantity: 0,
        max_quantity: 0
      }],
      output_kind: 'blank_padded_pdf'
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
      action_name: 'azione',
      width_mm: 0,
      height_mm: 0,
      dpi: 300,
      resample_on_dpi_change: false,
      output_kind: 'photoshop_pdf'
    },
    illustrator: {
      agent_key: '',
      script_mode: 'template',
      script_name: 'plettri/plettro2.jsx',
      template_path: 'plettri/STANDARD.ai',
      pdf_preset: 'PDF PLANCE',
      output_kind: 'unit_pdf'
    },
    step_repeat: {
      preset_source: 'fixed',
      preset_code: 'STANDARD_MONO',
      preset_variable: 'variables.imposition_preset',
      output_kind: 'imposition_pdf'
    },
    barcode: {
      data_field: 'order.code',
      width_mm: 90,
      height_mm: 29,
      bar_height_mm: 16,
      font_size_pt: 18,
      text_distance_pt: 6,
      bar_width: 0.75,
      output_kind: 'barcode_pdf'
    },
    hot_folder: {
      destination_code: '{{machine.destination_code}}',
      artifact_kind: 'source',
      filename: '{{file.filename}}',
      output_kind: 'delivered'
    },
    label_printer: {
      destination_code: '{{machine.label_destination_code}}',
      artifact_kind: 'barcode_pdf',
      output_kind: 'printed_label'
    },
    approval: {},
    handoff: {target_flow_id: ''},
    finish: {result_artifact_kind: ''}
  };

  const simpleConfigSchemas = {
    select_resource: [
      {
        key: 'asset_type',
        label: 'Tipo di risorsa',
        choices: [
          ['print', 'File di stampa'],
          ['cut', 'File di taglio'],
          ['varnish', 'Verniciatura'],
          ['white', 'Bianco'],
          ['{{variables.asset_type}}', 'Leggi da una variabile']
        ],
        allowCustomChoice: true,
        help: 'Puoi usare qualsiasi tipo asset registrato nel gestionale.'
      },
      {key: 'asset_index', label: 'Numero della risorsa', type: 'number', default: 1},
      {
        key: 'resource_role',
        label: 'Nome logico',
        default: 'Graphics',
        help: 'Esempi: Graphics, CutContour, Varnish, White.'
      },
      {key: 'resource_position', label: 'Posizione nella composizione', type: 'number', default: 1},
      {
        key: 'missing_policy',
        label: 'Se la risorsa non esiste',
        choices: [
          ['fail', 'Ferma con errore'],
          ['route_missing', 'Usa l’uscita “Mancante”']
        ],
        default: 'fail'
      },
      {key: 'output_kind', label: 'Tipo risultato', default: 'selected_resource'}
    ],
    photoshop: [
      {
        key: 'agent_key',
        label: 'Macchina Adobe',
        choices: 'agents',
        help: 'Seleziona il Mac che eseguirà realmente questo blocco.'
      },
      {
        key: 'action_name',
        label: 'Azione Photoshop',
        help: 'Inserisci un nome fisso oppure una variabile, ad esempio {{operation.selected_photoshop_action}}.'
      },
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
      {
        key: 'resample_on_dpi_change',
        label: 'Ricampiona quando cambia il DPI',
        choices: [
          [false, 'No · cambia solo il DPI'],
          [true, 'Sì · ricampiona mantenendo la misura fisica']
        ],
        help: 'Usa Sì per convertire, ad esempio, un file da 150 a 300 DPI creando i pixel mancanti. Con larghezza e altezza compilate il ricampionamento è già automatico.'
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
        key: 'script_mode',
        label: 'Modalità di esecuzione',
        choices: [
          ['template', 'Script con maschera Illustrator'],
          ['document', 'Esegui script sul documento aperto']
        ],
        default: 'template',
        help: 'La seconda modalità serve per elaborazioni generiche come taglio, verniciatura o composizione livelli.'
      },
      {
        key: 'script_name',
        label: 'Script JSX Illustrator',
        choices: 'illustrator_scripts',
        allowCustomChoice: true,
        default: 'plettri/plettro2.jsx',
        help: 'Scegli uno script rilevato oppure inserisci un percorso relativo, ad esempio plettri/plettro2.jsx, o una variabile come {{variables.illustrator_script}}.'
      },
      {
        key: 'template_path',
        label: 'Maschera Illustrator',
        choices: 'illustrator_templates',
        allowCustomChoice: true,
        default: 'plettri/STANDARD.ai',
        help: 'Richiesta soltanto nella modalità “Script con maschera”. Usa il percorso relativo mostrato nell’elenco, comprese le eventuali sottocartelle.'
      },
      {
        key: 'pdf_preset',
        label: 'Preset PDF Illustrator',
        default: 'PDF PLANCE',
        help: 'Inserisci un nome fisso, ad esempio PDF PLANCE, oppure una variabile come {{variables.illustrator_pdf_preset}}.'
      },
      {key: 'output_kind', label: 'Tipo risultato', default: 'unit_pdf'}
    ],
    duplicate_pages: [
      {
        key: 'copies_field',
        label: 'Numero di pagine da',
        choices: [
          ['variables.production_copies', 'Copie calcolate'],
          ['item.quantity', 'Quantità di lavorazione'],
          ['item.ordered_quantity', 'Quantità ordinata originale']
        ],
        default: 'variables.production_copies'
      },
      {key: 'output_kind', label: 'Tipo risultato', default: 'multipage_pdf'}
    ],
    pdf_label: [
      {
        key: 'text',
        label: 'Testo da inserire',
        default: '{{order.code}}',
        help: 'Puoi usare variabili come {{order.code}}, {{item.sku}} e {{item.position}}.'
      },
      {
        key: 'anchor',
        label: 'Posizione',
        choices: [
          ['top_left', 'In alto a sinistra'],
          ['top_center', 'In alto al centro'],
          ['top_right', 'In alto a destra'],
          ['bottom_left', 'In basso a sinistra'],
          ['bottom_center', 'In basso al centro'],
          ['bottom_right', 'In basso a destra']
        ],
        default: 'top_left'
      },
      {key: 'font', label: 'Font PDF', default: 'Times-Roman'},
      {key: 'font_size_pt', label: 'Dimensione testo (pt)', type: 'number', default: 18},
      {key: 'background_color', label: 'Sfondo etichetta', default: '#222222'},
      {key: 'text_color', label: 'Colore testo', default: '#ffffff'},
      {key: 'padding_x_mm', label: 'Margine orizzontale (mm)', type: 'number', default: 2},
      {key: 'padding_y_mm', label: 'Margine verticale (mm)', type: 'number', default: 1.5},
      {key: 'offset_x_mm', label: 'Spostamento orizzontale (mm)', type: 'number', default: 0},
      {key: 'offset_y_mm', label: 'Spostamento verticale (mm)', type: 'number', default: 5},
      {key: 'output_kind', label: 'Tipo risultato', default: 'labeled_pdf'}
    ],
    resize_pdf: [
      {key: 'width_mm', label: 'Larghezza finale (mm)', type: 'number', default: 297},
      {key: 'height_mm', label: 'Altezza finale (mm)', type: 'number', default: 210},
      {
        key: 'mode',
        label: 'Adattamento contenuto',
        choices: [
          ['contain', 'Mantieni proporzioni'],
          ['stretch', 'Adatta esattamente al foglio'],
          ['{{variables.label_resize_mode}}', 'Leggi dalla variabile del flusso']
        ],
        default: 'contain'
      },
      {key: 'output_kind', label: 'Tipo risultato', default: 'resized_pdf'}
    ],
    collect_group: [
      {
        key: 'group_field',
        label: 'Raggruppa usando',
        choices: [
          ['aggregation.token', 'Lavoro aggregato (consigliato)'],
          ['aggregation.id', 'ID lavoro aggregato'],
          ['order.code', 'Codice ordine'],
          ['operation.id', 'Identificativo operazione'],
          ['operation.action_batch_id', 'Batch file della stessa azione'],
          ['runtime.root_run_id', 'Esecuzione corrente']
        ],
        default: 'aggregation.token',
        help: 'Tutti i file con lo stesso valore entreranno nella stessa raccolta.'
      },
      {
        key: 'expected_count',
        label: 'Numero fisso di file attesi',
        type: 'number',
        default: 0,
        help: 'Usa 0 per leggere il numero dal campo seguente.'
      },
      {
        key: 'expected_count_field',
        label: 'Numero di file attesi da',
        choices: [
          ['aggregation.expected_count', 'Righe del lavoro aggregato'],
          ['file.count', 'Numero file dell’azione']
        ],
        default: 'aggregation.expected_count'
      },
      {
        key: 'order_field',
        label: 'Ordina i file usando',
        choices: [
          ['aggregation.position', 'Posizione nel lavoro'],
          ['file.index', 'Indice file'],
          ['item.position', 'Posizione riga ordine'],
          ['file.resource_position', 'Posizione della risorsa selezionata'],
          ['variables.resource_position', 'Posizione salvata dal flusso']
        ],
        default: 'aggregation.position'
      },
      {
        key: 'consistency_field',
        label: 'Verifica compatibilità usando',
        default: '',
        help: 'Tutte le righe devono avere lo stesso valore. Lascia vuoto per disattivare il controllo.'
      },
      {
        key: 'timeout_minutes',
        label: 'Attesa massima (minuti)',
        type: 'number',
        default: 15
      },
      {
        key: 'timeout_policy',
        label: 'Se il gruppo è incompleto',
        choices: [
          ['fail', 'Ferma con errore (consigliato)'],
          ['process_received', 'Procedi con i file ricevuti']
        ],
        default: 'fail'
      },
      {key: 'output_kind', label: 'Tipo risultato', default: 'aggregated_pdf'}
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
      {
        key: 'preset_source',
        label: 'Selezione preset',
        choices: [
          ['fixed', 'Plancia fissa'],
          ['variable', 'Preset indicato da una variabile']
        ],
        default: 'fixed'
      },
      {
        key: 'preset_code',
        label: 'Plancia pubblicata',
        choices: 'imposition',
        help: 'La plancia viene progettata e pubblicata nello Studio di imposizione.'
      },
      {
        key: 'preset_variable',
        label: 'Variabile contenente il preset',
        default: 'variables.imposition_preset',
        help: 'Usata quando “Selezione preset” è impostata su variabile.'
      },
      {key: 'output_kind', label: 'Tipo risultato', default: 'imposition_pdf'}
    ],
    barcode: [
      {key: 'data_field', label: 'Valore barcode', choices: 'fields', default: 'order.code'},
      {key: 'width_mm', label: 'Larghezza (mm)', type: 'number', default: 90},
      {key: 'height_mm', label: 'Altezza (mm)', type: 'number', default: 29},
      {key: 'bar_height_mm', label: 'Altezza barre (mm)', type: 'number', default: 16},
      {key: 'font_size_pt', label: 'Dimensione numero (pt)', type: 'number', default: 18,
        help: 'Dimensione del codice ordine stampato sotto le barre.'},
      {key: 'text_distance_pt', label: 'Distanza testo (px)', type: 'number', default: 6,
        help: 'Spazio aggiuntivo tra le barre e il codice ordine.'},
      {
        key: 'bar_width',
        label: 'Spessore barre (mm)',
        type: 'number',
        default: 0.75,
        help: 'Aumenta o riduce la larghezza complessiva del barcode.'
      },
      {key: 'output_kind', label: 'Tipo risultato', default: 'barcode_pdf'}
    ],
    hot_folder: [
      {
        key: 'destination_code',
        label: 'Hot folder',
        choices: 'network_destinations',
        help: 'La cartella deve essere configurata nel menu Destinazioni.'
      },
      {key: 'artifact_kind', label: 'File da consegnare'},
      {
        key: 'filename',
        label: 'Nome file',
        default: '{{order.code}}-output.pdf',
        help: 'Puoi usare {{order.code}}, {{item.sku}} e {{file.filename}}.'
      },
      {key: 'output_kind', label: 'Tipo risultato', default: 'delivered'}
    ],
    label_printer: [
      {
        key: 'destination_code',
        label: 'Stampante etichette',
        choices: 'printer_destinations',
        help: 'La coda CUPS e il formato si configurano una sola volta nel menu Destinazioni.'
      },
      {key: 'artifact_kind', label: 'PDF etichetta da stampare', default: 'barcode_pdf'},
      {key: 'output_kind', label: 'Tipo risultato', default: 'printed_label'}
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

  function snapToGrid(value) {
    return Math.max(GRID_SIZE, Math.round(Number(value || 0) / GRID_SIZE) * GRID_SIZE);
  }

  function clampZoom(value) {
    return Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, value));
  }

  function canvasSize() {
    return state.graph.nodes.reduce((size, node) => ({
      width: Math.max(size.width, Number(node.position?.x || 0) + 500),
      height: Math.max(size.height, Number(node.position?.y || 0) + 300)
    }), {width: CANVAS_WIDTH, height: CANVAS_HEIGHT});
  }

  function resizeCanvas() {
    const size = canvasSize();
    canvas.style.width = `${size.width * state.zoom}px`;
    canvas.style.height = `${size.height * state.zoom}px`;
    canvasContent.style.width = `${size.width}px`;
    canvasContent.style.height = `${size.height}px`;
  }

  function applyZoom(nextZoom, options = {}) {
    const previousZoom = state.zoom;
    const zoom = clampZoom(nextZoom);
    const centerX = scrollArea.scrollLeft + scrollArea.clientWidth / 2;
    const centerY = scrollArea.scrollTop + scrollArea.clientHeight / 2;
    const contentX = centerX / previousZoom;
    const contentY = centerY / previousZoom;
    state.zoom = zoom;
    resizeCanvas();
    canvasContent.style.transform = `scale(${zoom})`;
    document.getElementById('reset-zoom-automation').textContent = `${Math.round(zoom * 100)}%`;
    if (options.keepCenter !== false) {
      scrollArea.scrollLeft = contentX * zoom - scrollArea.clientWidth / 2;
      scrollArea.scrollTop = contentY * zoom - scrollArea.clientHeight / 2;
    }
  }

  function graphBounds() {
    if (!state.graph.nodes.length) return {left: 0, top: 0, right: 800, bottom: 500};
    const elements = new Map(
      Array.from(nodesLayer.querySelectorAll('.automation-node')).map((element) => [
        element.dataset.nodeId,
        element
      ])
    );
    return state.graph.nodes.reduce((bounds, node) => {
      const element = elements.get(node.id);
      const x = Number(node.position?.x || 0);
      const y = Number(node.position?.y || 0);
      return {
        left: Math.min(bounds.left, x),
        top: Math.min(bounds.top, y),
        right: Math.max(bounds.right, x + (element?.offsetWidth || 194)),
        bottom: Math.max(bounds.bottom, y + (element?.offsetHeight || 92))
      };
    }, {left: Infinity, top: Infinity, right: 0, bottom: 0});
  }

  function fitAutomation() {
    const bounds = graphBounds();
    const padding = 80;
    const width = Math.max(1, bounds.right - bounds.left + padding * 2);
    const height = Math.max(1, bounds.bottom - bounds.top + padding * 2);
    const zoom = clampZoom(Math.min(
      scrollArea.clientWidth / width,
      scrollArea.clientHeight / height
    ));
    applyZoom(zoom, {keepCenter: false});
    scrollArea.scrollTo({
      left: Math.max(0, (bounds.left - padding) * zoom),
      top: Math.max(0, (bounds.top - padding) * zoom),
      behavior: 'smooth'
    });
  }

  function organizeAutomation() {
    if (!state.graph.nodes.length) return;
    const nodesById = new Map(state.graph.nodes.map((node) => [node.id, node]));
    const incoming = new Map(state.graph.nodes.map((node) => [node.id, []]));
    state.graph.edges.forEach((edge) => {
      if (nodesById.has(edge.source) && nodesById.has(edge.target)) {
        incoming.get(edge.target).push(edge.source);
      }
    });
    const depths = new Map();
    const depthFor = (nodeId, visiting = new Set()) => {
      if (depths.has(nodeId)) return depths.get(nodeId);
      if (visiting.has(nodeId)) return 0;
      const nextVisiting = new Set(visiting).add(nodeId);
      const parents = incoming.get(nodeId) || [];
      const depth = parents.length
        ? Math.max(...parents.map((parentId) => depthFor(parentId, nextVisiting))) + 1
        : 0;
      depths.set(nodeId, depth);
      return depth;
    };
    state.graph.nodes.forEach((node) => depthFor(node.id));
    const levels = new Map();
    const heights = new Map(
      Array.from(nodesLayer.querySelectorAll('.automation-node')).map((element) => [
        element.dataset.nodeId,
        element.offsetHeight
      ])
    );
    state.graph.nodes.forEach((node) => {
      const depth = depths.get(node.id) || 0;
      if (!levels.has(depth)) levels.set(depth, []);
      levels.get(depth).push(node);
    });
    Array.from(levels.entries()).sort(([a], [b]) => a - b).forEach(([depth, nodes]) => {
      const totalHeight = nodes.reduce((sum, node) => sum + (heights.get(node.id) || 92), 0) +
        Math.max(0, nodes.length - 1) * 72;
      let nextY = Math.max(40, (CANVAS_HEIGHT - totalHeight) / 2);
      nodes.forEach((node) => {
        node.position = {
          x: snapToGrid(180 + depth * 320),
          y: snapToGrid(nextY)
        };
        nextY += snapToGrid((heights.get(node.id) || 92) + 72);
      });
    });
    markDirty();
    render();
    applyZoom(state.zoom, {keepCenter: false});
    fitAutomation();
    showMessage('Blocchi ordinati sulla griglia. Salva la bozza per confermare.', 'success');
  }

  function portsFor(node) {
    if (node.type !== 'router') {
      const labels = {
        mono: 'Monofacciale',
        bifa: 'Bifacciale',
        incomplete: 'Incompleto',
        found: 'Trovata',
        missing: 'Mancante'
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
    if (value === 'quantity_fields') {
      return [
        ['item.quantity', 'Quantità di lavorazione'],
        ['item.ordered_quantity', 'Quantità ordinata originale']
      ];
    }
    if (value === 'fields') {
      return availableDataFields().map((field) => [field.path, field.label]);
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
    if (value === 'network_destinations' || value === 'printer_destinations') {
      const kind = value === 'network_destinations' ? 'network_folder' : 'ipp_printer';
      const choices = [
        ['', '-- Seleziona destinazione --'],
      ];
      if (value === 'network_destinations') {
        choices.push([
          '{{machine.destination_code}}',
          'Hot folder della macchina selezionata'
        ]);
      } else {
        choices.push([
          '{{machine.label_destination_code}}',
          'Stampante etichette della macchina selezionata'
        ]);
      }
      choices.push(
        ...state.destinations
          .filter((destination) => destination.kind === kind)
          .map((destination) => [
            destination.code,
            `${destination.name} (${destination.code})${destination.available ? ' · verificata' : ''}`
          ])
      );
      return choices;
    }
    if (value === 'flows') {
      return [
        ['', '-- Seleziona automazione pubblicata --'],
        ...state.flows.map((flow) => [flow.id, flow.name])
      ];
    }
    if (value === 'illustrator_scripts' || value === 'illustrator_templates') {
      const metadataKey = value === 'illustrator_scripts'
        ? 'illustrator_scripts'
        : 'illustrator_templates';
      const resources = state.agents.flatMap((agent) =>
        Array.isArray(agent.metadata?.[metadataKey]) ? agent.metadata[metadataKey] : []
      );
      const resourcePath = (entry) => {
        if (entry && typeof entry === 'object') {
          return String(entry.path || entry.relative_path || entry.name || '').trim();
        }
        return String(entry || '').trim();
      };
      const values = [...new Set(resources.map(resourcePath).filter(Boolean))].sort((a, b) =>
        a.localeCompare(b, undefined, { sensitivity: 'base', numeric: true })
      );
      return [
        ['', value === 'illustrator_scripts' ? '-- Seleziona script --' : '-- Seleziona maschera --'],
        ...values.map((name) => [name, name.includes('/') ? name.replaceAll('/', ' / ') : name])
      ];
    }
    return value || null;
  }

  function availableDataFields() {
    const fields = [...state.fieldCatalog];
    state.graph.nodes.forEach((node) => {
      if (node.type === 'set_variables') {
        Object.keys(node.config?.values || {}).forEach((key) => fields.push({
          path: `variables.${key}`,
          label: key,
          type: 'variable',
          category: 'Variabili del flusso',
          produced_by: node.label || node.id
        }));
      }
      if (node.type === 'calculate_copies' && node.config?.output_key) {
        fields.push({
          path: `variables.${node.config.output_key}`,
          label: node.config.output_key,
          type: 'number',
          category: 'Variabili del flusso',
          produced_by: node.label || node.id
        });
      }
      if (node.type === 'select_resource') {
        fields.push(
          {path: 'variables.resource_role', label: 'Nome logico della risorsa', type: 'text', category: 'Variabili del flusso', produced_by: node.label || node.id},
          {path: 'variables.resource_position', label: 'Posizione della risorsa', type: 'number', category: 'Variabili del flusso', produced_by: node.label || node.id}
        );
      }
    });
    const unique = new Map();
    fields.forEach((field) => {
      if (field?.path && !unique.has(field.path)) unique.set(field.path, field);
    });
    return [...unique.values()].sort((a, b) =>
      String(a.label || a.path).localeCompare(String(b.label || b.path), 'it', {sensitivity: 'base'})
    );
  }

  function renderDataCatalog() {
    const container = document.getElementById('automation-data-list');
    const search = document.getElementById('automation-data-search');
    if (!container) return;
    const query = String(search?.value || '').trim().toLowerCase();
    const visible = availableDataFields().filter((field) =>
      !query || `${field.label} ${field.path} ${field.category || ''}`.toLowerCase().includes(query)
    );
    const groups = new Map();
    visible.forEach((field) => {
      const root = field.path.split('.')[0];
      const fallback = {
        order: 'Ordine', item: 'Riga ordine', product: 'Prodotto', file: 'File',
        aggregation: 'Aggregazione', operation: 'Operazione', machine: 'Macchina',
        payload: 'Payload', variables: 'Variabili del flusso', runtime: 'Sistema'
      }[root] || 'Altro';
      const category = field.category || fallback;
      if (!groups.has(category)) groups.set(category, []);
      groups.get(category).push(field);
    });
    container.replaceChildren();
    [...groups.entries()].sort(([a], [b]) => a.localeCompare(b, 'it')).forEach(([category, fields]) => {
      const details = document.createElement('details');
      details.className = 'border rounded mb-2';
      details.open = query.length > 0;
      const summary = document.createElement('summary');
      summary.className = 'small px-2 py-1 bg-light';
      summary.textContent = `${category} (${fields.length})`;
      const list = document.createElement('div');
      list.className = 'p-1';
      fields.forEach((field) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'btn btn-sm btn-link text-start text-decoration-none w-100 px-2 py-1';
        button.title = field.produced_by ? `Prodotta da: ${field.produced_by}` : `Tipo: ${field.type || 'testo'}`;
        const readable = document.createElement('span');
        readable.className = 'd-block';
        readable.textContent = field.label || field.path;
        const technical = document.createElement('code');
        technical.className = 'small';
        technical.textContent = field.path;
        button.append(readable, technical);
        button.addEventListener('click', async () => {
          const expression = `{{${field.path}}}`;
          const active = document.activeElement;
          if (active && nodeConfigForm.contains(active) && ['INPUT', 'TEXTAREA'].includes(active.tagName)) {
            const start = active.selectionStart ?? active.value.length;
            const end = active.selectionEnd ?? start;
            active.value = `${active.value.slice(0, start)}${expression}${active.value.slice(end)}`;
            active.focus();
            active.setSelectionRange(start + expression.length, start + expression.length);
          } else {
            await navigator.clipboard?.writeText(expression);
            showMessage(`${expression} copiato.`, 'success');
          }
        });
        list.appendChild(button);
      });
      details.append(summary, list);
      container.appendChild(details);
    });
    if (!visible.length) container.innerHTML = '<div class="small text-muted">Nessun dato trovato.</div>';
  }

  function configField(field, value, role = field.key) {
    const wrapper = document.createElement('div');
    wrapper.className = 'mb-2';
    const label = document.createElement('label');
    label.className = 'form-label small mb-1';
    label.textContent = field.label;
    const choices = choicesFor(field.choices);
    let input;
    if (choices && field.allowCustomChoice) {
      input = document.createElement('input');
      input.className = 'form-control form-control-sm';
      input.type = 'text';
      input.value = value ?? field.default ?? '';
      const datalist = document.createElement('datalist');
      datalist.id = `automation-options-${field.key}-${Math.random().toString(36).slice(2)}`;
      choices
        .filter(([choiceValue]) => choiceValue !== '')
        .forEach(([choiceValue, choiceLabel]) => {
          const option = document.createElement('option');
          option.value = choiceValue;
          option.label = choiceLabel;
          datalist.appendChild(option);
        });
      input.setAttribute('list', datalist.id);
      wrapper.append(label, input, datalist);
    } else if (choices) {
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
    if (!field.allowCustomChoice) wrapper.append(label, input);
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
    const ruleField = String(rule.field || 'item.sku');
    const manualVariable = ruleField.startsWith('variables.') ? ruleField : '';
    const selectedField = manualVariable ? 'item.sku' : ruleField;
    card.append(
      heading,
      configField({label: 'Campo disponibile', choices: 'fields'}, selectedField, 'case_field'),
      configField({
        label: 'Variabile del flusso (opzionale)',
        help: 'Compilalo solo per leggere una variabile runtime, ad esempio variables.plancia. Se compilato, sostituisce il campo selezionato sopra.'
      }, manualVariable, 'case_variable'),
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

  function renumberBlankRules(container) {
    container.querySelectorAll('.automation-blank-rule').forEach((card, index) => {
      const title = card.querySelector('.automation-blank-rule-title');
      if (title) title.textContent = `Regola ${index + 1}`;
    });
  }

  function appendBlankRule(container, rule = {}) {
    const card = document.createElement('div');
    card.className = 'automation-blank-rule border rounded p-2 mb-3 bg-light';
    const heading = document.createElement('div');
    heading.className = 'd-flex align-items-center justify-content-between gap-2 mb-2';
    const title = document.createElement('strong');
    title.className = 'automation-blank-rule-title small';
    const actions = document.createElement('div');
    actions.className = 'btn-group btn-group-sm';
    const moveUp = document.createElement('button');
    moveUp.type = 'button';
    moveUp.className = 'btn btn-outline-secondary py-0 px-2';
    moveUp.title = 'Sposta prima';
    moveUp.textContent = '↑';
    moveUp.addEventListener('click', () => {
      if (card.previousElementSibling) {
        container.insertBefore(card, card.previousElementSibling);
        renumberBlankRules(container);
      }
    });
    const moveDown = document.createElement('button');
    moveDown.type = 'button';
    moveDown.className = 'btn btn-outline-secondary py-0 px-2';
    moveDown.title = 'Sposta dopo';
    moveDown.textContent = '↓';
    moveDown.addEventListener('click', () => {
      if (card.nextElementSibling) {
        container.insertBefore(card.nextElementSibling, card);
        renumberBlankRules(container);
      }
    });
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'btn btn-outline-danger py-0 px-2';
    remove.title = 'Elimina regola';
    remove.textContent = '×';
    remove.addEventListener('click', () => {
      card.remove();
      renumberBlankRules(container);
    });
    actions.append(moveUp, moveDown, remove);
    heading.append(title, actions);

    const positionField = configField({
      label: 'Dove inserire',
      choices: [
        ['start', 'All’inizio'],
        ['after', 'Dopo una pagina'],
        ['end', 'Alla fine']
      ]
    }, rule.position || 'after', 'blank_position');
    const afterField = configField({
      label: 'Dopo la pagina',
      type: 'number',
      default: 1,
      help: 'La numerazione considera le pagine presenti prima di questa regola.'
    }, rule.after_page ?? 1, 'blank_after_page');
    afterField.dataset.blankAfterFields = '1';
    const repeatField = configField({
      label: 'Ripetizione',
      choices: [
        ['false', 'Una sola volta'],
        ['true', 'Ripeti a intervalli']
      ]
    }, String(rule.repeat === true), 'blank_repeat');
    repeatField.dataset.blankAfterFields = '1';
    const intervalField = configField({
      label: 'Ogni quante pagine',
      type: 'number',
      default: 1,
      help: 'Esempio: dopo pagina 9, ogni 9 pagine.'
    }, rule.interval || 1, 'blank_interval');
    intervalField.dataset.blankIntervalField = '1';

    card.append(
      heading,
      configField({label: 'Nome della regola'}, rule.label || '', 'blank_label'),
      configField({
        label: 'Applica a',
        choices: [
          ['all', 'Documento intero / entrambi i lati'],
          ['front', 'Solo fronte'],
          ['back', 'Solo retro']
        ],
        help: 'Su un PDF bifacciale “entrambi i lati” applica la stessa regola separatamente a fronte e retro.'
      }, rule.target || 'all', 'blank_target'),
      configField({
        label: 'Stato',
        choices: [['true', 'Attiva'], ['false', 'Disattivata']]
      }, String(rule.enabled !== false), 'blank_enabled'),
      positionField,
      afterField,
      configField({
        label: 'Quante pagine vuote',
        type: 'number',
        default: 1
      }, rule.count ?? 1, 'blank_count'),
      repeatField,
      intervalField,
      configField({
        label: 'Quantità minima ordine',
        type: 'number',
        default: 0,
        help: '0 significa nessun limite minimo.'
      }, rule.min_quantity || 0, 'blank_min_quantity'),
      configField({
        label: 'Quantità massima ordine',
        type: 'number',
        default: 0,
        help: '0 significa nessun limite massimo.'
      }, rule.max_quantity || 0, 'blank_max_quantity')
    );

    const updateVisibility = () => {
      const isAfter = configValue('blank_position', card) === 'after';
      const repeats = configValue('blank_repeat', card) === 'true';
      card.querySelectorAll('[data-blank-after-fields]').forEach((element) => {
        element.hidden = !isAfter;
      });
      card.querySelector('[data-blank-interval-field]').hidden = !(isAfter && repeats);
    };
    card.querySelector('[data-config-role="blank_position"]').addEventListener('change', updateVisibility);
    card.querySelector('[data-config-role="blank_repeat"]').addEventListener('change', updateVisibility);
    container.appendChild(card);
    renumberBlankRules(container);
    updateVisibility();
  }

  function renderBlankPagesConfig(node) {
    configHint('Le regole vengono applicate dall’alto verso il basso. Nei PDF bifacciali fronte e retro restano gruppi separati, così le posizioni vuote rimangono allineate.');
    nodeConfigForm.appendChild(configField(
      {label: 'Quantità usata per le condizioni', choices: 'fields'},
      node.config?.quantity_field || 'item.quantity',
      'blank_quantity_field'
    ));
    const rules = document.createElement('div');
    rules.className = 'automation-blank-rules';
    (Array.isArray(node.config?.rules) ? node.config.rules : []).forEach((rule) => {
      appendBlankRule(rules, rule);
    });
    nodeConfigForm.appendChild(rules);
    const add = document.createElement('button');
    add.type = 'button';
    add.className = 'btn btn-sm btn-outline-primary w-100 mb-3';
    add.textContent = '+ Aggiungi regola';
    add.addEventListener('click', () => appendBlankRule(rules, {
      label: `Regola ${rules.querySelectorAll('.automation-blank-rule').length + 1}`,
      enabled: true,
      target: 'all',
      position: 'after',
      after_page: 1,
      count: 1,
      repeat: false,
      interval: 1,
      min_quantity: 0,
      max_quantity: 0
    }));
    nodeConfigForm.append(
      add,
      configField(
        {label: 'Tipo risultato', default: 'blank_padded_pdf'},
        node.config?.output_kind || 'blank_padded_pdf',
        'blank_output_kind'
      )
    );
  }

  function configList(value) {
    return String(value || 'any').split(/[;,]/).map((item) => item.trim()).filter(Boolean);
  }

  function triggerChoice(label, value, selected, kind) {
    const wrapper = document.createElement('div');
    wrapper.className = 'form-check mb-1';
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.className = 'form-check-input';
    input.id = `trigger-${kind}-${value}`;
    input.value = value;
    input.checked = selected;
    input.dataset.triggerKind = kind;
    const text = document.createElement('label');
    text.className = 'form-check-label small';
    text.htmlFor = input.id;
    text.textContent = label;
    wrapper.append(input, text);
    return wrapper;
  }

  function triggerChoiceGroup({title, help, kind, configured, choices, custom = false}) {
    const selected = configList(configured);
    const acceptsAny = selected.includes('any');
    const knownValues = choices.map((choice) => choice[0]);
    const section = document.createElement('fieldset');
    section.className = 'mb-3';
    const legend = document.createElement('legend');
    legend.className = 'form-label small fw-semibold mb-1';
    legend.textContent = title;
    const anyChoice = triggerChoice('Qualsiasi', 'any', acceptsAny, kind);
    section.append(legend, anyChoice);
    choices.forEach(([value, label]) => {
      section.appendChild(triggerChoice(label, value, !acceptsAny && selected.includes(value), kind));
    });

    if (custom) {
      const customValues = selected.filter((value) => value !== 'any' && !knownValues.includes(value));
      const customLabel = document.createElement('label');
      customLabel.className = 'form-label small mt-2 mb-1';
      customLabel.htmlFor = `trigger-${kind}-custom`;
      customLabel.textContent = 'Eventi personalizzati';
      const customInput = document.createElement('input');
      customInput.type = 'text';
      customInput.className = 'form-control form-control-sm';
      customInput.id = `trigger-${kind}-custom`;
      customInput.placeholder = 'artwork.approved; production.completed';
      customInput.value = customValues.join('; ');
      customInput.dataset.triggerCustom = kind;
      section.append(customLabel, customInput);
    }

    const helpText = document.createElement('div');
    helpText.className = 'form-text';
    helpText.textContent = help;
    section.appendChild(helpText);

    const updateDisabledState = () => {
      const anyInput = section.querySelector(`[data-trigger-kind="${kind}"][value="any"]`);
      section.querySelectorAll(`[data-trigger-kind="${kind}"]:not([value="any"])`).forEach((input) => {
        input.disabled = anyInput.checked;
        if (anyInput.checked) input.checked = false;
      });
      const customInput = section.querySelector(`[data-trigger-custom="${kind}"]`);
      if (customInput) customInput.disabled = anyInput.checked;
    };
    section.querySelectorAll(`[data-trigger-kind="${kind}"]`).forEach((input) => {
      input.addEventListener('change', () => {
        if (input.value !== 'any' && input.checked) {
          section.querySelector(`[data-trigger-kind="${kind}"][value="any"]`).checked = false;
        }
        updateDisabledState();
      });
    });
    updateDisabledState();
    return section;
  }

  function renderTriggerConfig(node) {
    configHint('Scegli quando può partire questa automazione e da dove può ricevere il lavoro.');
    nodeConfigForm.append(
      triggerChoiceGroup({
        title: 'Quando può partire',
        help: 'Per una prestampa normale seleziona Prestampa. Gli eventi personalizzati servono solo per casi aggiuntivi.',
        kind: 'event',
        configured: node.config?.operation_type,
        choices: [
          ['preprint', 'Prestampa'],
          ['print', 'Stampa'],
          ['label', 'Etichetta']
        ],
        custom: true
      }),
      triggerChoiceGroup({
        title: 'Da dove può partire',
        help: 'Per il primo flusso seleziona Flusso di stampa. Per la seconda parte seleziona Altra automazione.',
        kind: 'source',
        configured: node.config?.source_type,
        choices: [
          ['print_flow', 'Flusso di stampa'],
          ['handoff', 'Altra automazione'],
          ['manual', 'Avvio manuale o prova'],
          ['api', 'Chiamata API']
        ]
      })
    );
  }

  function collectTriggerValues(kind, custom = false) {
    const checked = Array.from(
      nodeConfigForm.querySelectorAll(`[data-trigger-kind="${kind}"]:checked`)
    ).map((input) => input.value);
    if (checked.includes('any')) return 'any';

    const values = [...checked];
    if (custom) {
      const customValue = nodeConfigForm.querySelector(`[data-trigger-custom="${kind}"]`)?.value || '';
      customValue.split(/[;,]/).map((value) => value.trim()).filter(Boolean).forEach((value) => {
        if (!/^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$/.test(value)) {
          throw new Error(`Codice evento personalizzato non valido: ${value}`);
        }
        if (!values.includes(value)) values.push(value);
      });
    }
    if (!values.length) throw new Error(`Seleziona almeno una voce in “${kind === 'event' ? 'Quando può partire' : 'Da dove può partire'}”.`);
    return values.join(';');
  }

  function renderNodeConfigForm(node) {
    nodeConfigForm.replaceChildren();
    if (node.type === 'trigger') {
      renderTriggerConfig(node);
      return;
    }
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
        configField({label: 'Quantità di partenza', choices: 'quantity_fields'}, node.config?.quantity_field || 'item.quantity', 'quantity_field'),
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
    if (node.type === 'insert_blanks') {
      renderBlankPagesConfig(node);
      return;
    }
    if (node.type === 'step_repeat') {
      configHint('Puoi scegliere un preset fisso oppure leggere il codice del preset da una variabile impostata nei blocchi precedenti.');
      const sourceField = configField(
        simpleConfigSchemas.step_repeat[0],
        node.config?.preset_source || 'fixed'
      );
      const fixedField = configField(
        simpleConfigSchemas.step_repeat[1],
        node.config?.preset_code
      );
      const variableField = configField(
        simpleConfigSchemas.step_repeat[2],
        node.config?.preset_variable || 'variables.imposition_preset'
      );
      const outputField = configField(
        simpleConfigSchemas.step_repeat[3],
        node.config?.output_kind
      );
      const updatePresetFields = () => {
        const variableMode = configValue('preset_source') === 'variable';
        fixedField.hidden = variableMode;
        variableField.hidden = !variableMode;
      };
      nodeConfigForm.append(sourceField, fixedField, variableField, outputField);
      sourceField.querySelector('[data-config-role="preset_source"]')
        .addEventListener('change', updatePresetFields);
      updatePresetFields();
      return;
    }
    if (node.type === 'illustrator') {
      configHint('Puoi usare Illustrator con una maschera oppure eseguire uno script direttamente sul documento corrente.');
      const fields = simpleConfigSchemas.illustrator.map((field) =>
        configField(field, node.config?.[field.key])
      );
      fields.forEach((field) => nodeConfigForm.appendChild(field));
      const modeInput = nodeConfigForm.querySelector('[data-config-role="script_mode"]');
      const templateInput = nodeConfigForm.querySelector('[data-config-role="template_path"]');
      const templateField = templateInput?.closest('.mb-2');
      const updateMode = () => {
        if (templateField) templateField.hidden = modeInput?.value === 'document';
      };
      modeInput?.addEventListener('change', updateMode);
      updateMode();
      return;
    }

    const schema = simpleConfigSchemas[node.type];
    if (!schema) {
      configHint('Questo blocco non richiede configurazione.');
      return;
    }
    if (node.type === 'pair_sides') {
      configHint('I file senza suffisso escono subito come monofacciali. I file fronte e retro vengono attesi, ordinati e uniti in un PDF a due pagine.');
    }
    if (node.type === 'collect_group') {
      configHint('Ogni esecuzione attende qui. Quando arrivano tutte le righe, i PDF vengono uniti nell’ordine scelto e il flusso prosegue una sola volta. Il controllo compatibilità impedisce di mescolare preset diversi.');
    }
    if (node.type === 'select_resource') {
      configHint('Seleziona un file allegato alla riga ordine usando il suo tipo. Il nome logico e la posizione potranno essere letti dai blocchi successivi.');
    }
    schema.forEach((field) => {
      nodeConfigForm.appendChild(configField(field, node.config?.[field.key]));
    });
  }

  function collectNodeConfig(node) {
    if (node.type === 'trigger') {
      return {
        operation_type: collectTriggerValues('event', true),
        source_type: collectTriggerValues('source')
      };
    }
    if (node.type === 'router') {
      return {
        cases: Array.from(nodeConfigForm.querySelectorAll('.automation-config-case')).map((card, index) => ({
          port: configValue('case_port', card) || `case_${index + 1}`,
          label: configValue('case_label', card) || `Condizione ${index + 1}`,
          field: configValue('case_variable', card).trim() || configValue('case_field', card) || 'item.sku',
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
    if (node.type === 'insert_blanks') {
      const rules = Array.from(
        nodeConfigForm.querySelectorAll('.automation-blank-rule')
      ).map((card, index) => {
        const count = Number(configValue('blank_count', card));
        const afterPage = Number(configValue('blank_after_page', card));
        const interval = Number(configValue('blank_interval', card));
        const minimum = Number(configValue('blank_min_quantity', card));
        const maximum = Number(configValue('blank_max_quantity', card));
        const position = configValue('blank_position', card) || 'after';
        const repeat = position === 'after' &&
          configValue('blank_repeat', card) === 'true';
        if (![count, afterPage, interval, minimum, maximum].every(Number.isFinite)) {
          throw new Error(`Valore numerico non valido nella regola ${index + 1}.`);
        }
        if (count < 0 || afterPage < 0 || minimum < 0 || maximum < 0) {
          throw new Error(`I valori della regola ${index + 1} non possono essere negativi.`);
        }
        if (repeat && interval < 1) {
          throw new Error(`Indica un intervallo nella regola ${index + 1}.`);
        }
        if (minimum > 0 && maximum > 0 && minimum > maximum) {
          throw new Error(`Intervallo quantità invertito nella regola ${index + 1}.`);
        }
        return {
          label: configValue('blank_label', card) || `Regola ${index + 1}`,
          enabled: configValue('blank_enabled', card) !== 'false',
          target: configValue('blank_target', card) || 'all',
          position,
          after_page: afterPage,
          count,
          repeat,
          interval: repeat ? interval : 0,
          min_quantity: minimum,
          max_quantity: maximum
        };
      });
      return {
        quantity_field: configValue('blank_quantity_field') || 'item.quantity',
        rules,
        output_kind: configValue('blank_output_kind') || 'blank_padded_pdf'
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
    const x = snapToGrid(position.x ?? (scrollArea.scrollLeft / state.zoom + 100));
    const y = snapToGrid(position.y ?? (
      scrollArea.scrollTop / state.zoom + 100 + (state.graph.nodes.length % 5) * GRID_SIZE
    ));
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

  function duplicateNode(requestedId = state.selectedNodeId) {
    const source = nodeFor(requestedId);
    if (!source) return;
    if (source.type === 'trigger') {
      showMessage('Il flusso può avere un solo blocco Ingresso.', 'error');
      return;
    }
    const id = uniqueId(source.type);
    const duplicate = JSON.parse(JSON.stringify(source));
    duplicate.id = id;
    duplicate.label = `${source.label || source.id} copia`;
    duplicate.position = {
      x: snapToGrid(Number(source.position?.x || 0) + GRID_SIZE * 2),
      y: snapToGrid(Number(source.position?.y || 0) + GRID_SIZE * 2)
    };
    state.graph.nodes.push(duplicate);
    state.selectedNodeId = id;
    markDirty();
    render();
    showMessage('Blocco duplicato senza collegamenti. Posizionalo e collegalo dove serve.', 'success');
  }

  function selectNode(id, options = {}) {
    state.selectedNodeId = id;
    if (!options.keepMultiSelection) state.selectedNodeIds = new Set(id ? [id] : []);
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
    state.selectedNodeIds = new Set([id]);
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
    const sourceNode = nodeFor(pending.source);
    const duplicate = state.graph.edges.some((edge) => (
      edge.source === pending.source &&
      edge.target === target &&
      String(edge.source_port || 'default') === pending.source_port
    ));
    if (duplicate) {
      state.pendingConnection = null;
      showMessage('Questo collegamento esiste già.', 'error');
      renderNodes();
      return;
    }
    if (sourceNode?.type !== 'fork') {
      state.graph.edges = state.graph.edges.filter(
        (edge) => !(edge.source === pending.source && String(edge.source_port || 'default') === pending.source_port)
      );
    }
    state.graph.edges.push({
      id: `edge_${Date.now()}_${Math.random().toString(16).slice(2, 7)}`,
      source: pending.source,
      target,
      source_port: pending.source_port
    });
    state.pendingConnection = null;
    markDirty();
    render();
    if (sourceNode?.type === 'fork') {
      const branches = state.graph.edges.filter((edge) => edge.source === pending.source).length;
      showMessage(`Diramazione aggiornata: ${branches} rami collegati.`, 'success');
    }
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
      if (state.selectedNodeIds.has(node.id) || state.selectedNodeId === node.id) element.classList.add('is-selected');
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
      const duplicate = document.createElement('button');
      duplicate.type = 'button';
      duplicate.className = 'automation-node-action automation-node-duplicate';
      duplicate.title = 'Duplica blocco';
      duplicate.setAttribute('aria-label', `Duplica blocco ${node.label || node.id}`);
      duplicate.innerHTML = '<i class="fas fa-copy"></i>';
      duplicate.addEventListener('pointerdown', (event) => event.stopPropagation());
      duplicate.addEventListener('click', (event) => {
        event.stopPropagation();
        duplicateNode(node.id);
      });
      if (node.type === 'trigger') duplicate.disabled = true;
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'automation-node-action automation-node-delete';
      remove.title = 'Elimina blocco';
      remove.setAttribute('aria-label', `Elimina blocco ${node.label || node.id}`);
      remove.innerHTML = '<i class="fas fa-trash"></i>';
      remove.addEventListener('pointerdown', (event) => event.stopPropagation());
      remove.addEventListener('click', (event) => {
        event.stopPropagation();
        deleteNode(node.id);
      });
      header.append(icon, label, duplicate, remove);

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

      element.addEventListener('click', (event) => {
        if (state.pendingConnection && state.pendingConnection.source !== node.id) {
          finishConnection(node.id);
          return;
        }
        if (event.shiftKey || event.metaKey || event.ctrlKey) {
          if (state.selectedNodeIds.has(node.id)) state.selectedNodeIds.delete(node.id);
          else state.selectedNodeIds.add(node.id);
          state.selectedNodeId = node.id;
          selectNode(node.id, {keepMultiSelection: true});
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
      if (!state.selectedNodeIds.has(node.id)) {
        markNodeSelected(element, node.id);
        selectNode(node.id, {render: false});
      } else {
        state.selectedNodeId = node.id;
      }
      const startX = event.clientX;
      const startY = event.clientY;
      const selectedNodes = state.graph.nodes.filter((candidate) => state.selectedNodeIds.has(candidate.id));
      const origins = new Map(selectedNodes.map((candidate) => [candidate.id, {
        x: Number(candidate.position?.x || 0), y: Number(candidate.position?.y || 0)
      }]));
      let moved = false;

      const onMove = (moveEvent) => {
        if (moveEvent.pointerId !== event.pointerId) return;
        const deltaX = (moveEvent.clientX - startX) / state.zoom;
        const deltaY = (moveEvent.clientY - startY) / state.zoom;
        if (!moved && Math.abs(deltaX) < 3 && Math.abs(deltaY) < 3) return;
        moved = true;
        moveEvent.preventDefault();
        selectedNodes.forEach((candidate) => {
          const origin = origins.get(candidate.id);
          candidate.position = {
            x: snapToGrid(origin.x + deltaX),
            y: snapToGrid(origin.y + deltaY)
          };
          const candidateElement = nodesLayer.querySelector(`[data-node-id="${candidate.id}"]`);
          if (candidateElement) {
            candidateElement.style.left = `${candidate.position.x}px`;
            candidateElement.style.top = `${candidate.position.y}px`;
          }
        });
        renderEdges();
      };
      const onUp = (upEvent) => {
        if (upEvent.pointerId !== event.pointerId) return;
        window.removeEventListener('pointermove', onMove);
        window.removeEventListener('pointerup', onUp);
        window.removeEventListener('pointercancel', onUp);
        element.classList.remove('is-dragging');
        if (moved) {
          resizeCanvas();
          markDirty();
        }
      };
      element.classList.add('is-dragging');
      window.addEventListener('pointermove', onMove, {passive: false});
      window.addEventListener('pointerup', onUp);
      window.addEventListener('pointercancel', onUp);
    });
  }

  function enableMarqueeSelection() {
    let start = null;
    let box = null;
    canvasContent.addEventListener('pointerdown', (event) => {
      const target = event.target instanceof Element ? event.target : null;
      if (event.button !== 0 || target?.closest('.automation-node, .automation-edge')) return;
      event.preventDefault();
      const rect = canvas.getBoundingClientRect();
      start = {x: event.clientX - rect.left, y: event.clientY - rect.top};
      const additive = event.shiftKey || event.metaKey || event.ctrlKey;
      const initialSelection = additive ? new Set(state.selectedNodeIds) : new Set();
      box = document.createElement('div');
      box.className = 'automation-selection-box';
      canvas.appendChild(box);
      const move = (moveEvent) => {
        if (!start) return;
        const x = moveEvent.clientX - rect.left;
        const y = moveEvent.clientY - rect.top;
        const left = Math.min(start.x, x), top = Math.min(start.y, y);
        box.style.left = `${left}px`; box.style.top = `${top}px`;
        box.style.width = `${Math.abs(x - start.x)}px`; box.style.height = `${Math.abs(y - start.y)}px`;
      };
      const up = (upEvent) => {
        if (!start) return;
        const x = upEvent.clientX - rect.left, y = upEvent.clientY - rect.top;
        const left = Math.min(start.x, x), top = Math.min(start.y, y);
        const right = Math.max(start.x, x), bottom = Math.max(start.y, y);
        const selected = state.graph.nodes.filter((candidate) => {
          const element = nodesLayer.querySelector(`[data-node-id="${candidate.id}"]`);
          if (!element) return false;
          const r = element.getBoundingClientRect();
          const ex = r.left - rect.left, ey = r.top - rect.top;
          return ex < right && ey < bottom && ex + r.width > left && ey + r.height > top;
        });
        const selectedIds = new Set(selected.map((candidate) => candidate.id));
        state.selectedNodeIds = additive
          ? new Set([...initialSelection, ...selectedIds])
          : selectedIds;
        state.selectedNodeId = selected[0]?.id || [...state.selectedNodeIds][0] || null;
        if (state.selectedNodeId) selectNode(state.selectedNodeId, {keepMultiSelection: true});
        else selectNode(null);
        box.remove(); box = null; start = null;
        window.removeEventListener('pointermove', move);
        window.removeEventListener('pointerup', up);
      };
      window.addEventListener('pointermove', move, {passive: false});
      window.addEventListener('pointerup', up, {once: true});
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
    renderDataCatalog();
    resizeCanvas();
    if (state.selectedNodeId) selectNode(state.selectedNodeId, {keepMultiSelection: true});
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
  document.getElementById('duplicate-node').addEventListener('click', () => duplicateNode());
  document.getElementById('save-automation').addEventListener('click', save);
  document.getElementById('validate-automation').addEventListener('click', validate);
  document.getElementById('organize-automation').addEventListener('click', organizeAutomation);
  document.getElementById('zoom-out-automation').addEventListener('click', () => applyZoom(state.zoom - 0.1));
  document.getElementById('zoom-in-automation').addEventListener('click', () => applyZoom(state.zoom + 0.1));
  document.getElementById('reset-zoom-automation').addEventListener('click', () => applyZoom(1));
  document.getElementById('fit-automation').addEventListener('click', fitAutomation);
  enableMarqueeSelection();

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
      x: (event.clientX - canvasRect.left) / state.zoom - 97,
      y: (event.clientY - canvasRect.top) / state.zoom - 30
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

  document.getElementById('automation-data-search')?.addEventListener('input', renderDataCatalog);

  window.addEventListener('beforeunload', (event) => {
    if (!state.dirty) return;
    event.preventDefault();
    event.returnValue = '';
  });

  renderPalette();
  applyZoom(1, {keepCenter: false});
  render();
})();
