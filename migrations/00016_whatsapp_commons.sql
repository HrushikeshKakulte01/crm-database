-- possible common tables:
-- media
-- location
-- currency
-- date time
-- errors
-- contacts
--     -- addresses
--     -- phones
--     -- emails
--     -- urls
-- action
--     -- saved addresses
--     -- address parameters
--     -- buttons
--     -- sections
--     -- section rows
--     -- section product items
-- parameters
--     -- media
--     -- locations
--     -- currencies
--     -- date times
--     -- actions
-- library template body inputs
-- template examples
--     -- header texts
--     -- header text named params
--     -- header handles
--     -- body texts
--     -- body text named params

-- +goose Up
-- common table for all media messages (incoming and outgoing)
-- template-broadcast           - media used for template messages used for broadcasts
-- bot-node-outgoing            - outgoing message from bot to user
-- bot-user-response-incoming   - incoming message from user to bot
-- ticket-incoming              - incoming message from user to agent
-- ticket-outgoing              - outgoing message from agent to user
CREATE TABLE IF NOT EXISTS whatsapp.common_message_media(
    media_id UUID PRIMARY KEY DEFAULT uuidv7(),
    surrogate_phone_id UUID NOT NULL REFERENCES whatsapp.organization_phones(surrogate_phone_id),
    type_origin VARCHAR(20) NOT NULL CHECK(
        type_origin IN(
            'template-broadcast',
            'bot-node-outgoing',
            'bot-user-response-incoming',
            'ticket-incoming',
            'ticket-outgoing'
        )
    ),
    whatsapp_media_id TEXT UNIQUE,
    file_name TEXT,
    caption TEXT,
    mime_type TEXT,
    file_size INTEGER,
    file_hash_sha256 CHAR(64),
    is_animated BOOLEAN NOT NULL DEFAULT false,
    url_bitamin TEXT,
    url_whatsapp TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    re_uploaded_at TIMESTAMPTZ
);

-- common table for all example media messages template creation
CREATE TABLE IF NOT EXISTS whatsapp.common_example_media(
    example_media_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    whatsapp_example_media_id TEXT,
    file_name TEXT,
    mime_type TEXT,
    file_size INTEGER,
    url_bitamin TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    re_uploaded_at TIMESTAMPTZ
);

-- table for storing error messages
CREATE TABLE IF NOT EXISTS whatsapp.common_errors(
    error_id UUID PRIMARY KEY DEFAULT uuidv7(),
    surrogate_phone_id UUID NOT NULL REFERENCES whatsapp.organization_phones(surrogate_phone_id),
    error_type TEXT NOT NULL, -- message, history
    error_object JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- +goose Down
DROP TABLE IF EXISTS whatsapp.common_errors;
DROP TABLE IF EXISTS whatsapp.common_example_media;
DROP TABLE IF EXISTS whatsapp.common_message_media;