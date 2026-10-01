-- +goose Up
-- outbound status broadcasts from agents to users (status set by agents for users)
-- broadcast_object_template - common template for all users
--                           - might be different for each agent
CREATE TABLE IF NOT EXISTS wamd.broadcast_statuses(
    broadcast_status_id UUID PRIMARY KEY DEFAULT uuidv7(),
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
CREATE INDEX IF NOT EXISTS idx_broadcast_statuses_org_scheduled_at
    ON wamd.broadcast_statuses(organization_id, scheduled_at DESC);

-- media used for the broadcast status
CREATE TABLE IF NOT EXISTS wamd.broadcast_status_media(
    broadcast_status_id UUID NOT NULL REFERENCES wamd.broadcast_statuses(broadcast_status_id),
    media_id UUID NOT NULL REFERENCES wamd.common_message_media(media_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (broadcast_status_id, media_id)
);

-- agents from which the broadcasts are sent
CREATE TABLE IF NOT EXISTS wamd.broadcast_status_dispatchers(
    broadcast_status_id UUID NOT
        NULL REFERENCES wamd.broadcast_statuses(broadcast_status_id),
    from_agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK(
        status IN(
            'pending',
            'set',
            'failed',
            'cancelled'
        )
    ),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    PRIMARY KEY (broadcast_status_id, from_agent_id)
);

-- job queue for sending broadcast statuses
-- use SKIP LOCKED to prevent multiple jobs from being processed concurrently
CREATE TABLE IF NOT EXISTS wamd.broadcast_status_job_queue(
    broadcast_status_id UUID NOT NULL
        REFERENCES wamd.broadcast_statuses(broadcast_status_id),
    from_agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    from_agent_phone VARCHAR(20) NOT NULL,
    message_agent JSONB NOT NULL,  -- agent specific broadcast object
    message_id TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK(
        status IN(
            'pending',
            'processing', -- claimed by FetchQueuedStatusesForSending, awaiting send
            'processed',  -- terminal: sent successfully
            'failed',
            'cancelled'
        )
    ),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    scheduled_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ,
    error_message TEXT,
    PRIMARY KEY (broadcast_status_id, from_agent_id)
);
-- persists the WhatsApp message ID for each dispatched status job, so incoming
-- view/read receipts can still be attributed to a campaign after a server
-- restart wipes the in-memory message-id -> campaign map
CREATE INDEX IF NOT EXISTS idx_broadcast_status_job_queue_message_id
    ON wamd.broadcast_status_job_queue (message_id)
    WHERE message_id IS NOT NULL;
-- backs the FetchQueuedStatusesForSending poll: claim pending jobs due now
CREATE INDEX IF NOT EXISTS idx_broadcast_status_job_queue_pending_scheduled
    ON wamd.broadcast_status_job_queue(scheduled_at)
    WHERE status = 'pending';

-- viewers of broadcasts
-- attribute each view to the dispatcher agent whose status post was viewed,
-- since a broadcast_status can be dispatched via multiple agent accounts
--
-- viewer phone is intentionally not stored here: it's resolved from
-- viewer_whatsapp_jid on demand via the bridge's LID<->PN map
-- (see ResolvePhoneForJID), which stays accurate as mappings are learned
-- after this row is written, unlike a value captured once at insert time
CREATE TABLE IF NOT EXISTS wamd.broadcast_status_viewers(
    broadcast_status_id UUID NOT NULL
        REFERENCES wamd.broadcast_statuses(broadcast_status_id),
    from_agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    viewer_whatsapp_jid TEXT NOT NULL,
    viewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (broadcast_status_id, from_agent_id, viewer_whatsapp_jid)
);


-- +goose Down
DROP TABLE IF EXISTS wamd.broadcast_status_viewers;
DROP TABLE IF EXISTS wamd.broadcast_status_job_queue;
DROP TABLE IF EXISTS wamd.broadcast_status_dispatchers;
DROP TABLE IF EXISTS wamd.broadcast_status_media;
DROP TABLE IF EXISTS wamd.broadcast_statuses;