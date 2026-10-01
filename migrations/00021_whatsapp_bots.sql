-- +goose Up
-- bot details from whatsapp
-- which waba was this bot created in
CREATE TABLE IF NOT EXISTS whatsapp.bots(
    bot_id UUID PRIMARY KEY REFERENCES core.bots(bot_id),
    surrogate_waba_id UUID NOT NULL REFERENCES whatsapp.organization_wabas(surrogate_waba_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- table for storing bot platform connections
-- an existing bot needs to be connected to a phone number
-- one phone can only have one active bot associated with it
CREATE TABLE IF NOT EXISTS whatsapp.bot_platform_associations(
    bot_id UUID PRIMARY KEY REFERENCES core.bots(bot_id) ON DELETE CASCADE,
    surrogate_phone_id UUID NOT NULL REFERENCES whatsapp.organization_phones(surrogate_phone_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
-- one active bot per organization phone
CREATE UNIQUE INDEX IF NOT EXISTS idx_whatsapp_bot_platform_associations_active
    ON whatsapp.bot_platform_associations(surrogate_phone_id)
    WHERE is_active = true;

-- table for storing bot node contents for whatsapp
-- is_template_message  - if yes, the message is a template message
-- is_contextual_reply  - if yes, the user sees the bot send a whatsapp 'reply'
--                        to their message
-- has_read_receipt     - if yes, the user's messages get blue ticked
-- has_typing_indicator - if yes, there will be a typing indicator shown to the user
--                        chat will be paused until the user replies
-- message_json         - holds the json data to be sent to whatsapp as a JSONB object
CREATE TABLE IF NOT EXISTS whatsapp.bot_nodes(
    node_id UUID PRIMARY KEY REFERENCES core.bot_nodes(node_id) ON DELETE CASCADE,
    is_template_message BOOLEAN NOT NULL DEFAULT false,
    is_contextual_reply BOOLEAN NOT NULL DEFAULT false,
    has_read_receipt BOOLEAN NOT NULL DEFAULT true,
    has_typing_indicator BOOLEAN NOT NULL DEFAULT true,
    message_type whatsapp.message_type NOT NULL,
    message_object JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- bot node content - template details
CREATE TABLE IF NOT EXISTS whatsapp.bot_nodes_template_details(
    node_id UUID PRIMARY KEY REFERENCES whatsapp.bot_nodes(node_id) ON DELETE CASCADE,
    template_id UUID NOT NULL REFERENCES whatsapp.templates(template_id)
);

-- bot node contextual reply details
-- stores the node id of the node that the contextual reply is to
CREATE TABLE IF NOT EXISTS whatsapp.bot_nodes_contextual_reply_details(
    node_id UUID PRIMARY KEY REFERENCES whatsapp.bot_nodes(node_id) ON DELETE CASCADE,
    contextual_reply_node_id UUID NOT NULL REFERENCES whatsapp.bot_nodes(node_id) ON DELETE CASCADE
);


-- +goose Down
DROP TABLE IF EXISTS whatsapp.bot_nodes_contextual_reply_details;
DROP TABLE IF EXISTS whatsapp.bot_nodes_template_details;
DROP TABLE IF EXISTS whatsapp.bot_nodes;
DROP TABLE IF EXISTS whatsapp.bot_platform_associations;
DROP TABLE IF EXISTS whatsapp.bots;