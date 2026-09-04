<?php
/*
Plugin Name: WP Order Sync
Description: Sincronizza i nuovi ordini di WooCommerce al gestionale tramite REST API.
Version: 3.12
Author: Paolo AI
*/

// Evita l'accesso diretto
if (!defined('ABSPATH')) {
    exit;
}

// The plugin accesses orders only through WooCommerce CRUD APIs, so the same
// package works with both legacy posts storage and HPOS during a gradual rollout.
add_action('before_woocommerce_init', function () {
    if (class_exists(\Automattic\WooCommerce\Utilities\FeaturesUtil::class)) {
        \Automattic\WooCommerce\Utilities\FeaturesUtil::declare_compatibility(
            'custom_order_tables',
            __FILE__,
            true
        );
    }
});

// Includi i file necessari
include_once plugin_dir_path(__FILE__) . 'includes/sync.php';
include_once plugin_dir_path(__FILE__) . 'includes/settings.php';
include_once plugin_dir_path(__FILE__) . 'includes/cf7-sync.php';
