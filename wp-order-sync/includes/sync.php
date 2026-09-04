<?php
// File: includes/sync.php (aligned arrays; preserves cart_id "0"; robust URL normalization)

if ( ! defined('ABSPATH') ) {
    exit;
}

if ( ! function_exists('wos_sync_order_to_ftp') ) {

    add_action('woocommerce_order_status_processing', 'wos_sync_order_to_ftp');
    
    // New Actions for CRM Live Sync — trigger for ALL status changes
    add_action('woocommerce_order_status_changed', 'wos_trigger_crm_sync_status', 10, 4);
    add_action('woocommerce_order_refunded', 'wos_trigger_crm_sync_refund', 10, 2);
    // WooCommerce fires this hook for both legacy post storage and HPOS.
    add_action('woocommerce_trash_order', 'wos_trigger_crm_sync_trash', 10, 1);

    function wos_trigger_crm_sync_status($order_id, $from, $to, $order) {
        // Send CRM updates for ANY status change to ensure data integrity
        wos_sync_crm_data_only($order_id);
    }
    
    function wos_trigger_crm_sync_refund($order_id, $refund_id) {
        wos_sync_crm_data_only($order_id);
    }

    function wos_trigger_crm_sync_trash($order_id) {
        wos_sync_crm_data_only($order_id);
    }

    function wos_sync_order_to_ftp($order_id) {
        if ($order_id === null || $order_id === '' ) {
            return;
        }

        $order = wc_get_order($order_id);
        if (!$order) {
            error_log('WP Order Sync: Ordine non trovato. ID: ' . $order_id);
            return;
        }

        // WC_Order CRUD uses wp_postmeta on legacy stores and wc_orders_meta on HPOS.
        if (wos_order_is_synced($order)) {
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
        $price_decimals = function_exists('wc_get_price_decimals') ? wc_get_price_decimals() : 2;
        $created_at = $order->get_date_created();
        $order_data = [
            'id'                        => $order->get_order_number(),
            'number'                    => $order->get_order_number(),
            'site_name'                 => $site_name,
            // ISO 8601 preserves the real order timestamp and its timezone;
            // the explicit GMT value makes cross-system comparisons reliable.
            'order_date'                => $created_at ? $created_at->date('c') : '',
            'order_date_gmt'            => $created_at ? gmdate('c', $created_at->getTimestamp()) : '',
            'customer_note'             => $order->get_customer_note(),
            'invoice'                   => wos_get_production_invoice_data($order),
            'print_files_with_cart_id'  => $print_files_with_cart_id,
            'screenshots_with_cart_id'  => $screenshots_with_cart_id,
            'cut_with_cart_id'          => $cuts_with_cart_id,
            'line_items'                => [],
        ];

        foreach ($order->get_items() as $item) {
            $product = $item->get_product();
            if (!$product) continue;

            $meta = wos_get_order_item_meta_data($item);
            $sku  = wos_get_item_sku($item, $product);

            $order_data['line_items'][] = [
                'product_id' => $product->get_id(),
                'name'       => $item->get_name(),
                'quantity'   => $item->get_quantity(),
                'sku'        => $sku,
                // Excluding tax, matching WooCommerce item totals.
                'unit_price' => round((float) ( $item->get_quantity() > 0 ? $item->get_subtotal() / $item->get_quantity() : 0 ), $price_decimals),
                'line_total' => round((float) $item->get_total(), $price_decimals),
                'line_tax'   => round((float) $item->get_total_tax(), $price_decimals),
                'image'     => [
                    'id'  => $product->get_image_id(),
                    'src' => wp_get_attachment_url($product->get_image_id()),
                ],
                'meta_data' => $meta,
            ];
        }

        // Explicit totals keep the ERP independent from customization metadata.
        $order_data['totals'] = [
            'subtotal'     => round((float) $order->get_subtotal(), $price_decimals),
            'discount'     => round((float) $order->get_discount_total(), $price_decimals),
            'shipping'     => round((float) $order->get_shipping_total(), $price_decimals),
            'shipping_tax' => round((float) $order->get_shipping_tax(), $price_decimals),
            'tax'          => round((float) $order->get_total_tax(), $price_decimals),
            'total'        => round((float) $order->get_total(), $price_decimals),
            'currency'     => $order->get_currency(),
        ];

        $json_data = json_encode($order_data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        if ($json_data === false) {
            error_log('WP Order Sync: Errore json_encode ordine ' . $order_id);
            return;
        }

        // --- 5) Upload FTP (Production JSON) ---
        $order_number    = $order->get_order_number();
        $filename        = 'order_' . $order_number . '.json';
        $remote_file     = rtrim($ftp_path, '/') . '/' . $filename;

        $upload_response = wos_upload_to_ftp($ftp_host, $ftp_port, $ftp_username, $ftp_password, $remote_file, $json_data);

        if (is_wp_error($upload_response)) {
            error_log('WP Order Sync: Upload produzione fallito - ' . $upload_response->get_error_message());
            return;
        }

        // --- 6) CRM JSON Upload ---
        // DEPRECATO: Adesso wos_sync_crm_data_only si occupa sia della parte FTP CRM che della Webhook API CRM
        // ed è agganciato a woocommerce_order_status_changed (che include anche 'processing')
        
        wos_set_order_synced($order, true);
    }
}

/**
 * Return the stable invoice block used only by the production FTP payload.
 * Older orders and orders without a request still expose an explicit false
 * flag, allowing the ERP to branch without testing for missing properties.
 */
if ( ! function_exists('wos_get_production_invoice_data') ) {
    function wos_get_production_invoice_data($order) {
        $not_requested = [
            'schema_version' => 1,
            'requested'      => false,
        ];

        if (!$order || 'yes' !== $order->get_meta('_wc_ai_invoice_requested', true)) {
            return $not_requested;
        }

        $invoice = $order->get_meta('_wc_ai_invoice_data', true);
        if (!is_array($invoice)) {
            return $not_requested;
        }

        // Whitelist the versioned contract so unrelated order metadata can
        // never leak into the production file.
        $address = isset($invoice['address']) && is_array($invoice['address']) ? $invoice['address'] : [];
        // Preserve contacts even for legacy orders whose invoice metadata was
        // saved before the dedicated fields existed.
        $invoice_email = trim((string)($invoice['email'] ?? ''));
        $invoice_phone = trim((string)($invoice['phone'] ?? ''));
        if ('' === $invoice_email && is_callable([$order, 'get_billing_email'])) {
            $invoice_email = (string)$order->get_billing_email();
        }
        if ('' === $invoice_email && is_callable([$order, 'get_shipping_email'])) {
            $invoice_email = (string)$order->get_shipping_email();
        }
        if ('' === $invoice_phone && is_callable([$order, 'get_billing_phone'])) {
            $invoice_phone = (string)$order->get_billing_phone();
        }
        if ('' === $invoice_phone && is_callable([$order, 'get_shipping_phone'])) {
            $invoice_phone = (string)$order->get_shipping_phone();
        }

        return [
            'schema_version' => 1,
            'requested'      => true,
            'customer_type'  => (string)($invoice['customer_type'] ?? ''),
            'company_name'   => (string)($invoice['company_name'] ?? ''),
            'first_name'     => (string)($invoice['first_name'] ?? ''),
            'last_name'      => (string)($invoice['last_name'] ?? ''),
            'tax_country'    => (string)($invoice['tax_country'] ?? ''),
            'vat_number'     => (string)($invoice['vat_number'] ?? ''),
            'tax_code'       => (string)($invoice['tax_code'] ?? ''),
            'recipient_code' => (string)($invoice['recipient_code'] ?? ''),
            'pec'            => (string)($invoice['pec'] ?? ''),
            'email'          => $invoice_email,
            'phone'          => $invoice_phone,
            'address'        => [
                'address_1' => (string)($address['address_1'] ?? ''),
                'address_2' => (string)($address['address_2'] ?? ''),
                'postcode'  => (string)($address['postcode'] ?? ''),
                'city'      => (string)($address['city'] ?? ''),
                'province'  => (string)($address['province'] ?? ''),
                'country'   => (string)($address['country'] ?? ''),
            ],
        ];
    }
}

/**
 * Read/write the production sync marker through WooCommerce CRUD so it works
 * with both the legacy posts datastore and HPOS.
 */
if ( ! function_exists('wos_order_is_synced') ) {
    function wos_order_is_synced($order_or_id) {
        $order = $order_or_id instanceof WC_Order ? $order_or_id : wc_get_order($order_or_id);
        return $order ? (bool)$order->get_meta('_wos_synced', true) : false;
    }
}

if ( ! function_exists('wos_set_order_synced') ) {
    function wos_set_order_synced($order_or_id, $is_synced) {
        $order = $order_or_id instanceof WC_Order ? $order_or_id : wc_get_order($order_or_id);
        if (!$order) {
            return false;
        }

        if ($is_synced) {
            $order->update_meta_data('_wos_synced', 1);
        } else {
            $order->delete_meta_data('_wos_synced');
        }

        $order->save_meta_data();
        return true;
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
            'final_sku',
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
 * Consistently extract SKU for an order item, including size and final_sku overrides.
 */
if ( ! function_exists('wos_get_item_sku') ) {
    function wos_get_item_sku($item, $product) {
        if (!$product) return '';
        
        $meta = wos_get_order_item_meta_data($item);
        $sku  = $product->get_sku();

        // Add size suffix if present
        if (isset($meta['_wc_ai_customization']['selected_size']) && $meta['_wc_ai_customization']['selected_size'] !== '') {
            $sku .= '-' . $meta['_wc_ai_customization']['selected_size'];
        }

        // Apply final_sku override if present
        $maybe_final = wos_extract_final_sku($meta);
        if (is_string($maybe_final) && $maybe_final !== '') {
            $sku = $maybe_final;
        }
        
        return $sku;
    }
}

/**
 * Generate CRM JSON payload from a WooCommerce order.
 * Extracts standard customer and financial data only.
 */
if ( ! function_exists('wos_generate_crm_json') ) {
    function wos_generate_crm_json($order, $site_name) {
        if (!$order) return false;

        // Return a special payload for cancelled, failed, or trashed orders
        $delete_statuses = ['cancelled', 'failed', 'trash'];
        if (in_array($order->get_status(), $delete_statuses)) {
            $crm_data = [
                'type'         => 'crm_delete',
                'site_name'    => $site_name,
                'order_number' => $order->get_order_number(),
            ];
            return json_encode($crm_data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        }

        // Skip refunds or other sub-types that do not support get_billing_email()
        if (!is_callable([$order, 'get_billing_email'])) {
            return false;
        }

        // Customer data
        $customer_data = [
            'email'            => $order->get_billing_email(),
            'first_name'       => $order->get_billing_first_name(),
            'last_name'        => $order->get_billing_last_name(),
            'phone'            => $order->get_billing_phone(),
            'billing_address'  => implode(', ', array_filter([
                $order->get_billing_address_1(),
                $order->get_billing_address_2(),
                $order->get_billing_postcode(),
                $order->get_billing_city(),
                $order->get_billing_state(),
                $order->get_billing_country(),
            ])),
            'shipping_address' => implode(', ', array_filter([
                $order->get_shipping_address_1(),
                $order->get_shipping_address_2(),
                $order->get_shipping_postcode(),
                $order->get_shipping_city(),
                $order->get_shipping_state(),
                $order->get_shipping_country(),
            ])),
        ];

        // Financial data
        // get_total_refunded() e get_total_tax_refunded() in WooCommerce
        // restituiscono numeri positivi (es: "10.00" per un rimborso di 10 euro).
        $refund_amount = (float)$order->get_total_refunded();
        $refund_tax = (float)$order->get_total_tax_refunded();
        
        $net_total = (float)$order->get_total() - $refund_amount;
        $net_tax = (float)$order->get_total_tax() - $refund_tax;

        // Include both standard WooCommerce coupons and promo codes applied by
        // the product customizer. These values are also used by CRM analytics.
        $coupon_codes = $order->get_coupon_codes();
        foreach ($order->get_items() as $item) {
            $meta = $item->get_meta('_wc_ai_customization');
            if (is_array($meta) && isset($meta['discount_applied'])) {
                $discount_data = $meta['discount_applied'];
                if (
                    isset($discount_data['source'], $discount_data['code']) &&
                    $discount_data['source'] === 'promo_code' &&
                    $discount_data['code'] !== ''
                ) {
                    $coupon_codes[] = strtoupper(trim((string)$discount_data['code']));
                }
            }
        }
        $coupon_codes = array_values(array_unique(array_filter(array_map('trim', $coupon_codes))));
        
        $financials = [
            'total'          => $net_total, // Netto (Lordo - Rimborso)
            'tax'            => $net_tax,   // Tasse Nette
            'shipping'       => (float)$order->get_shipping_total(), // La spedizione di solito non cambia, a meno che non sia rimborsata specificamente
            'discount'       => (float)$order->get_discount_total(),
            'coupons'        => $coupon_codes,
            'refund_amount'  => $refund_amount,
            'refund_tax'     => $refund_tax,
            'payment_method' => $order->get_payment_method_title(),
            'currency'       => $order->get_currency(),
        ];

        // Products
        $products = [];
        foreach ($order->get_items() as $item) {
            $product = $item->get_product();
            $sku = wos_get_item_sku($item, $product);

            $products[] = [
                'sku'        => $sku,
                'name'       => $item->get_name(),
                'quantity'   => $item->get_quantity(),
                'line_total' => (float)$item->get_total(),
            ];
        }

        $crm_data = [
            'type'         => 'crm_order',
            'site_name'    => $site_name,
            'order_number' => $order->get_order_number(),
            'order_date'   => $order->get_date_created() ? $order->get_date_created()->date('c') : date('c'),
            'status'       => $order->get_status(),
            'customer'     => $customer_data,
            'financials'   => $financials,
            'products'     => $products,
        ];

        $json = json_encode($crm_data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        if ($json === false) {
            error_log('WP Order Sync: Errore json_encode CRM per ordine ' . $order->get_id());
            return false;
        }

        return $json;
    }
}

/**
 * Admin bulk actions
 */
add_filter('bulk_actions-edit-shop_order', 'wos_register_bulk_actions');
add_filter('bulk_actions-woocommerce_page_wc-orders', 'wos_register_bulk_actions');
function wos_register_bulk_actions($bulk_actions) {
    $bulk_actions['wos_reset_sync']  = __('Reset Sync (wos)', 'wp-order-sync');
    $bulk_actions['wos_mark_synced'] = __('Mark as Synced (wos)', 'wp-order-sync');
    return $bulk_actions;
}

add_filter('handle_bulk_actions-edit-shop_order', 'wos_handle_bulk_actions', 10, 3);
add_filter('handle_bulk_actions-woocommerce_page_wc-orders', 'wos_handle_bulk_actions', 10, 3);
function wos_handle_bulk_actions($redirect_to, $doaction, $order_ids) {
    if ($doaction === 'wos_reset_sync') {
        $reset_count = 0;
        foreach ($order_ids as $order_id) {
            if (wos_set_order_synced($order_id, false)) {
                $reset_count++;
            }
        }
        $redirect_to = add_query_arg('wos_reset_sync', $reset_count, $redirect_to);
    }

    if ($doaction === 'wos_mark_synced') {
        $mark_count = 0;
        foreach ($order_ids as $order_id) {
            if (wos_set_order_synced($order_id, true)) {
                $mark_count++;
            }
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

/**
 * Sincronizza SOLO i dati CRM per un ordine specifico via REST API.
 */
function wos_sync_crm_data_only($order_id) {
    if (!$order_id) return;
    $order = wc_get_order($order_id);
    if (!$order) return;

    $options = get_option('wos_settings');
    $api_url = $options['wos_crm_api_url'] ?? '';
    $api_key = $options['wos_crm_api_key'] ?? '';
    $site_name = $options['wos_site_name'] ?? get_bloginfo('name');
    
    if (empty($api_url)) {
        return;
    }

    $crm_json = wos_generate_crm_json($order, $site_name);
    if ($crm_json === false) {
        return;
    }

    $headers = [
        'Content-Type' => 'application/json',
        'Accept'       => 'application/json',
    ];
    if (!empty($api_key)) {
        $headers['Authorization'] = 'Bearer ' . $api_key;
    }

    $response = wp_remote_post($api_url, [
        'method'      => 'POST',
        'timeout'     => 15,
        'redirection' => 5,
        'httpversion' => '1.0',
        'blocking'    => true,
        'headers'     => $headers,
        'body'        => $crm_json,
        'cookies'     => array()
    ]);

    if (is_wp_error($response)) {
        error_log('WP Order Sync: Errore chiamata CRM API per ordine ' . $order->get_order_number() . ' - ' . $response->get_error_message());
    } else {
        $http_code = wp_remote_retrieve_response_code($response);
        if ($http_code < 200 || $http_code >= 300) {
             error_log('WP Order Sync: La CRM API ha restituito errore ' . $http_code . ' per ordine ' . $order->get_order_number() . '. Body: ' . wp_remote_retrieve_body($response));
        }
    }
}

/**
 * AJAX handler to test the CRM API connection.
 */
add_action('wp_ajax_wos_test_api_connection', 'wos_test_api_connection_ajax');
function wos_test_api_connection_ajax() {
    if (!current_user_can('manage_options')) {
        wp_send_json_error(['message' => __('Permesso negato.', 'wp-order-sync')]);
    }

    $api_url = isset($_POST['url']) ? sanitize_url($_POST['url']) : '';
    $api_key = isset($_POST['key']) ? sanitize_text_field($_POST['key']) : '';

    if (empty($api_url)) {
        wp_send_json_error(['message' => __('URL Webhook mancante.', 'wp-order-sync')]);
    }

    // Prepare a test payload (similar to health check or dummy order)
    $test_data = [
        'type'         => 'crm_test',
        'site_name'    => get_bloginfo('name'),
        'timestamp'    => date('c'),
        'message'      => 'Test connection from WordPress'
    ];

    $headers = [
        'Content-Type' => 'application/json',
        'Accept'       => 'application/json',
    ];
    if (!empty($api_key)) {
        $headers['Authorization'] = 'Bearer ' . $api_key;
    }

    $response = wp_remote_post($api_url, [
        'method'  => 'POST',
        'timeout' => 10,
        'headers' => $headers,
        'body'    => json_encode($test_data),
    ]);

    if (is_wp_error($response)) {
        wp_send_json_error(['message' => $response->get_error_message()]);
    } else {
        $http_code = wp_remote_retrieve_response_code($response);
        if ($http_code >= 200 && $http_code < 300) {
            wp_send_json_success(['message' => __('Connessione riuscita!', 'wp-order-sync')]);
        } else {
            wp_send_json_error(['message' => sprintf(__('Errore HTTP %d: %s', 'wp-order-sync'), $http_code, wp_remote_retrieve_body($response))]);
        }
    }
}

/**
 * Sends a generic payload to the CRM API.
 */
if ( ! function_exists('wos_send_payload_to_api') ) {
    function wos_send_payload_to_api($payload) {
        $options = get_option('wos_settings');
        $api_url = $options['wos_crm_api_url'] ?? '';
        $api_key = $options['wos_crm_api_key'] ?? '';

        if (empty($api_url)) {
            error_log('WP Order Sync: Impossibile sincronizzare. URL Webhook mancante nelle impostazioni.');
            return false;
        }

        $headers = [
            'Content-Type' => 'application/json',
            'Accept'       => 'application/json',
        ];
        if (!empty($api_key)) {
            $headers['Authorization'] = 'Bearer ' . $api_key;
        }

        $body = is_string($payload) ? $payload : json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);

        $response = wp_remote_post($api_url, [
            'method'      => 'POST',
            'timeout'     => 15,
            'redirection' => 5,
            'httpversion' => '1.0',
            'blocking'    => true,
            'headers'     => $headers,
            'body'        => $body,
            'cookies'     => array()
        ]);

        if (is_wp_error($response)) {
            error_log('WP Order Sync: Errore chiamata CRM API - ' . $response->get_error_message());
            return false;
        }

        $http_code = wp_remote_retrieve_response_code($response);
        if ($http_code < 200 || $http_code >= 300) {
             error_log('WP Order Sync: La CRM API ha restituito errore ' . $http_code . '. Body: ' . wp_remote_retrieve_body($response));
             return false;
        }

        return true;
    }
}
