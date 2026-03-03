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
    return $sanitized;
}

/**
 * Render della sezione
 */
function wos_settings_section_callback() {
    echo __('Inserisci le impostazioni FTP per sincronizzare gli ordini.', 'wp-order-sync');
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

/**
 * Callback della pagina opzioni
 * con il bottone "Sincronizza tutti gli ordini processing".
 */
function wos_options_page() {
    // Se clicca “Sincronizza tutti gli ordini”
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
            submit_button(); // "Salva"
            ?>
        </form>

        <hr />

        <!-- Pulsante per sincronizzare tutti gli ordini “Processing” non ancora sincronizzati -->
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
    </div>
    <?php
}

/**
 * Sincronizza in blocco tutti gli ordini "processing" non ancora sincronizzati
 * usando la funzione "wos_sync_order_to_ftp" (definita in sync.php).
 */
function wos_sync_all_processing_orders() {
    // Evitiamo l’uso di wc_get_orders con parametri non supportati
    $args = [
        'post_type'      => 'shop_order',
        'post_status'    => 'wc-processing',
        'posts_per_page' => -1,
        'meta_query'     => [
            [
                'key'     => '_wos_synced',
                'compare' => 'NOT EXISTS'
            ]
        ]
    ];

    $query  = new WP_Query($args);
    $orders = $query->posts;

    if (!empty($orders)) {
        foreach ($orders as $order_post) {
            $order_id = $order_post->ID;

            // La funzione wos_sync_order_to_ftp è definita in sync.php
            wos_sync_order_to_ftp($order_id);
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
