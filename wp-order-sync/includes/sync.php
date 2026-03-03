<?php
// File: includes/sync.php (aligned arrays; preserves cart_id "0"; robust URL normalization)

if ( ! defined('ABSPATH') ) {
    exit;
}

if ( ! function_exists('wos_sync_order_to_ftp') ) {

    add_action('woocommerce_order_status_processing', 'wos_sync_order_to_ftp');

    function wos_sync_order_to_ftp($order_id) {
        if ($order_id === null || $order_id === '' ) {
            return;
        }

        // Evita doppio invio
        $synced = get_post_meta($order_id, '_wos_synced', true);
        if ($synced) {
            return;
        }

        $order = wc_get_order($order_id);
        if (!$order) {
            error_log('WP Order Sync: Ordine non trovato. ID: ' . $order_id);
            return;
        }

        // Impostazioni
        $options      = get_option('wos_settings');
        $site_name    = $options['wos_site_name']    ?? '';
        $ftp_host     = $options['wos_ftp_host']     ?? '';
        $ftp_port     = (int)($options['wos_ftp_port'] ?? 21);
        $ftp_username = $options['wos_ftp_username'] ?? '';
        $ftp_password = $options['wos_ftp_password'] ?? '';
        $ftp_path     = $options['wos_ftp_path']     ?? '/';

        if ($ftp_host === '' || $ftp_username === '' || $ftp_password === '') {
            error_log('WP Order Sync: Credenziali FTP incomplete.');
            return;
        }

        global $wpdb;
        $table_name = 'lumise_order_products'; // verifica che sia corretto

        // Base uploads URL
        $upload_dir = wp_upload_dir();
        if (!empty($upload_dir['subdir'])) {
            $upload_dir['baseurl'] = str_replace($upload_dir['subdir'], '', $upload_dir['baseurl']);
        }
        $base_url = trailingslashit($upload_dir['baseurl']) . 'lumise_data/orders/';

        // --- 1) PRINT FILES (cart_id -> [urls]) ---
        $print_files_cart = $wpdb->get_results(
            $wpdb->prepare("SELECT cart_id, print_files FROM $table_name WHERE order_id = %d", $order_id),
            ARRAY_A
        );

        $map_print = []; // cart_id(string) => array urls
        foreach ($print_files_cart as $row) {
            $rawPrint = isset($row['print_files']) ? $row['print_files'] : '';
            if ($rawPrint === null) $rawPrint = '';
            $rawPrint = trim($rawPrint);
            if ($rawPrint === '') continue;

            $clean_data = trim($rawPrint, "[] \t\n\r\0\x0B'\"");
            $nodes = $clean_data === '' ? [] : array_map('trim', explode(',', $clean_data));
            $urls  = [];

            foreach ($nodes as $node) {
                $node = trim($node, " \t\n\r\0\x0B'\"");
                if ($node === '') continue;
                $url = wos_clean_and_build_url($base_url, $node);
                $url = wos_normalize_url($url);
                if (filter_var($url, FILTER_VALIDATE_URL)) {
                    $urls[] = $url;
                }
            }

            if (!empty($urls) && array_key_exists('cart_id', $row)) {
                $cid = (string)$row['cart_id']; // preserva "0"
                // Accetta anche cart_id ""? Lo escludiamo, ma teniamo "0"
                if ($cid !== '') {
                    // Se esistono più righe stesso cart_id, mergiamo
                    $prev = isset($map_print[$cid]) ? $map_print[$cid] : [];
                    $map_print[$cid] = array_values(array_unique(array_merge($prev, $urls)));
                }
            }
        }

        // --- 2) SCREENSHOTS (cart_id -> [urls]) ---
        $screenshots_cart = $wpdb->get_results(
            $wpdb->prepare("SELECT cart_id, screenshots FROM $table_name WHERE order_id = %d", $order_id),
            ARRAY_A
        );

        $map_screen = []; // cart_id(string) => array urls
        foreach ($screenshots_cart as $row) {
            $rawShots = isset($row['screenshots']) ? $row['screenshots'] : '';
            if ($rawShots === null) $rawShots = '';
            $rawShots = trim($rawShots);
            if ($rawShots === '') continue;

            $clean_data = trim($rawShots, "[] \t\n\r\0\x0B'\"");
            $nodes = $clean_data === '' ? [] : array_map('trim', explode(',', $clean_data));
            $urls  = [];

            foreach ($nodes as $node) {
                $node = trim($node, " \t\n\r\0\x0B'\"");
                if ($node === '') continue;
                $url = wos_clean_and_build_url($base_url, $node);
                $url = wos_normalize_url($url);
                if (filter_var($url, FILTER_VALIDATE_URL)) {
                    $urls[] = $url;
                }
            }

            if (!empty($urls) && array_key_exists('cart_id', $row)) {
                $cid = (string)$row['cart_id']; // preserva "0"
                if ($cid !== '') {
                    $prev = isset($map_screen[$cid]) ? $map_screen[$cid] : [];
                    $map_screen[$cid] = array_values(array_unique(array_merge($prev, $urls)));
                }
            }
        }

        // --- 3) Costruzione array allineati ai line items ---
        $print_files_with_cart_id  = [];
        $screenshots_with_cart_id  = [];
        $cuts_with_cart_id         = [];

        foreach ($order->get_items() as $item) {
            $meta = wos_get_order_item_meta_data($item);

            // cart_id da Lumise o AI; preserva "0" come stringa valida
            $cart_id = '';
            if (isset($meta['lumise_data']) && is_array($meta['lumise_data']) && array_key_exists('cart_id', $meta['lumise_data'])) {
                $cart_id = (string)$meta['lumise_data']['cart_id'];
            } elseif (isset($meta['_wc_ai_customization']) && is_array($meta['_wc_ai_customization']) && array_key_exists('artwork_id', $meta['_wc_ai_customization'])) {
                $cart_id = (string)$meta['_wc_ai_customization']['artwork_id'];
            }

            // Sorgenti: mappe DB
            $row_print  = ($cart_id !== '' && isset($map_print[$cart_id]))  ? $map_print[$cart_id]  : [];
            $row_screen = ($cart_id !== '' && isset($map_screen[$cart_id])) ? $map_screen[$cart_id] : [];
            $row_cut    = [];

            // Aggiungi eventuali _mpu_file_urls come print_files
            if (isset($meta['_mpu_file_urls']) && $meta['_mpu_file_urls'] !== '') {
                $raw_files = $meta['_mpu_file_urls'];
                if (!is_array($raw_files)) {
                    $raw_files = array_map('trim', explode(',', $raw_files));
                }
                foreach ($raw_files as $f) {
                    $f = trim($f, " \t\n\r\0\x0B'\"");
                    if ($f === '') continue;
                    $url = preg_match('#^https?://#i', $f) ? $f : wos_clean_and_build_url($base_url, $f);
                    $url = wos_normalize_url($url);
                    if (filter_var($url, FILTER_VALIDATE_URL)) {
                        $row_print[] = $url;
                    }
                }
            }

            // AI multicanvas
            if (isset($meta['_wc_ai_customization']) && is_array($meta['_wc_ai_customization'])) {
                $custom = $meta['_wc_ai_customization'];

                // --- Single preview/print urls ---
                if (!empty($custom['preview_url']) && is_string($custom['preview_url'])) {
                    $u = wos_normalize_url($custom['preview_url']);
                    if (filter_var($u, FILTER_VALIDATE_URL)) {
                        $row_screen[] = $u;
                    }
                }
                if (!empty($custom['print_url']) && is_string($custom['print_url'])) {
                    $u = wos_normalize_url($custom['print_url']);
                    if (filter_var($u, FILTER_VALIDATE_URL)) {
                        $row_print[] = $u;
                    }
                }

                // --- Multicanvas data (nested) ---
                if (!empty($custom['multicanvas_data']) && is_array($custom['multicanvas_data'])) {
                    $mc = $custom['multicanvas_data'];
                    if (!empty($mc['stage_previews']) && is_array($mc['stage_previews'])) {
                        foreach ($mc['stage_previews'] as $u) {
                            if (!is_string($u)) continue;
                            $u = wos_normalize_url($u);
                            if (filter_var($u, FILTER_VALIDATE_URL)) {
                                $row_screen[] = $u;
                            }
                        }
                    }
                    if (!empty($mc['stage_prints']) && is_array($mc['stage_prints'])) {
                        foreach ($mc['stage_prints'] as $u) {
                            if (!is_string($u)) continue;
                            $u = wos_normalize_url($u);
                            if (filter_var($u, FILTER_VALIDATE_URL)) {
                                $row_print[] = $u;
                            }
                        }
                    }
                    if (!empty($mc['stage_cuts']) && is_array($mc['stage_cuts'])) {
                        foreach ($mc['stage_cuts'] as $u) {
                            if (!is_string($u)) continue;
                            $u = wos_normalize_url($u);
                            if (filter_var($u, FILTER_VALIDATE_URL)) {
                                $row_cut[] = $u;
                            }
                        }
                    }
                }

                // --- Legacy flat keys (if present) ---
                if (!empty($custom['stage_previews']) && is_array($custom['stage_previews'])) {
                    foreach ($custom['stage_previews'] as $u) {
                        if (!is_string($u)) continue;
                        $u = wos_normalize_url($u);
                        if (filter_var($u, FILTER_VALIDATE_URL)) {
                            $row_screen[] = $u;
                        }
                    }
                }
                if (!empty($custom['stage_prints']) && is_array($custom['stage_prints'])) {
                    foreach ($custom['stage_prints'] as $u) {
                        if (!is_string($u)) continue;
                        $u = wos_normalize_url($u);
                        if (filter_var($u, FILTER_VALIDATE_URL)) {
                            $row_print[] = $u;
                        }
                    }
                }
            }

            // Fallback meta keys added by integrator
            if (isset($meta['_wc_ai_preview_url']) && is_string($meta['_wc_ai_preview_url'])) {
                $u = wos_normalize_url($meta['_wc_ai_preview_url']);
                if (filter_var($u, FILTER_VALIDATE_URL)) {
                    $row_screen[] = $u;
                }
            }
            if (isset($meta['_wc_ai_print_url']) && is_string($meta['_wc_ai_print_url'])) {
                $u = wos_normalize_url($meta['_wc_ai_print_url']);
                if (filter_var($u, FILTER_VALIDATE_URL)) {
                    $row_print[] = $u;
                }
            }
// Deduplica
            $row_print  = array_values(array_unique($row_print));
            $row_screen = array_values(array_unique($row_screen));
            $row_cut    = array_values(array_unique($row_cut));

            // Aggiungi SEMPRE la riga, anche se vuota
            $print_files_with_cart_id[] = [
                'cart_id'     => $cart_id,      // '' se assente, '0' valido
                'print_files' => $row_print,    // []
            ];
            $screenshots_with_cart_id[] = [
                'cart_id'     => $cart_id,
                'screenshots' => $row_screen,   // []
            ];
            $cuts_with_cart_id[] = [
                'cart_id'     => $cart_id,
                'cut_with_cart_id' => $row_cut,   // []
            ];
        }

        // --- 4) line_items + JSON finale ---
        $order_data = [
            'id'                        => $order->get_order_number(),
            'number'                    => $order->get_order_number(),
            'site_name'                 => $site_name,
            'customer_note'             => $order->get_customer_note(),
            'print_files_with_cart_id'  => $print_files_with_cart_id,
            'screenshots_with_cart_id'  => $screenshots_with_cart_id,
            'cut_with_cart_id'          => $cuts_with_cart_id,
            'line_items'                => [],
        ];

        foreach ($order->get_items() as $item) {
            $product = $item->get_product();
            if (!$product) continue;

            $meta = wos_get_order_item_meta_data($item);
            $sku  = $product->get_sku();

            if (isset($meta['_wc_ai_customization']['selected_size']) && $meta['_wc_ai_customization']['selected_size'] !== '') {
                $sku .= '-' . $meta['_wc_ai_customization']['selected_size'];
            }

            
            // Override SKU se presente final_sku nei meta (solo nel payload dell'ordine)
            $maybe_final = wos_extract_final_sku($meta);
            if (is_string($maybe_final) && $maybe_final !== '') {
                $sku = $maybe_final;
            }

            $order_data['line_items'][] = [
                'quantity'  => $item->get_quantity(),
                'sku'       => $sku,
                'image'     => [
                    'id'  => $product->get_image_id(),
                    'src' => wp_get_attachment_url($product->get_image_id()),
                ],
                'meta_data' => $meta,
            ];
        }

        $json_data = json_encode($order_data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        if ($json_data === false) {
            error_log('WP Order Sync: Errore json_encode ordine ' . $order_id);
            return;
        }

        // --- 5) Upload FTP ---
        $order_number    = $order->get_order_number();
        $filename        = 'order_' . $order_number . '.json';
        $remote_file     = rtrim($ftp_path, '/') . '/' . $filename;

        $upload_response = wos_upload_to_ftp($ftp_host, $ftp_port, $ftp_username, $ftp_password, $remote_file, $json_data);

        if (is_wp_error($upload_response)) {
            error_log('WP Order Sync: Upload fallito - ' . $upload_response->get_error_message());
            return;
        }

        update_post_meta($order_id, '_wos_synced', 1);
    }
}

/**
 * Build URL from base + relative or return absolute as-is (normalized).
 */
if ( ! function_exists('wos_clean_and_build_url') ) {
    function wos_clean_and_build_url($base_url, $path_or_url) {
        $path_or_url = (string)$path_or_url;
        $path_or_url = trim($path_or_url, " \t\n\r\0\x0B'\"");
        $path_or_url = str_replace('\\', '/', $path_or_url);

        // Assoluta?
        if (preg_match('#^https?://#i', $path_or_url)) {
            return wos_normalize_url($path_or_url);
        }

        $base = rtrim(str_replace('\\', '/', (string)$base_url), '/') . '/';
        $rel  = ltrim($path_or_url, '/');

        return wos_normalize_url($base . $rel);
    }
}

/**
 * Normalize URL: remove backslashes, collapse duplicate slashes except after protocol.
 */
if ( ! function_exists('wos_normalize_url') ) {
    function wos_normalize_url($url) {
        $url = (string)$url;
        $url = trim($url, " \t\n\r\0\x0B'\"");
        $url = str_replace('\\', '/', $url);
        // Split protocol once to preserve ://
        if (preg_match('#^([a-z][a-z0-9+\-.]*://)(.*)$#i', $url, $m)) {
            $proto = $m[1];
            $rest  = $m[2];
            // collapse multiple slashes in the rest
            $rest  = preg_replace('#/{2,}#', '/', $rest);
            return $proto . $rest;
        }
        // No protocol: just collapse
        return preg_replace('#/{2,}#', '/', $url);
    }
}

/**
 * FTP uploader with recursive dir creation
 */
if ( ! function_exists('wos_upload_to_ftp') ) {
    function wos_upload_to_ftp($host, $port, $username, $password, $remote_path, $file_contents) {
        $ftp_conn = ftp_connect($host, $port, 30);
        if (!$ftp_conn) {
            return new WP_Error('ftp_connect_failed', __('Impossibile connettersi al server FTP.', 'wp-order-sync'));
        }

        $login = ftp_login($ftp_conn, $username, $password);
        if (!$login) {
            ftp_close($ftp_conn);
            return new WP_Error('ftp_login_failed', __('Login FTP fallito.', 'wp-order-sync'));
        }

        ftp_pasv($ftp_conn, true);

        $remote_dir = dirname($remote_path);
        if (!wos_ftp_create_dirs($ftp_conn, $remote_dir)) {
            ftp_close($ftp_conn);
            return new WP_Error('ftp_create_dir_failed', __('Impossibile creare cartelle FTP.', 'wp-order-sync'));
        }

        $tmp = tmpfile();
        fwrite($tmp, $file_contents);
        fseek($tmp, 0);

        $meta = stream_get_meta_data($tmp);
        $local_temp_path = $meta['uri'];

        $result = ftp_put($ftp_conn, $remote_path, $local_temp_path, FTP_BINARY);

        fclose($tmp);
        ftp_close($ftp_conn);

        if (!$result) {
            return new WP_Error('ftp_put_failed', __('Upload FTP fallito.', 'wp-order-sync'));
        }

        return true;
    }
}

/**
 * Recursively create dirs on FTP
 */
if ( ! function_exists('wos_ftp_create_dirs') ) {
    function wos_ftp_create_dirs($ftp_conn, $remote_dir) {
        $parts = explode('/', trim($remote_dir, '/'));
        $path  = '';
        foreach ($parts as $part) {
            if ($part === '') continue;
            $path .= '/' . $part;
            if (@ftp_chdir($ftp_conn, $path)) {
                ftp_chdir($ftp_conn, '/');
                continue;
            }
            if (!@ftp_mkdir($ftp_conn, $path)) {
                return false;
            }
        }
        return true;
    }
}

/**
 * Extract relevant meta from item
 */
if ( ! function_exists('wos_get_order_item_meta_data') ) {
    function wos_get_order_item_meta_data($item) {
        $meta_data = $item->get_meta_data();
        $formatted_meta = [];

        $allowed_keys = [
            'lumise_data',
            '_mpu_file_urls',
            '_wc_ai_preview_url',
            '_wc_ai_print_url',
            '_wc_ai_customization',
        ];

        foreach ($meta_data as $meta) {
            $data = $meta->get_data();
            if (!isset($data['key'])) continue;

            $key = $data['key'];
            $val = $data['value'];

            if (!in_array($key, $allowed_keys, true)) continue;

            if (is_string($val) && wos_is_serialized($val)) {
                $val = maybe_unserialize($val);
            }

            if (is_string($val) && wos_is_json($val)) {
                $json = json_decode($val, true);
                if (json_last_error() === JSON_ERROR_NONE) {
                    $val = $json;
                }
            }

            $formatted_meta[$key] = $val;
        }

        return $formatted_meta;
    }
}

/**
 * Helpers
 */
if ( ! function_exists('wos_is_serialized') ) {
    function wos_is_serialized($data) {
        if (!is_string($data)) return false;
        $data = trim($data);
        if ($data === 'N;') return true;
        if (!preg_match('/^[adObis]:/', $data)) return false;
        return @unserialize($data) !== false;
    }
}

if ( ! function_exists('wos_is_json') ) {
    function wos_is_json($string) {
        if (!is_string($string)) return false;
        json_decode($string);
        return (json_last_error() === JSON_ERROR_NONE);
    }
}

/**
 * Estrae un final_sku dai meta in modo robusto (case-insensitive e ricorsivo).
 * Supporta:
 * - $meta['final_sku']
 * - $meta['_wc_ai_customization']['final_sku']
 * - qualunque altra occorrenza "final_sku" annidata
 */
if ( ! function_exists('wos_extract_final_sku') ) {
    function wos_extract_final_sku($meta) {
        if (!is_array($meta)) return null;

        if (!empty($meta['final_sku']) && is_string($meta['final_sku'])) {
            return trim($meta['final_sku']);
        }
        if (!empty($meta['_wc_ai_customization']['final_sku']) && is_string($meta['_wc_ai_customization']['final_sku'])) {
            return trim($meta['_wc_ai_customization']['final_sku']);
        }

        $stack = [$meta];
        while ($stack) {
            $node = array_pop($stack);
            if (!is_array($node)) continue;

            foreach ($node as $k => $v) {
                if (is_string($k) && strcasecmp($k, 'final_sku') === 0 && is_string($v) && trim($v) !== '') {
                    return trim($v);
                }
                if (is_array($v)) {
                    $stack[] = $v;
                }
            }
        }
        return null;
    }
}


/**
 * Admin bulk actions
 */
add_filter('bulk_actions-edit-shop_order', 'wos_register_bulk_actions');
function wos_register_bulk_actions($bulk_actions) {
    $bulk_actions['wos_reset_sync']  = __('Reset Sync (wos)', 'wp-order-sync');
    $bulk_actions['wos_mark_synced'] = __('Mark as Synced (wos)', 'wp-order-sync');
    return $bulk_actions;
}

add_filter('handle_bulk_actions-edit-shop_order', 'wos_handle_bulk_actions', 10, 3);
function wos_handle_bulk_actions($redirect_to, $doaction, $post_ids) {
    if ($doaction === 'wos_reset_sync') {
        $reset_count = 0;
        foreach ($post_ids as $post_id) {
            delete_post_meta($post_id, '_wos_synced');
            $reset_count++;
        }
        $redirect_to = add_query_arg('wos_reset_sync', $reset_count, $redirect_to);
    }

    if ($doaction === 'wos_mark_synced') {
        $mark_count = 0;
        foreach ($post_ids as $post_id) {
            update_post_meta($post_id, '_wos_synced', 1);
            $mark_count++;
        }
        $redirect_to = add_query_arg('wos_mark_synced', $mark_count, $redirect_to);
    }

    return $redirect_to;
}

add_action('admin_notices', 'wos_bulk_action_admin_notice');
function wos_bulk_action_admin_notice() {
    if (!empty($_REQUEST['wos_reset_sync'])) {
        $count = intval($_REQUEST['wos_reset_sync']);
        printf(
            '<div id="message" class="updated fade"><p>%s</p></div>',
            sprintf(
                _n('%s ordine è ora desincronizzato.', '%s ordini sono ora desincronizzati.', $count, 'wp-order-sync'),
                $count
            )
        );
    }

    if (!empty($_REQUEST['wos_mark_synced'])) {
        $count = intval($_REQUEST['wos_mark_synced']);
        printf(
            '<div id="message" class="updated fade"><p>%s</p></div>',
            sprintf(
                _n('%s ordine è ora marcato come sincronizzato.', '%s ordini sono ora marcati come sincronizzati.', $count, 'wp-order-sync'),
                $count
            )
        );
    }
}
