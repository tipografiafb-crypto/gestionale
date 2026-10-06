<?php
if (!defined('ABSPATH')) { exit; }

// Versioned durable cart snapshots and outbound events. No CRM request is made
// on the checkout request; delivery is retried by Action Scheduler.
function wos_automation_install() {
    global $wpdb;
    require_once ABSPATH . 'wp-admin/includes/upgrade.php';
    $collate = $wpdb->get_charset_collate();
    dbDelta("CREATE TABLE {$wpdb->prefix}wos_carts (
        token varchar(80) NOT NULL,
        revision bigint unsigned NOT NULL DEFAULT 0,
        published_revision bigint unsigned NOT NULL DEFAULT 0,
        snapshot longtext NOT NULL,
        restore_data longtext NOT NULL,
        recovery_hash varchar(64) NOT NULL,
        updated_at datetime NOT NULL,
        expires_at datetime NOT NULL,
        converted tinyint NOT NULL DEFAULT 0,
        PRIMARY KEY  (token),
        KEY expires_at (expires_at)
    ) $collate;");
    dbDelta("CREATE TABLE {$wpdb->prefix}wos_outbox (
        id bigint unsigned NOT NULL AUTO_INCREMENT,
        event_id varchar(80) NOT NULL,
        body longtext NOT NULL,
        attempts int unsigned NOT NULL DEFAULT 0,
        next_at datetime NOT NULL,
        locked_until datetime NULL,
        status varchar(20) NOT NULL DEFAULT 'pending',
        last_error varchar(120) NULL,
        created_at datetime NOT NULL,
        PRIMARY KEY  (id),
        UNIQUE KEY event_id (event_id),
        KEY due (status,next_at)
    ) $collate;");
    update_option('wos_automation_schema', '1', false);
}

function wos_automation_enabled() {
    return get_option('wos_automation_enabled') === 'yes' && get_option('wos_automation_url') && get_option('wos_automation_secret') && get_option('wos_automation_store');
}

function wos_automation_requires_consent() {
    return get_option('wos_automation_require_consent', 'yes') !== 'no';
}

add_action('rest_api_init', function () {
    register_rest_route('wos/v1', '/carts/(?P<token>[a-zA-Z0-9-]{16,80})/status', [
        'methods' => 'GET',
        'permission_callback' => function ($request) {
            if (!wos_automation_enabled()) { return false; }
            $timestamp = $request->get_header('X-WOS-Timestamp');
            $signature = $request->get_header('X-WOS-Signature');
            return preg_match('/^\d{10}$/', $timestamp) && abs(time() - (int)$timestamp) <= 300 &&
                hash_equals(hash_hmac('sha256', $timestamp . '.' . $request['token'], get_option('wos_automation_secret')), $signature);
        },
        'callback' => function ($request) {
            global $wpdb;
            $row = $wpdb->get_row($wpdb->prepare("SELECT revision,updated_at,converted,snapshot FROM {$wpdb->prefix}wos_carts WHERE token=%s AND expires_at>UTC_TIMESTAMP()", $request['token']));
            if (!$row) { return new WP_Error('expired', 'Carrello non disponibile', ['status' => 410]); }
            $snapshot = json_decode($row->snapshot, true);
            // Read the WooCommerce order source as well, including a completed
            // purchase whose outbound event has not reached the CRM yet.
            $orders = wc_get_orders(['limit' => 1, 'return' => 'ids', 'billing_email' => $snapshot['email'],
                'status' => ['processing', 'completed'], 'date_created' => '>=' . $row->updated_at]);
            $pending = (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->prefix}wos_outbox WHERE status IN ('pending','dead')");
            $response = new WP_REST_Response(['converted' => (bool)$row->converted || !empty($orders),
                'revision' => (int)$row->revision, 'updated_at' => gmdate('c', strtotime($row->updated_at . ' UTC')), 'outbox_pending' => $pending > 0]);
            $response->header('Cache-Control', 'no-store');
            return $response;
        }
    ]);
});

add_action('init', function () {
    if (!wos_automation_enabled()) { return; }
    if (get_option('wos_automation_schema') !== '1') { wos_automation_install(); }
    if (function_exists('as_has_scheduled_action') && !as_has_scheduled_action('wos_automation_drain', [], 'wos')) {
        as_schedule_recurring_action(time() + 60, 60, 'wos_automation_drain', [], 'wos', true);
    }
}, 20);

function wos_automation_enqueue($type, $data, $occurred_at = null) {
    global $wpdb;
    $event_id = wp_generate_uuid4();
    $body = wp_json_encode(['schema_version' => 1, 'event_id' => $event_id,
        'event_type' => $type, 'occurred_at' => $occurred_at ?: gmdate('c'), 'data' => $data]);
    if (!$body || strlen($body) > 262144) { error_log('WOS: evento troppo grande o non valido'); return false; }
    return false !== $wpdb->insert($wpdb->prefix . 'wos_outbox', ['event_id' => $event_id, 'body' => $body,
        'next_at' => gmdate('Y-m-d H:i:s'), 'created_at' => gmdate('Y-m-d H:i:s')]);
}

add_action('wos_automation_drain', 'wos_automation_drain');
function wos_automation_drain() {
    global $wpdb;
    if (!wos_automation_enabled()) { return; }
    // A dirty snapshot remains pending until its event has reached the outbox.
    // A crash between these writes may duplicate an event, never lose a cart.
    $dirty = $wpdb->get_results("SELECT token,revision,snapshot,updated_at FROM {$wpdb->prefix}wos_carts WHERE revision>published_revision ORDER BY updated_at LIMIT 50");
    foreach ($dirty as $cart) {
        $payload = json_decode($cart->snapshot, true); $payload['revision'] = (int)$cart->revision;
        if (wos_automation_enqueue('cart.updated', $payload, gmdate('c', strtotime($cart->updated_at . ' UTC')))) {
            $wpdb->query($wpdb->prepare("UPDATE {$wpdb->prefix}wos_carts SET published_revision=GREATEST(published_revision,%d) WHERE token=%s", $cart->revision, $cart->token));
        }
    }
    $table = $wpdb->prefix . 'wos_outbox';
    $rows = $wpdb->get_results("SELECT id FROM $table WHERE status='pending' AND next_at <= UTC_TIMESTAMP() AND (locked_until IS NULL OR locked_until < UTC_TIMESTAMP()) ORDER BY id LIMIT 20");
    foreach ($rows as $item) {
        $claimed = $wpdb->query($wpdb->prepare("UPDATE $table SET locked_until=DATE_ADD(UTC_TIMESTAMP(), INTERVAL 60 SECOND) WHERE id=%d AND status='pending' AND (locked_until IS NULL OR locked_until < UTC_TIMESTAMP())", $item->id));
        if ($claimed !== 1) { continue; }
        $row = $wpdb->get_row($wpdb->prepare("SELECT * FROM $table WHERE id=%d", $item->id));
        $timestamp = (string)time();
        $response = wp_safe_remote_post(get_option('wos_automation_url'), ['timeout' => 15, 'redirection' => 0,
            'headers' => ['Content-Type' => 'application/json', 'X-WOS-Store' => get_option('wos_automation_store'),
                'X-WOS-Timestamp' => $timestamp, 'X-WOS-Signature' => hash_hmac('sha256', $timestamp . '.' . $row->body, get_option('wos_automation_secret'))], 'body' => $row->body]);
        $code = is_wp_error($response) ? 0 : wp_remote_retrieve_response_code($response);
        if ($code >= 200 && $code < 300) {
            $wpdb->delete($table, ['id' => $row->id]);
        } else {
            $attempts = (int)$row->attempts + 1;
            $wpdb->update($table, ['attempts' => $attempts, 'status' => $attempts >= 12 ? 'dead' : 'pending',
                'next_at' => gmdate('Y-m-d H:i:s', time() + min(3600, 30 * pow(2, min($attempts, 7)))),
                'locked_until' => null, 'last_error' => 'HTTP ' . $code], ['id' => $row->id]);
        }
    }
    $wpdb->query("DELETE FROM {$wpdb->prefix}wos_carts WHERE expires_at < UTC_TIMESTAMP()");
    $wpdb->query("DELETE FROM $table WHERE status='dead' AND created_at < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 30 DAY)");
}

function wos_automation_capture_cart($force = false) {
    global $wpdb;
    if (!wos_automation_enabled() || !function_exists('WC') || !WC()->cart || !WC()->session) { return; }
    $email = WC()->session->get('wos_email');
    if (!$email && is_user_logged_in()) { $email = wp_get_current_user()->user_email; }
    if (!is_email($email)) { return; }
    $identity = strtolower(trim($email));
    if (WC()->session->get('wos_identity') !== $identity) {
        WC()->session->set('wos_cart_token', wp_generate_uuid4());
        WC()->session->set('wos_recovery_secret', wp_generate_password(48, false));
        WC()->session->set('wos_identity', $identity);
    }
    $token = WC()->session->get('wos_cart_token');
    $secret = WC()->session->get('wos_recovery_secret');
    $items = []; $restore = [];
    foreach (WC()->cart->get_cart() as $item) {
        $product = $item['data'];
        $items[] = ['product_id' => $item['product_id'], 'variation_id' => $item['variation_id'],
            'sku' => $product->get_sku(), 'name' => $product->get_name(), 'quantity' => $item['quantity']];
        $copy = $item; unset($copy['data'], $copy['line_tax_data'], $copy['line_total'], $copy['line_subtotal'], $copy['line_tax'], $copy['line_subtotal_tax']);
        // Server-owned item data preserves customizer metadata. Plugins can
        // explicitly filter unsupported/temporary assets before persistence.
        $restore[] = apply_filters('wos_automation_restore_item', $copy, $item);
    }
    $consent = WC()->session->get('wos_consent', ['granted' => false]);
    if (!wos_automation_requires_consent()) {
        $consent = ['granted' => true, 'source' => 'wos_plugin_setting', 'recorded_at' => gmdate('c'),
            'notice' => 'Consenso disattivato nelle impostazioni del plugin dal titolare del sito'];
        WC()->session->set('wos_consent', $consent);
    }
    $data = ['cart_token' => $token, 'email' => $identity, 'first_name' => WC()->customer ? WC()->customer->get_billing_first_name() : '',
        'currency' => get_woocommerce_currency(), 'total' => WC()->cart->get_total('edit'), 'items' => $items,
        'consent' => $consent, 'recovery_url' => add_query_arg(['wos_recover' => $token, 'key' => $secret], home_url('/'))];
    $snapshot = wp_json_encode($data);
    $restore_json = wp_json_encode(['items' => $restore, 'coupons' => WC()->cart->get_applied_coupons()]);
    if (!$snapshot || !$restore_json || strlen($restore_json) > 1048576) { return; }
    $table = $wpdb->prefix . 'wos_carts';
    $existing = $wpdb->get_row($wpdb->prepare("SELECT snapshot, updated_at, converted FROM $table WHERE token=%s", $token));
    if ($existing && $existing->converted) { return; }
    if ($existing && $existing->snapshot === $snapshot && (!$force || strtotime($existing->updated_at . ' UTC') > time() - 60)) { return; }
    $updated = $wpdb->query($wpdb->prepare("INSERT INTO $table (token,revision,snapshot,restore_data,recovery_hash,updated_at,expires_at) VALUES (%s,1,%s,%s,%s,UTC_TIMESTAMP(),DATE_ADD(UTC_TIMESTAMP(), INTERVAL 30 DAY)) ON DUPLICATE KEY UPDATE revision=revision+1,snapshot=VALUES(snapshot),restore_data=VALUES(restore_data),updated_at=UTC_TIMESTAMP(),expires_at=VALUES(expires_at)", $token, $snapshot, $restore_json, hash('sha256', $secret)));
    if ($updated === false) { return; }
}

foreach (['woocommerce_add_to_cart', 'woocommerce_cart_item_removed', 'woocommerce_cart_item_restored', 'woocommerce_after_cart_item_quantity_update', 'woocommerce_applied_coupon', 'woocommerce_removed_coupon', 'woocommerce_cart_emptied'] as $hook) {
    add_action($hook, function () { add_action('shutdown', 'wos_automation_capture_cart'); }, 30, 0);
}

add_action('wp_enqueue_scripts', function () {
    if (!wos_automation_enabled() || (!is_checkout() && !is_cart())) { return; }
    wp_enqueue_script('wos-automation-capture', plugins_url('../assets/automation-capture.js', __FILE__), [], '4.1.1', true);
    wp_localize_script('wos-automation-capture', 'wosCapture', ['url' => WC_AJAX::get_endpoint('wos_capture'),
        'nonce' => wp_create_nonce('wos_capture'), 'notice' => get_option('wos_automation_notice', 'Acconsento a ricevere email su questo carrello e sui miei acquisti. Posso disiscrivermi in ogni momento.'),
        'requiresConsent' => wos_automation_requires_consent() ? 'yes' : 'no']);
});

add_action('wc_ajax_wos_capture', function () {
    if (!wos_automation_enabled() || !check_ajax_referer('wos_capture', 'nonce', false) || !WC()->session || !WC()->cart) { wp_send_json_error(null, 403); }
    $email = sanitize_email(wp_unslash($_POST['email'] ?? ''));
    if (!is_email($email)) { wp_send_json_error(null, 422); }
    // Slow down repeated anonymous requests without preventing cart updates.
    if ((int)WC()->session->get('wos_capture_at', 0) > time() - 3) { wp_send_json_success(); }
    WC()->session->set('wos_capture_at', time());
    WC()->session->set('wos_email', $email);
    WC()->session->set('wos_consent', ['granted' => !wos_automation_requires_consent() || ($_POST['consent'] ?? '') === 'yes',
        'source' => 'wos_checkout_checkbox', 'recorded_at' => gmdate('c'),
        'notice' => get_option('wos_automation_notice', 'Acconsento a ricevere email su questo carrello e sui miei acquisti. Posso disiscrivermi in ogni momento.')]);
    WC()->session->set_customer_session_cookie(true);
    wos_automation_capture_cart(true);
    wp_send_json_success();
});

function wos_automation_order_meta($order) {
    if (!wos_automation_enabled() || !WC()->session || !is_a($order, 'WC_Order')) { return; }
    $order->update_meta_data('_wos_cart_token', WC()->session->get('wos_cart_token'));
    $order->update_meta_data('_wos_consent', WC()->session->get('wos_consent', ['granted' => false]));
}
add_action('woocommerce_checkout_create_order', 'wos_automation_order_meta', 20);
add_action('woocommerce_store_api_checkout_update_order_meta', function ($order) { wos_automation_order_meta($order); $order->save_meta_data(); }, 20);
add_action('woocommerce_checkout_order_processed', function ($id) { if (wos_automation_enabled()) { wos_automation_order_event($id); } }, 30);
add_action('woocommerce_store_api_checkout_order_processed', function ($order) { if (wos_automation_enabled()) { wos_automation_order_event($order->get_id()); } }, 30);
// The checkout hook covers the first snapshot; this hook keeps the CRM aware
// of every later WooCommerce state transition (paid, completed, refunded…).
add_action('woocommerce_order_status_changed', function ($order_id) {
    if (wos_automation_enabled()) { wos_automation_order_event($order_id); }
}, 30, 1);

function wos_automation_order_event($order_id) {
    global $wpdb;
    $order = wc_get_order($order_id);
    if (!$order || !is_a($order, 'WC_Order')) { return; }
    if (!is_email($order->get_billing_email())) { return; }
    $data = json_decode(wos_generate_crm_json($order, get_option('wos_automation_store')), true);
    // Preserve failed/cancelled orders in the new event stream.
    if (!$data || $data['type'] !== 'crm_order') { return; }
    $data['cart_token'] = $order->get_meta('_wos_cart_token');
    $paid = $order->get_date_paid();
    $data['confirmed_at'] = $paid ? gmdate('c', $paid->getTimestamp()) : ($order->get_date_created() ? gmdate('c', $order->get_date_created()->getTimestamp()) : gmdate('c'));
    $data['consent'] = $order->get_meta('_wos_consent') ?: ['granted' => false];
    if (WC()->session && strtolower((string)WC()->session->get('wos_email')) === strtolower($order->get_billing_email())) {
        $data['consent'] = WC()->session->get('wos_consent', $data['consent']);
        $order->update_meta_data('_wos_consent', $data['consent']);
        $order->save_meta_data();
    }
    if (!$data['cart_token'] && WC()->session) {
        $data['cart_token'] = WC()->session->get('wos_cart_token');
    }
    if (in_array($order->get_status(), ['processing', 'completed'], true) && $data['cart_token']) {
        $wpdb->update($wpdb->prefix . 'wos_carts', ['converted' => 1], ['token' => $data['cart_token']]);
    }
    return wos_automation_enqueue('order.updated', $data);
}

add_action('template_redirect', function () {
    global $wpdb;
    if (!wos_automation_enabled() || empty($_GET['wos_recover'])) { return; }
    nocache_headers(); header('Referrer-Policy: no-referrer'); header('X-Robots-Tag: noindex, nofollow');
    $token = sanitize_text_field(wp_unslash($_GET['wos_recover']));
    $key = (string)wp_unslash($_GET['key'] ?? '');
    $row = $wpdb->get_row($wpdb->prepare("SELECT * FROM {$wpdb->prefix}wos_carts WHERE token=%s AND converted=0 AND expires_at>UTC_TIMESTAMP()", $token));
    if (!$row || !hash_equals($row->recovery_hash, hash('sha256', $key))) { wp_die('Carrello scaduto o non disponibile.', 'Carrello', ['response' => 410]); }
    // A GET from an email security scanner must never empty a shopper's cart.
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        wp_die('<form method="post">' . wp_nonce_field('wos_restore_' . $token, '_wpnonce', true, false) . '<p>Riprendere il carrello salvato? Il carrello corrente verrà sostituito.</p><button>Riprendi carrello</button></form>', 'Riprendi carrello', ['response' => 200]);
    }
    if (!wp_verify_nonce(sanitize_text_field(wp_unslash($_POST['_wpnonce'] ?? '')), 'wos_restore_' . $token)) { wp_die('Sessione scaduta', '', ['response' => 403]); }
    $saved = json_decode($row->restore_data, true);
    if (!is_array($saved) || empty($saved['items'])) { wp_die('Carrello non disponibile', '', ['response' => 410]); }
    // Validate availability before replacing the current session cart.
    foreach ($saved['items'] as $item) {
        $product = wc_get_product($item['variation_id'] ?: $item['product_id']);
        if (!$product || !$product->is_purchasable() || !$product->is_in_stock() || !$product->has_enough_stock($item['quantity'])) { wp_die('Un articolo non è più disponibile. Contattaci per recuperare il progetto.', '', ['response' => 409]); }
    }
    $previous = WC()->cart->get_cart();
    $previous_coupons = WC()->cart->get_applied_coupons();
    WC()->cart->empty_cart();
    $ok = true;
    foreach ($saved['items'] as $item) {
        $extra = $item; unset($extra['key'], $extra['product_id'], $extra['variation_id'], $extra['variation'], $extra['quantity']);
        if (!WC()->cart->add_to_cart($item['product_id'], $item['quantity'], $item['variation_id'], $item['variation'], $extra)) { $ok = false; break; }
    }
    if (!$ok) {
        WC()->cart->set_cart_contents($previous);
        WC()->cart->set_applied_coupons($previous_coupons); WC()->cart->calculate_totals();
        wp_die('Impossibile ripristinare tutti gli articoli. Il carrello precedente è stato conservato.', '', ['response' => 409]);
    }
    foreach ($saved['coupons'] as $coupon) { WC()->cart->apply_coupon($coupon); }
    // Do not restore email, address, account access or consent from a bearer link.
    WC()->session->set('wos_cart_token', $token);
    WC()->session->set('wos_recovery_secret', $key);
    WC()->cart->calculate_totals();
    wp_safe_redirect(wc_get_checkout_url()); exit;
}, 20);

add_action('admin_menu', function () {
    add_submenu_page('woocommerce', 'Automazioni CRM', 'Automazioni CRM', 'manage_woocommerce', 'wos-automations', 'wos_automation_settings_page');
});
function wos_automation_settings_page() {
    global $wpdb;
    if (!current_user_can('manage_woocommerce')) { return; }
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        check_admin_referer('wos_automation_settings');
        $url = esc_url_raw(wp_unslash($_POST['url'] ?? ''));
        if ($url && wp_parse_url($url, PHP_URL_SCHEME) !== 'https') { echo '<div class="notice notice-error"><p>Utilizzare HTTPS.</p></div>'; }
        else {
            update_option('wos_automation_url', $url, false);
            update_option('wos_automation_store', sanitize_text_field(wp_unslash($_POST['store'] ?? '')), false);
            if (!empty($_POST['secret'])) { update_option('wos_automation_secret', sanitize_text_field(wp_unslash($_POST['secret'])), false); }
            update_option('wos_automation_notice', sanitize_textarea_field(wp_unslash($_POST['notice'] ?? '')), false);
            update_option('wos_automation_enabled', isset($_POST['enabled']) ? 'yes' : 'no', false);
            update_option('wos_automation_retry_failed', isset($_POST['retry']) ? 'yes' : 'no', false);
            update_option('wos_automation_require_consent', isset($_POST['require_consent']) ? 'yes' : 'no', false);
            wos_automation_install();
            if (!empty($_POST['retry'])) { $wpdb->query("UPDATE {$wpdb->prefix}wos_outbox SET status='pending', attempts=0,next_at=UTC_TIMESTAMP(),locked_until=NULL WHERE status='dead'"); }
            echo '<div class="notice notice-success"><p>Configurazione salvata.</p></div>';
        }
    }
    echo '<div class="wrap"><h1>Automazioni CRM</h1><p>Abilitando il collegamento, gli aggiornamenti ordine passano alla nuova coda persistente. Avviare prima il worker automazioni nel CRM.</p><form method="post">';
    wp_nonce_field('wos_automation_settings');
    echo '<p><label><input type="checkbox" name="enabled" ' . checked(get_option('wos_automation_enabled'), 'yes', false) . '> Abilita eventi e carrelli</label></p>';
    foreach (['url' => ['URL API eventi HTTPS', 'wos_automation_url'], 'store' => ['Codice negozio CRM', 'wos_automation_store'], 'notice' => ['Testo consenso email', 'wos_automation_notice']] as $field => $info) {
        echo '<p><label>' . esc_html($info[0]) . '<br><input class="large-text" name="' . esc_attr($field) . '" value="' . esc_attr(get_option($info[1], $field === 'notice' ? 'Acconsento a ricevere email su questo carrello e sui miei acquisti. Posso disiscrivermi in ogni momento.' : '')) . '"></label></p>';
    }
    echo '<p><label>Chiave CRM (lascia vuota per conservarla)<br><input type="password" name="secret" autocomplete="new-password" class="large-text"></label></p>';
    echo '<p><label><input type="checkbox" name="require_consent" ' . checked(wos_automation_requires_consent(), true, false) . '> Richiedi consenso marketing</label><br><small>Se disattivato, gli eventi vengono registrati come autorizzati dal titolare del sito e il plugin non mostra la casella al cliente.</small></p>';
    echo '<p><label><input type="checkbox" name="retry" ' . checked(get_option('wos_automation_retry_failed'), 'yes', false) . '> Riprova eventi falliti</label></p>'; submit_button('Salva'); echo '</form>';
    if (get_option('wos_automation_schema') === '1') {
        $counts = $wpdb->get_results("SELECT status,COUNT(*) AS n FROM {$wpdb->prefix}wos_outbox GROUP BY status");
        foreach ($counts as $count) { echo '<p>' . esc_html($count->status . ': ' . $count->n) . '</p>'; }
    }
    echo '<p>Configurare un cron reale per Action Scheduler. Senza traffico sul sito, WP-Cron può ritardare gli eventi.</p></div>';
}
