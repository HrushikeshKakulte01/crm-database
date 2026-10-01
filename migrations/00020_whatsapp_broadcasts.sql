-- +goose Up
-- outbound whatsapp templates scheduled by an agent for a group of users
-- is_now       - if true, the broadcast will be sent immediately
-- broad
CREATE TABLE IF NOT EXISTS whatsapp.broadcasts(
    broadcast_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    surrogate_phone_id UUID NOT NULL REFERENCES whatsapp.organization_phones(surrogate_phone_id),
    broadcast_name TEXT NOT NULL,
    scheduled_by_agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    template_id UUID NOT NULL REFERENCES whatsapp.templates(template_id),
    is_now BOOLEAN NOT NULL DEFAULT false,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK(
        status IN(
            'pending',
            'processed',
            'failed',
            'cancelled'
        )
    ),
    is_retry BOOLEAN NOT NULL DEFAULT false, -- if true, the broadcast is a retry of a failed broadcast
    retry_attempt INT NOT NULL DEFAULT 0, -- the number of times the broadcast has been retried
    parent_broadcast_id UUID REFERENCES whatsapp.broadcasts(broadcast_id), -- the broadcast that this broadcast is a retry of
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    scheduled_at TIMESTAMPTZ,
    processed_at TIMESTAMPTZ,
    failed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ
);
-- broadcasts by organization, phone, and schedule time
CREATE INDEX IF NOT EXISTS idx_whatsapp_broadcasts_org_phone_scheduled
    ON whatsapp.broadcasts(organization_id, surrogate_phone_id, scheduled_at);
-- lookup retry chains by parent broadcast
CREATE INDEX IF NOT EXISTS idx_whatsapp_broadcasts_parent_broadcast_id
    ON whatsapp.broadcasts(parent_broadcast_id);

-- which tags were used by the agent to select the recipients/users for this broadcast
CREATE TABLE IF NOT EXISTS whatsapp.broadcast_recipient_tags(
    broadcast_id UUID NOT NULL REFERENCES whatsapp.broadcasts(broadcast_id),
    tag_stock_value_id UUID NOT NULL REFERENCES core.user_tag_stock_values(tag_stock_value_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (broadcast_id, tag_stock_value_id)
);

-- which attributes were used by the agent to select the recipients/users for this broadcast
CREATE TABLE IF NOT EXISTS whatsapp.broadcast_recipient_attributes(
    broadcast_id UUID NOT NULL REFERENCES whatsapp.broadcasts(broadcast_id),
    attribute_stock_value_id UUID NOT NULL
        REFERENCES core.user_attribute_stock_values(attribute_stock_value_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (broadcast_id, attribute_stock_value_id)
);

-- bulk upload associations for the broadcast
CREATE TABLE IF NOT EXISTS whatsapp.broadcast_bulk_upload_associations(
    broadcast_id UUID NOT NULL REFERENCES whatsapp.broadcasts(broadcast_id),
    bulk_upload_id UUID NOT NULL REFERENCES core.bulk_uploads(bulk_upload_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (broadcast_id, bulk_upload_id)
);

-- actual users for which the broadcast is scheduled
CREATE TABLE IF NOT EXISTS whatsapp.broadcast_recipients(
    broadcast_id UUID NOT NULL REFERENCES whatsapp.broadcasts(broadcast_id),
    user_id UUID NOT NULL REFERENCES core.users(user_id),
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK(
        status IN(
            'pending',
            'cancelled',
            'sent',
            'delivered',
            'read',
            'failed',
            'played'
        )
    ),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cancelled_at TIMESTAMPTZ,
    sent_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ,
    failed_at TIMESTAMPTZ,
    played_at TIMESTAMPTZ,
    error_object JSONB,
    PRIMARY KEY (broadcast_id, user_id)
);
-- failed recipients for a broadcast
CREATE INDEX IF NOT EXISTS idx_broadcast_recipients_broadcast_failed_at
    ON whatsapp.broadcast_recipients(broadcast_id)
    WHERE failed_at IS NOT NULL;

-- job queue for sending broadcasts
-- use SKIP LOCKED to prevent multiple jobs from being processed concurrently
CREATE TABLE IF NOT EXISTS whatsapp.broadcast_job_queue(
    broadcast_id UUID NOT NULL REFERENCES whatsapp.broadcasts(broadcast_id),
    user_id UUID NOT NULL REFERENCES core.users(user_id),
    broadcast_object_for_user JSONB NOT NULL,  -- user specific broadcast object
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK(
        status IN(
            'pending',
            'processing',
            'processed',
            'failed',
            'cancelled'
        )
    ),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    scheduled_at TIMESTAMPTZ,
    processing_started_at TIMESTAMPTZ,
    processed_at TIMESTAMPTZ,
    failed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    PRIMARY KEY (broadcast_id, user_id)
);
-- pending jobs by schedule time for queue processing
CREATE INDEX IF NOT EXISTS idx_broadcast_job_queue_pending_schedule
    ON whatsapp.broadcast_job_queue(scheduled_at, broadcast_id, user_id)
    WHERE status = 'pending';
-- failed jobs for a broadcast
CREATE INDEX IF NOT EXISTS idx_broadcast_job_queue_broadcast_failed
    ON whatsapp.broadcast_job_queue(broadcast_id)
    WHERE status = 'failed';


-- +goose Down
DROP TABLE IF EXISTS whatsapp.broadcast_job_queue;
DROP TABLE IF EXISTS whatsapp.broadcast_recipients;
DROP TABLE IF EXISTS whatsapp.broadcast_bulk_upload_associations;
DROP TABLE IF EXISTS whatsapp.broadcast_recipient_attributes;
DROP TABLE IF EXISTS whatsapp.broadcast_recipient_tags;
DROP TABLE IF EXISTS whatsapp.broadcasts;