-- +goose Up
------------------------------
-- common
------------------------------
-- application name enum for specifying authorization for applications
-- available for organizations
CREATE TYPE core.app AS ENUM(
    'console',
    'bots',
    'tickets'
);

-- enum type for various platforms (bedrock of conversations)
-- example: if a user communicated with an organization on whatsapp,
-- the platform if 'whatsapp'
CREATE TYPE core.platform AS ENUM(
    'whatsapp',
    'instagram',
    'telegram',
    'windows',
    'mac',
    'debian',
    'web',
    'slack',
    'msteams',
    'discord'
);

-- agent role enum
CREATE TYPE core.agent_role AS ENUM(
    'admin',
    'support',
    'coordinator'
);

-- when a user is conversing with a bot on whatsapp,
-- and a simple whatsapp message is sent as response
-- the connector value will be 'null'
-- if a complex response is sent back on whatsapp which
-- invokes an llm, the value can be 'openai'/'claude', etc 
-- depending on the connector
CREATE TYPE core.connector AS ENUM(
    'openai-gpt5-pro',
    'openai-gpt5',
    'openai-mini',
    'ide',
    'octave',
    'zoho',
    'indiamart',
    'postgres'
);

------------------------------
-- whatsapp
------------------------------
-- system changes to the user's whatsapp account
CREATE TYPE whatsapp.user_system_change AS ENUM(
    'customer-changed-number',
    'customer-identity-changed'
);

-- message types for whatsapp
CREATE TYPE whatsapp.message_type AS ENUM(
    -- regular messages
    'text',
    'image',
    'audio',
    'video',
    'document',
    'sticker',
    'reaction',
    'location',
    'contacts',
    -- interactive messages
    'interactive_address_message',
    'interactive_booking_confirmation',
    'interactive_button',
    'interactive_call_permission_request',
    'interactive_catalog_message',
    'interactive_cta_url',
    'interactive_flow',
    'interactive_form_message',
    'interactive_list',
    'interactive_location_request_message',
    'interactive_menu_options',
    'interactive_message_with_link',
    'interactive_message_with_link_status',
    'interactive_order_details',
    'interactive_order_status',
    'interactive_product',
    'interactive_product_list',
    'interactive_voice_call',
    'interactive_carousel',
    -- template messages
    'template_authentication',
    'template_coupon',
    'template_catalog',
    'template_interactive',
    'template_limited_time_offer',
    'template_media_card_carousel',
    'template_multi_product_message',
    'template_product_card_carousel',
    'template_single_product_message',
    'template_text',
    'template_media',
    -- incoming messages
    'button',
    'interactive',
    'order',
    'system',
    'unsupported',
    'revoke'
);


-- +goose Down
DROP TYPE IF EXISTS whatsapp.message_type;
DROP TYPE IF EXISTS whatsapp.user_system_change;
DROP TYPE IF EXISTS core.connector;
DROP TYPE IF EXISTS core.agent_role;
DROP TYPE IF EXISTS core.platform;
DROP TYPE IF EXISTS core.app;