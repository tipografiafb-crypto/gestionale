<?php
/*
Plugin Name: WP Order Sync
Description: Sincronizza i nuovi ordini di WooCommerce al gestionale tramite REST API.
Version: 3.7.1
Author: Paolo AI
*/

// Evita l'accesso diretto
if (!defined('ABSPATH')) {
    exit;
}

// Includi i file necessari
include_once plugin_dir_path(__FILE__) . 'includes/settings.php';
include_once plugin_dir_path(__FILE__) . 'includes/sync.php';
