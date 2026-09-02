<?php
// File: includes/settings.php

// Evita accessi diretti
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

/**
 * Agganciamo l'admin_menu e admin_init per le impostazioni
 */
add_action('admin_menu', 'wos_add_submenu_under_psoft');
add_action('admin_init', 'wos_settings_init');

/**
 * Aggiunge un sottomenu sotto "PSoft" (slug ipotetico: psoft_main_menu).
 */
function wos_add_submenu_under_psoft() {
    add_submenu_page(
        'psoft_main_menu',
        __('WP Order Sync', 'wp-order-sync'),
        __('Order Sync', 'wp-order-sync'),
        'manage_options',
        'wp-order-sync',
        'wos_options_page'
    );
}

/**
 * Inizializza i setting (uguale a prima).
 */
function wos_settings_init() {
    register_setting('wos_settings_group', 'wos_settings', 'sanitize_wos_settings');

    add_settings_section(
        'wos_settings_section',
        __('Impostazioni FTP', 'wp-order-sync'),
        'wos_settings_section_callback',
        'wos_settings_group'
    );

    add_settings_field(
        'wos_site_name',
        __('Nome del Sito', 'wp-order-sync'),
        'wos_site_name_render',
        'wos_settings_group',
        'wos_settings_section'
    );

    add_settings_field(
        'wos_ftp_host',
        __('Host FTP', 'wp-order-sync'),
        'wos_ftp_host_render',
        'wos_settings_group',
        'wos_settings_section'
    );

    add_settings_field(
        'wos_ftp_port',
        __('Porta FTP', 'wp-order-sync'),
        'wos_ftp_port_render',
        'wos_settings_group',
        'wos_settings_section'
    );

    add_settings_field(
        'wos_ftp_username',
        __('Nome Utente FTP', 'wp-order-sync'),
        'wos_ftp_username_render',
        'wos_settings_group',
        'wos_settings_section'
    );

    add_settings_field(
        'wos_ftp_password',
        __('Password FTP', 'wp-order-sync'),
        'wos_ftp_password_render',
        'wos_settings_group',
        'wos_settings_section'
    );

    add_settings_field(
        'wos_ftp_path',
        __('Percorso Cartella FTP', 'wp-order-sync'),
        'wos_ftp_path_render',
        'wos_settings_group',
        'wos_settings_section'
    );

    add_settings_field(
        'wos_crm_api_url',
        __('Magenta CRM Webhook URL', 'wp-order-sync'),
        'wos_crm_api_url_render',
        'wos_settings_group',
        'wos_settings_section'
    );

    add_settings_field(
        'wos_crm_api_key',
        __('Magenta CRM Webhook API Key', 'wp-order-sync'),
        'wos_crm_api_key_render',
        'wos_settings_group',
        'wos_settings_section'
    );
}

/**
 * Sanitizza i campi del form
 */
function sanitize_wos_settings($input) {
    $sanitized = [];
    if (isset($input['wos_site_name'])) {
        $sanitized['wos_site_name'] = sanitize_text_field($input['wos_site_name']);
    }
    if (isset($input['wos_ftp_host'])) {
        $sanitized['wos_ftp_host'] = sanitize_text_field($input['wos_ftp_host']);
    }
    if (isset($input['wos_ftp_port'])) {
        $sanitized['wos_ftp_port'] = intval($input['wos_ftp_port']);
    }
    if (isset($input['wos_ftp_username'])) {
        $sanitized['wos_ftp_username'] = sanitize_text_field($input['wos_ftp_username']);
    }
    if (isset($input['wos_ftp_password'])) {
        $sanitized['wos_ftp_password'] = sanitize_text_field($input['wos_ftp_password']);
    }
    if (isset($input['wos_ftp_path'])) {
        $sanitized['wos_ftp_path'] = sanitize_text_field($input['wos_ftp_path']);
    }
    if (isset($input['wos_crm_api_url'])) {
        $sanitized['wos_crm_api_url'] = sanitize_url($input['wos_crm_api_url']);
    }
    if (isset($input['wos_crm_api_key'])) {
        $sanitized['wos_crm_api_key'] = sanitize_text_field($input['wos_crm_api_key']);
    }
    return $sanitized;
}

/**
 * Render della sezione
 */
function wos_settings_section_callback() {
    echo __('Configura le credenziali FTP per la produzione e l\'API Webhook per il CRM.', 'wp-order-sync');
}

/**
 * Render dei vari campi (uguali a prima).
 */
function wos_site_name_render() {
    $options = get_option('wos_settings');
    ?>
    <input type="text" name="wos_settings[wos_site_name]"
           value="<?php echo esc_attr($options['wos_site_name'] ?? ''); ?>" size="50">
    <?php
}

function wos_ftp_host_render() {
    $options = get_option('wos_settings');
    ?>
    <input type="text" name="wos_settings[wos_ftp_host]"
           value="<?php echo esc_attr($options['wos_ftp_host'] ?? ''); ?>" size="50">
    <?php
}

function wos_ftp_port_render() {
    $options = get_option('wos_settings');
    $port = isset($options['wos_ftp_port']) ? intval($options['wos_ftp_port']) : 21;
    ?>
    <input type="number" name="wos_settings[wos_ftp_port]"
           value="<?php echo esc_attr($port); ?>" size="10">
    <?php
}

function wos_ftp_username_render() {
    $options = get_option('wos_settings');
    ?>
    <input type="text" name="wos_settings[wos_ftp_username]"
           value="<?php echo esc_attr($options['wos_ftp_username'] ?? ''); ?>" size="50">
    <?php
}

function wos_ftp_password_render() {
    $options = get_option('wos_settings');
    ?>
    <input type="text" name="wos_settings[wos_ftp_password]"
           value="<?php echo esc_attr($options['wos_ftp_password'] ?? ''); ?>" size="50">
    <?php
}

function wos_ftp_path_render() {
    $options = get_option('wos_settings');
    ?>
    <input type="text" name="wos_settings[wos_ftp_path]"
           value="<?php echo esc_attr($options['wos_ftp_path'] ?? ''); ?>" size="50">
    <?php
}

function wos_crm_api_url_render() {
    $options = get_option('wos_settings');
    ?>
    <input type="url" name="wos_settings[wos_crm_api_url]"
           value="<?php echo esc_attr($options['wos_crm_api_url'] ?? ''); ?>" size="50">
    <p class="description"><?php _e('Indirizzo del webhook (es: http://ip:5001/api/v1/webhook/woocommerce)', 'wp-order-sync'); ?></p>
    <?php
}

function wos_crm_api_key_render() {
    $options = get_option('wos_settings');
    ?>
    <input type="password" name="wos_settings[wos_crm_api_key]"
           id="wos_crm_api_key"
           value="<?php echo esc_attr($options['wos_crm_api_key'] ?? ''); ?>" size="50">
    <button type="button" id="wos-test-api-conn" class="button secondary"><?php _e('Test Connessione', 'wp-order-sync'); ?></button>
    <span id="wos-api-test-result" style="margin-left: 10px; font-weight: bold;"></span>
    <p class="description"><?php _e('La Token/API Key impostata nel CRM.', 'wp-order-sync'); ?></p>
    <?php
}

/**
 * Handle AJAX request for syncing a batch of CRM data via FTP (with date filters)
 */
add_action('wp_ajax_wos_sync_crm_batch', 'wos_sync_crm_batch_ajax');
function wos_sync_crm_batch_ajax() {
    if (!current_user_can('manage_options')) {
        wp_send_json_error(['message' => __('Permesso negato.', 'wp-order-sync')]);
    }

    if (function_exists('set_time_limit')) {
        @set_time_limit(120);
    }

    $offset     = isset($_POST['offset']) ? intval($_POST['offset']) : 0;
    $date_from  = isset($_POST['date_from']) ? sanitize_text_field($_POST['date_from']) : '';
    $date_to    = isset($_POST['date_to']) ? sanitize_text_field($_POST['date_to']) : '';
    $batch_size = 20;

    $options      = get_option('wos_settings');
    $api_url      = $options['wos_crm_api_url'] ?? '';
    
    if (empty($api_url)) {
        wp_send_json_error(['message' => __('Webhook URL non configurato.', 'wp-order-sync')]);
    }

    // Costruiamo gli argomenti della query
    $args = [
        'status'  => ['processing', 'completed'],
        'limit'   => $batch_size,
        'offset'  => $offset,
        'orderby' => 'ID',
        'order'   => 'ASC',
    ];

    // Gestione date per WooCommerce HPOS
    if ($date_from && $date_to) {
        $args['date_created'] = $date_from . '...' . $date_to;
    } elseif ($date_from) {
        $args['date_created'] = '>=' . $date_from;
    } elseif ($date_to) {
        $args['date_created'] = '<=' . $date_to;
    }

    // Calcoliamo il totale solo al primo giro
    if ($offset === 0) {
        $count_args = $args;
        $count_args['limit'] = -1;
        $count_args['return'] = 'ids';
        $total_orders = count(wc_get_orders($count_args));
    } else {
        $total_orders = isset($_POST['total']) ? intval($_POST['total']) : 0;
    }

    if ($total_orders === 0) {
        wp_send_json_success([
            'processed'  => 0,
            'total'      => 0,
            'new_offset' => 0,
            'is_done'    => true,
            'message'    => __('Nessun ordine trovato nel range di date.', 'wp-order-sync'),
        ]);
        return;
    }

    // Recupera gli ordini del batch
    $orders = wc_get_orders($args);

    if (empty($orders)) {
        wp_send_json_success([
            'processed'  => 0,
            'total'      => $total_orders,
            'new_offset' => $offset,
            'is_done'    => true,
            'message'    => __('Esportazione terminata.', 'wp-order-sync'),
        ]);
        return;
    }

    // Helper temporaneo di debug: scriviamo su un file di testo nostro
    $upload_dir = wp_upload_dir();
    $wos_debug_file = trailingslashit($upload_dir['basedir']) . 'wos-debug.txt';
    $debug_log = function($msg) use ($wos_debug_file) {
        @file_put_contents($wos_debug_file, date('Y-m-d H:i:s') . " - " . $msg . "\n", FILE_APPEND);
    };

    if ($offset === 0) {
        @unlink($wos_debug_file); // puliamo il file di debug a inizio batch
        $debug_log("Inizio Nuovo Export CRM. Batch size: " . $batch_size);
    }
    
    $debug_log("Recuperati " . count($orders) . " ordini. Offset attuale: " . $offset);

    // Registriamo un shutdown function temporaneo per catturare Fatal Error (es. Memory limit, Timeout, o loop infiniti in un ordine specifico)
    global $wos_current_processing_order_id;
    $wos_current_processing_order_id = 0;
    
    $wos_shutdown_handler = function() {
        global $wos_current_processing_order_id;
        $error = error_get_last();
        if ($error !== null && in_array($error['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR, E_USER_ERROR])) {
            $msg = 'FATAL ERROR (Order ID: ' . $wos_current_processing_order_id . '): ' . $error['message'] . ' in ' . $error['file'] . ':' . $error['line'];
            error_log('WP Order Sync: ' . $msg);
            // Non possiamo ritornare JSON qui perché l'output è già collassato, ma almeno stampiamo qualcosa nel log
        }
    };
    register_shutdown_function($wos_shutdown_handler);

    $upload_errors = 0; // Initialize upload_errors here

    foreach ($orders as $order) {
        $wos_current_processing_order_id = $order->get_id();
        $debug_log("Sto per processare l'ordine ID: " . $wos_current_processing_order_id);
        try {
            // Usa la funzione centralizzata che gestisce sia API che FTP
            wos_sync_crm_data_only($wos_current_processing_order_id);
            $debug_log("Ordine " . $wos_current_processing_order_id . " inviato correttamente.");
        } catch (Throwable $e) {
            $debug_log("ECCEZIONE CATTURATA ordine " . $order->get_id() . ": " . $e->getMessage());
            error_log('WP Order Sync: Eccezione invio CRM per ordine ' . $order->get_id() . ' - ' . $e->getMessage());
            $upload_errors++;
        }
    }
    
    $debug_log("Batch completato.");
    
    // Ripristiniamo
    $wos_current_processing_order_id = 0;

    $processed_count = count($orders);
    $new_offset      = $offset + $processed_count;
    $is_done         = ($new_offset >= $total_orders);

    $msg = sprintf(__('Inviati %d di %d ordini...', 'wp-order-sync'), min($new_offset, $total_orders), $total_orders);
    if ($upload_errors > 0) {
        $msg .= sprintf(' (%d errori upload FTP)', $upload_errors);
    }

    wp_send_json_success([
        'processed'     => $processed_count,
        'total'         => $total_orders,
        'new_offset'    => $new_offset,
        'is_done'       => $is_done,
        'upload_errors' => $upload_errors,
        'message'       => $msg,
    ]);
}

/**
 * Callback della pagina opzioni
 */
function wos_options_page() {
    if (isset($_POST['wos_sync_all']) && current_user_can('manage_options')) {
        wos_sync_all_processing_orders();
    }
    ?>
    <div class="wrap">
        <h1><?php _e('WP Order Sync', 'wp-order-sync'); ?></h1>

        <form action="options.php" method="post">
            <?php
            settings_fields('wos_settings_group');
            do_settings_sections('wos_settings_group');
            submit_button();
            ?>
        </form>

        <hr />

        <!-- Pulsante per sincronizzare ordini Processing non sincronizzati (PRODUZIONE) -->
        <form method="post">
            <?php
            submit_button(
                __('Sincronizza tutti gli ordini Processing non sincronizzati', 'wp-order-sync'),
                'secondary',
                'wos_sync_all',
                false
            );
            ?>
        </form>

        <!-- Sezione Export CRM Filtrato -->
        <div style="margin-top: 20px; padding: 15px; border: 1px solid #ccd0d4; background: #fff;">
            <h3><?php _e('Esportazione Storico CRM via API', 'wp-order-sync'); ?></h3>
            <p class="description">
                <?php _e('Seleziona un periodo di tempo per inviare gli ordini passati al CRM. L\'operazione avverrà via chiamata REST API.', 'wp-order-sync'); ?>
            </p>

            <div style="margin: 15px 0;">
                <label style="margin-right: 15px;">
                    <strong><?php _e('Data Inizio:', 'wp-order-sync'); ?></strong><br>
                    <input type="date" id="wos-crm-date-from" class="regular-text" style="width: auto;">
                </label>
                <label>
                    <strong><?php _e('Data Fine:', 'wp-order-sync'); ?></strong><br>
                    <input type="date" id="wos-crm-date-to" class="regular-text" style="width: auto;">
                </label>
            </div>

            <button type="button" id="wos-start-crm-sync" class="button button-primary">
                <?php _e('Avvia Export FTP', 'wp-order-sync'); ?>
            </button>
            <button type="button" id="wos-stop-crm-sync" class="button button-secondary" style="display:none; color: #a00;">
                <?php _e('Stop', 'wp-order-sync'); ?>
            </button>

            <!-- Progress Container -->
            <div id="wos-progress-container" style="display:none; margin-top:15px; max-width: 500px;">
                <div style="background: #e5e5e5; height: 20px; border-radius: 3px; position: relative;">
                    <div id="wos-progress-bar" style="background: #0073aa; width: 0%; height: 100%; border-radius: 3px; transition: width 0.3s ease;"></div>
                    <div id="wos-progress-text" style="position: absolute; top: 0; left: 0; width: 100%; text-align: center; color: #fff; font-size: 12px; line-height: 20px; text-shadow: 1px 1px 1px rgba(0,0,0,0.5);">0%</div>
                </div>
                <p id="wos-progress-status" style="margin-top: 5px; font-weight: bold;"></p>
            </div>
        </div>
    </div>

    <!-- Script AJAX -->
    <script type="text/javascript">
    document.addEventListener('DOMContentLoaded', function() {
        var startBtn          = document.getElementById('wos-start-crm-sync');
        var stopBtn           = document.getElementById('wos-stop-crm-sync');
        var progressBar       = document.getElementById('wos-progress-bar');
        var progressText      = document.getElementById('wos-progress-text');
        var progressStatus    = document.getElementById('wos-progress-status');
        var progressContainer = document.getElementById('wos-progress-container');
        var dateFrom          = document.getElementById('wos-crm-date-from');
        var dateTo            = document.getElementById('wos-crm-date-to');

        if (!startBtn) return;

        var isSyncRunning = false;
        var currentOffset = 0;
        var totalOrders   = 0;
        var ajaxurl       = '<?php echo esc_url(admin_url('admin-ajax.php')); ?>';

        startBtn.addEventListener('click', function(e) {
            e.preventDefault();

            if (!dateFrom.value && !dateTo.value) {
                if (!confirm('<?php echo esc_js(__('Non hai selezionato nessuna data. Vuoi davvero esportare TUTTI gli ordini del sito? Questa operazione potrebbe causare timeout. Consigliamo di procedere filtrando mese per mese.', 'wp-order-sync')); ?>')) {
                    return;
                }
            } else {
                if (!confirm('<?php echo esc_js(__('Vuoi avviare l\'esportazione FTP per le date selezionate?', 'wp-order-sync')); ?>')) {
                    return;
                }
            }

            isSyncRunning = true;
            currentOffset = 0;
            totalOrders   = 0;

            startBtn.disabled = true;
            startBtn.innerText = '<?php echo esc_js(__('Esportazione in corso...', 'wp-order-sync')); ?>';
            stopBtn.style.display = 'inline-block';
            progressContainer.style.display = 'block';
            progressBar.style.width = '0%';
            progressText.innerText = '0%';
            progressStatus.innerText = '<?php echo esc_js(__('Connessione in corso... Calcolo ordini...', 'wp-order-sync')); ?>';

            processBatch();
        });

        stopBtn.addEventListener('click', function(e) {
            e.preventDefault();
            isSyncRunning = false;
            stopBtn.style.display = 'none';
            startBtn.disabled = false;
            startBtn.innerText = '<?php echo esc_js(__('Avvia Export FTP', 'wp-order-sync')); ?>';
            progressStatus.innerText = '<?php echo esc_js(__('Operazione interrotta.', 'wp-order-sync')); ?>';
        });

        function processBatch() {
            if (!isSyncRunning) return;

            var dFrom = dateFrom.value;
            var dTo   = dateTo.value;

            var xhr = new XMLHttpRequest();
            xhr.open('POST', ajaxurl, true);
            xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');

            xhr.onload = function() {
                if (!isSyncRunning) return;
                if (xhr.status >= 200 && xhr.status < 400) {
                    try {
                        var response = JSON.parse(xhr.responseText);
                        if (response.success) {
                            var data = response.data;
                            currentOffset = data.new_offset;
                            totalOrders   = data.total;
                            
                            var pct = (totalOrders > 0) ? Math.min(100, Math.round((currentOffset / totalOrders) * 100)) : 100;

                            progressBar.style.width = pct + '%';
                            progressText.innerText  = pct + '%';
                            progressStatus.innerText = data.message;

                            if (data.is_done) {
                                isSyncRunning = false;
                                stopBtn.style.display = 'none';
                                startBtn.disabled = false;
                                startBtn.innerText = '<?php echo esc_js(__('Avvia Export FTP', 'wp-order-sync')); ?>';
                                progressStatus.innerHTML += ' <span style="color:green;">&#10003; Clicca OK.</span>';
                            } else {
                                setTimeout(processBatch, 2000); // 2 secondi di pausa tra blocchi FTP
                            }
                        } else {
                            handleError((response.data && response.data.message) ? response.data.message : 'Unknown error');
                        }
                    } catch(e) {
                        handleError('JSON Parse: ' + e.message);
                    }
                } else {
                    handleError('HTTP ' + xhr.status);
                }
            };
            xhr.onerror = function() { handleError('Connessione Server fallita.'); };
            
            var payload = 'action=wos_sync_crm_batch&offset=' + currentOffset;
            payload += '&date_from=' + encodeURIComponent(dFrom);
            payload += '&date_to=' + encodeURIComponent(dTo);
            if (totalOrders > 0) {
                payload += '&total=' + totalOrders;
            }
            
            xhr.send(payload);
        }

        function handleError(msg) {
            isSyncRunning = false;
            progressStatus.innerText = '<?php echo esc_js(__('Errore:', 'wp-order-sync')); ?> ' + msg;
            startBtn.disabled = false;
            startBtn.innerText = '<?php echo esc_js(__('Riprova', 'wp-order-sync')); ?>';
            stopBtn.style.display = 'none';
        }

        // Test API Connection
        var testBtn = document.getElementById('wos-test-api-conn');
        var testResult = document.getElementById('wos-api-test-result');

        if (testBtn) {
            testBtn.addEventListener('click', function() {
                var apiUrl = document.querySelector('input[name="wos_settings[wos_crm_api_url]"]').value;
                var apiKey = document.querySelector('input[name="wos_settings[wos_crm_api_key]"]').value;

                if (!apiUrl) {
                    alert('Inserisci prima l\'URL del Webhook.');
                    return;
                }

                testBtn.disabled = true;
                testResult.innerText = 'Connessione in corso...';
                testResult.style.color = 'blue';

                var xhr = new XMLHttpRequest();
                xhr.open('POST', ajaxurl, true);
                xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
                xhr.onload = function() {
                    testBtn.disabled = false;
                    try {
                        var res = JSON.parse(xhr.responseText);
                        if (res.success) {
                            testResult.innerText = '✓ Connesso con successo!';
                            testResult.style.color = 'green';
                        } else {
                            testResult.innerText = '✗ Errore: ' + (res.data ? res.data.message : 'Dati non validi');
                            testResult.style.color = 'red';
                        }
                    } catch(e) {
                        testResult.innerText = '✗ Errore risposta server.';
                        testResult.style.color = 'red';
                    }
                };
                xhr.send('action=wos_test_api_connection&url=' + encodeURIComponent(apiUrl) + '&key=' + encodeURIComponent(apiKey));
            });
        }
    });
    </script>
    <?php
}

/**
 * Sincronizza in blocco tutti gli ordini "processing" non ancora sincronizzati (PRODUZIONE)
 */
function wos_sync_all_processing_orders() {
    $orders = wc_get_orders([
        'status'     => 'processing',
        'limit'      => -1,
        'meta_query' => [
            [
                'key'     => '_wos_synced',
                'compare' => 'NOT EXISTS',
            ],
        ],
    ]);

    if (!empty($orders)) {
        foreach ($orders as $order) {
            wos_sync_order_to_ftp($order->get_id());
        }
        echo '<div class="updated notice"><p>'
           . __('Sincronizzazione completata per tutti gli ordini processing non sincronizzati.', 'wp-order-sync')
           . '</p></div>';
    } else {
        echo '<div class="notice notice-info"><p>'
           . __('Nessun ordine processing da sincronizzare.', 'wp-order-sync')
           . '</p></div>';
    }
}

