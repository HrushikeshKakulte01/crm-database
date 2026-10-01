-- +goose Up
-- conversations of users over whatsapp
CREATE TABLE IF NOT EXISTS whatsapp.conversations(
    conversation_id UUID PRIMARY KEY REFERENCES core.conversations(conversation_id),
    surrogate_phone_id UUID NOT NULL REFERENCES whatsapp.organization_phones(surrogate_phone_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- table for storing whatsapp specific details for conversation elements
-- actual details of messages sent and received
-- 'whatsapp_message_id' - message id from whatsapp
-- is_broadcast          - if true, the message is a broadcast message
-- is_contextual_reply   - if true, the conversation element was a reply to a previous message
-- is_referral           - if true, the conversation element was a referral message
CREATE TABLE IF NOT EXISTS whatsapp.conversation_elements(
    element_id UUID PRIMARY KEY REFERENCES core.conversation_elements(element_id),
    whatsapp_message_id TEXT UNIQUE NOT NULL,
    message_type whatsapp.message_type NOT NULL,
    is_broadcast BOOLEAN NOT NULL DEFAULT false,
    is_contextual_reply BOOLEAN NOT NULL DEFAULT false,
    is_referral BOOLEAN NOT NULL DEFAULT false,
    message_object JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- details of the broadcast that the conversation elements are a part of
CREATE TABLE IF NOT EXISTS whatsapp.ce_broadcast_details(
    element_id UUID PRIMARY KEY REFERENCES whatsapp.conversation_elements(element_id),
    broadcast_id UUID NOT NULL REFERENCES whatsapp.broadcasts(broadcast_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- lookup broadcast details by broadcast
CREATE INDEX IF NOT EXISTS idx_ce_broadcast_details_broadcast_element
    ON whatsapp.ce_broadcast_details(broadcast_id, element_id);

-- if incoming or outgoing message is a contextual reply, store the details here
CREATE TABLE IF NOT EXISTS whatsapp.ce_contextual_replies(
    element_id UUID PRIMARY KEY REFERENCES whatsapp.conversation_elements(element_id),
    contextual_reply_element_id UUID NOT NULL REFERENCES core.conversation_elements(element_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- table for storing referral details (click-to-whatsapp ad)
CREATE TABLE IF NOT EXISTS whatsapp.ce_referrals(
    element_id UUID PRIMARY KEY REFERENCES whatsapp.conversation_elements(element_id),
    source_id TEXT NOT NULL,
    source_type TEXT NOT NULL,
    source_url TEXT NOT NULL,
    headline TEXT NOT NULL,
    body TEXT NOT NULL,
    media_type TEXT NOT NULL,
    image_url TEXT NOT NULL,
    video_url TEXT NOT NULL,
    thumbnail_url TEXT NOT NULL,
    ctwa_clid TEXT,
    welcome_message_text TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- +goose Down
DROP TABLE IF EXISTS whatsapp.ce_referrals;
DROP TABLE IF EXISTS whatsapp.ce_contextual_replies;
DROP TABLE IF EXISTS whatsapp.ce_broadcast_details;
DROP TABLE IF EXISTS whatsapp.conversation_elements;
DROP TABLE IF EXISTS whatsapp.conversations;