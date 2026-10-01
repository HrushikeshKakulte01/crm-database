-- +goose Up

--
-- indiamart
--
-- store the webhooks from indiamart
-- 'status' is used to track the processing of the webhook
CREATE TABLE IF NOT EXISTS connectors.indiamart_webhooks(
    webhook_id UUID DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    webhook_data JSONB NOT NULL,
    webhook_type TEXT NOT NULL CHECK(
        webhook_type IN(
            'direct_enquiries',
            'buy_leads',
            'pns_calls',
            'catalog_views',
            'whatsapp_enquiries',
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
CREATE INDEX IF NOT EXISTS idx_connector_indiamart_webhooks_unhandled
    ON connectors.indiamart_webhooks(organization_id, webhook_type, created_at)
    WHERE status = 'pending';
-- pending webhooks by creation time for queue processing
CREATE INDEX IF NOT EXISTS idx_connector_indiamart_webhooks_pending_created_at
    ON connectors.indiamart_webhooks(organization_id, created_at, webhook_id)
    WHERE status = 'pending';

-- configure pg_partman for automatic partition management
SELECT partman.create_parent(
    p_parent_table := 'connectors.indiamart_webhooks',
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
WHERE parent_table = 'connectors.indiamart_webhooks';

-- run maintenance to create initial partitions
SELECT partman.run_maintenance('connectors.indiamart_webhooks');


--
-- zoho
--
-- store the webhooks from zoho
CREATE TABLE IF NOT EXISTS connectors.zoho_webhooks(
    webhook_id UUID DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    webhook_data JSONB NOT NULL,
    webhook_type TEXT NOT NULL CHECK(
        webhook_type IN(
            'basic_event',
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

-- indexes
CREATE INDEX IF NOT EXISTS idx_connector_zoho_webhooks_pending_created_at
    ON connectors.zoho_webhooks(organization_id, created_at, webhook_id)
    WHERE status = 'pending';

-- configure pg_partman for automatic partition management
SELECT partman.create_parent(
    p_parent_table := 'connectors.zoho_webhooks',
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
WHERE parent_table = 'connectors.zoho_webhooks';

-- run maintenance to create initial partitions
SELECT partman.run_maintenance('connectors.zoho_webhooks');


--
-- custom event
--
-- store the webhooks from custom events
CREATE TABLE IF NOT EXISTS connectors.custom_event_webhooks(
    webhook_id UUID DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    webhook_data JSONB NOT NULL,
    webhook_type TEXT NOT NULL DEFAULT 'bot_trigger' CHECK(
        webhook_type IN('bot_trigger')
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

-- indexes
CREATE INDEX IF NOT EXISTS idx_connector_custom_event_webhooks_pending_created_at
    ON connectors.custom_event_webhooks(organization_id, created_at, webhook_id)
    WHERE status = 'pending';

-- configure pg_partman for automatic partition management
SELECT partman.create_parent(
    p_parent_table := 'connectors.custom_event_webhooks',
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
WHERE parent_table = 'connectors.custom_event_webhooks';

-- run maintenance to create initial partitions
SELECT partman.run_maintenance('connectors.custom_event_webhooks');


-- +goose Down
DELETE FROM partman.part_config WHERE parent_table = 'connectors.custom_event_webhooks';
DROP TABLE IF EXISTS connectors.custom_event_webhooks;
DROP TABLE IF EXISTS partman.template_connectors_custom_event_webhooks;

DELETE FROM partman.part_config WHERE parent_table = 'connectors.zoho_webhooks';
DROP TABLE IF EXISTS connectors.zoho_webhooks;
DROP TABLE IF EXISTS partman.template_connectors_zoho_webhooks;

DELETE FROM partman.part_config WHERE parent_table = 'connectors.indiamart_webhooks';
DROP TABLE IF EXISTS connectors.indiamart_webhooks;
DROP TABLE IF EXISTS partman.template_connectors_indiamart_webhooks;