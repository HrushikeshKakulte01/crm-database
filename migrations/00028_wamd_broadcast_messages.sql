-- +goose Up
-- outbound message broadcasts from agents to users
-- broadcast_object_template - common template for all users
--                           - might be different for each user
CREATE TABLE IF NOT EXISTS wamd.broadcast_messages(
    broadcast_message_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    broadcast_name TEXT NOT NULL,
    scheduled_by_agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    message_template JSONB NOT NULL,
    is_now BOOLEAN NOT NULL DEFAULT false,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK(
        status IN(
            'pending',
            'processed',
            'failed',
            'cancelled'
        )
    ),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    scheduled_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ,
    error_message TEXT
);
-- org-scoped listing/paginating of broadcasts, ordered by scheduled_at
CREATE INDEX IF NOT EXISTS idx_broadcast_messages_org_scheduled_at
    ON wamd.broadcast_messages(organization_id, scheduled_at DESC);

-- media used for the broadcast message
CREATE TABLE IF NOT EXISTS wamd.broadcast_message_media(
    broadcast_message_id UUID NOT NULL REFERENCES wamd.broadcast_messages(broadcast_message_id),
    media_id UUID NOT NULL REFERENCES wamd.common_message_media(media_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (broadcast_message_id, media_id)
);

-- actual users for which the broadcast is scheduled
CREATE TABLE IF NOT EXISTS wamd.broadcast_message_recipients(
    broadcast_message_id UUID NOT NULL REFERENCES wamd.broadcast_messages(broadcast_message_id),
    from_agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    to_user_id UUID NOT NULL REFERENCES core.users(user_id),
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK(
        status IN(
            'pending',
            'delivered',
            'read',
            'failed',
            'cancelled'
        )
    ),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delivered_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ,
    failed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    PRIMARY KEY (broadcast_message_id, from_agent_id, to_user_id, status),
    UNIQUE (broadcast_message_id, from_agent_id, to_user_id)
);

-- job queue for sending broadcast messages
-- use SKIP LOCKED to prevent multiple jobs from being processed concurrently
CREATE TABLE IF NOT EXISTS wamd.broadcast_message_job_queue(
    broadcast_message_id UUID NOT NULL REFERENCES wamd.broadcast_messages(broadcast_message_id),
    from_agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    from_agent_phone VARCHAR(20) NOT NULL,
    to_user_id UUID NOT NULL REFERENCES core.users(user_id),
    to_user_phone VARCHAR(20) NOT NULL,
    message_user JSONB NOT NULL,  -- user specific broadcast object
    message_id TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK(
        status IN(
            'pending',
            'processing', -- claimed by FetchQueuedMessagesForSending, awaiting send
            'sent',
            'processed',
            'failed',
            'cancelled'
        )
    ),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    scheduled_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ,
    error_message TEXT,
    PRIMARY KEY (broadcast_message_id, from_agent_id, to_user_id)
);
-- persists the WhatsApp message ID for each dispatched message job, so incoming
-- read receipts can still be attributed to a campaign after a server restart
-- wipes the in-memory message-id -> campaign map
CREATE INDEX IF NOT EXISTS idx_broadcast_message_job_queue_message_id
    ON wamd.broadcast_message_job_queue (message_id)
    WHERE message_id IS NOT NULL;
-- backs the FetchQueuedMessagesForSending poll: claim pending jobs due now
CREATE INDEX IF NOT EXISTS idx_broadcast_message_job_queue_pending_scheduled
    ON wamd.broadcast_message_job_queue(scheduled_at)
    WHERE status = 'pending';


-- +goose Down
DROP TABLE IF EXISTS wamd.broadcast_message_job_queue;
DROP TABLE IF EXISTS wamd.broadcast_message_recipients;
DROP TABLE IF EXISTS wamd.broadcast_message_media;
DROP TABLE IF EXISTS wamd.broadcast_messages;