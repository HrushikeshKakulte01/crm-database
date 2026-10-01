-- +goose Up
-- common table for all media messages (regular + status)
-- broadcast-message     - media used for regular broadcasts
-- broadcast-status      - media used for status broadcasts
CREATE TABLE IF NOT EXISTS wamd.common_message_media(
    media_id UUID PRIMARY KEY DEFAULT uuidv7(),
    type_origin VARCHAR(20) NOT NULL CHECK(
        type_origin IN(
            'broadcast-message',
            'broadcast-status',
            'message-incoming',
            'message-outgoing'
        )
    ),
    whatsapp_media_id TEXT UNIQUE,
    file_name TEXT,
    mime_type TEXT,
    file_size INTEGER,
    file_hash_sha256 CHAR(64),
    is_animated BOOLEAN NOT NULL DEFAULT false,
    url_bitamin TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);


-- +goose Down
DROP TABLE IF EXISTS wamd.common_message_media;