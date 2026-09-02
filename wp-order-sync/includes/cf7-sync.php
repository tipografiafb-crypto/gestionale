<?php
if (!defined('ABSPATH')) {
    exit;
}

/**
 * Capture Contact Form 7 submissions and send them as leads to the CRM
 */
add_action('wpcf7_mail_sent', 'wos_capture_cf7_lead');

function wos_capture_cf7_lead($contact_form) {
    // Get form data
    $submission = WPCF7_Submission::get_instance();
    if (!$submission) {
        return;
    }

    $posted_data = $submission->get_posted_data();
    
    // Extract Email (try common field names)
    $email = '';
    if (!empty($posted_data['your-email'])) $email = $posted_data['your-email'];
    elseif (!empty($posted_data['email'])) $email = $posted_data['email'];
    
    // Without an email we can't create a lead in the CRM
    if (empty($email)) {
        return;
    }

    // Extract First Name and Last Name
    $first_name = '';
    $last_name = '';
    if (!empty($posted_data['your-name'])) {
        $parts = explode(' ', trim($posted_data['your-name']), 2);
        $first_name = $parts[0];
        if (isset($parts[1])) $last_name = $parts[1];
    } elseif (!empty($posted_data['nome'])) {
        $first_name = $posted_data['nome'];
        if (!empty($posted_data['cognome'])) {
            $last_name = $posted_data['cognome'];
        }
    } elseif (!empty($posted_data['first_name'])) {
        $first_name = $posted_data['first_name'];
        if (!empty($posted_data['last_name'])) {
            $last_name = $posted_data['last_name'];
        }
    }

    // Extract Phone
    $phone = '';
    if (!empty($posted_data['your-phone'])) $phone = $posted_data['your-phone'];
    elseif (!empty($posted_data['telefono'])) $phone = $posted_data['telefono'];
    elseif (!empty($posted_data['phone'])) $phone = $posted_data['phone'];

    $form_title = $contact_form->title();

    // Prepare payload
    $payload = [
        'type' => 'crm_lead',
        'site_name' => get_bloginfo('name'),
        'form_title' => $form_title,
        'email' => $email,
        'first_name' => $first_name,
        'last_name' => $last_name,
        'phone' => $phone
    ];

    // Send to CRM (using the existing wos_send_payload_to_api function from sync.php)
    if (function_exists('wos_send_payload_to_api')) {
        wos_send_payload_to_api($payload);
    }
}
