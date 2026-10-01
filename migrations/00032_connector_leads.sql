-- +goose Up
-- create indiamart queries table
CREATE TABLE IF NOT EXISTS connectors.indiamart_leads (
    surrogate_indiamart_lead_id UUID PRIMARY KEY DEFAULT uuidv7(),
    user_id UUID REFERENCES core.users(user_id),
    lead_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (surrogate_indiamart_lead_id, user_id)
);
-- index for active leads by user
CREATE INDEX IF NOT EXISTS idx_connector_indiamart_leads_user_active
    ON connectors.indiamart_leads (surrogate_indiamart_lead_id, user_id)
    WHERE is_active = true;


-- +goose Down
DROP TABLE IF EXISTS connectors.indiamart_leads;