-- +goose Up
-- store the webhooks from whatsapp
-- 'status' is used to track the processing of the webhook
CREATE TABLE IF NOT EXISTS whatsapp.common_webhooks(
    webhook_id UUID DEFAULT uuidv7(),
    webhook_data JSONB NOT NULL,
    webhook_type TEXT NOT NULL CHECK(
        webhook_type IN(
            'phone_number_quality_update',
            'message_template_quality_update',
            'message_template_status_update',
            'template_category_update',
            'incoming_message_update',
            'outgoing_message_status_update',
            'smb_app_state_sync',
            'smb_message_echoes',
            'history',
            'account_update',
            'common_error_update',
            'unknown'
        )
    ),
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK(
        status IN(
            'pending',
            'processing',
            'processed',
            'failed'
        )
    ),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processing_started_at TIMESTAMPTZ,
    processed_at TIMESTAMPTZ,
    failed_at TIMESTAMPTZ,
    PRIMARY KEY (webhook_id, created_at)
) PARTITION BY RANGE (created_at);

-- partial index for efficiently querying unhandled webhooks
-- only include unhandled webhooks
-- webhook_type is included to efficiently query by type
-- created_at is included to efficiently query by time
CREATE INDEX IF NOT EXISTS idx_whatsapp_common_webhooks_unhandled
    ON whatsapp.common_webhooks(webhook_type, created_at)
    WHERE status = 'pending';
-- pending webhooks by creation time for queue processing
CREATE INDEX IF NOT EXISTS idx_common_webhooks_pending_created_at
    ON whatsapp.common_webhooks(created_at, webhook_id)
    WHERE status = 'pending';

-- configure pg_partman for automatic partition management
-- creates monthly partitions with 2 months pre-created and 12 months retention
SELECT partman.create_parent(
    p_parent_table := 'whatsapp.common_webhooks',
    p_control := 'created_at',
    p_type := 'range',
    p_interval := '1 month',
    p_premake := 12,
    p_start_partition := CURRENT_DATE::TEXT
);

-- set retention to 12 months (automatically drop partitions older than 12 months)
UPDATE partman.part_config
SET
    retention = '12 months',
    retention_keep_table = false,
    retention_keep_index = false
WHERE parent_table = 'whatsapp.common_webhooks';

-- run maintenance to create initial partitions
SELECT partman.run_maintenance('whatsapp.common_webhooks');


-- +goose Down
-- remove partition configuration before dropping table
DELETE FROM partman.part_config WHERE parent_table = 'whatsapp.common_webhooks';
DROP TABLE IF EXISTS whatsapp.common_webhooks;
-- template table that is used as blueprint for new partitions
-- the template table is named template_<schema>_<table_name>
DROP TABLE IF EXISTS partman.template_whatsapp_common_webhooks;