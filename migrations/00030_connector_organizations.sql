-- +goose Up
-- create table for organization connectors api tokens
CREATE TABLE IF NOT EXISTS connectors.organization_connectors_api_tokens (
    connector_token_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    connector_type core.connector NOT NULL,
    logo_url TEXT,
    token_data BYTEA NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, connector_type)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_connector_org_connectors_api_tokens_active_unique
    ON connectors.organization_connectors_api_tokens (organization_id, connector_type)
    WHERE is_active = true;

-- RLS for organization connectors api tokens
-- create row level security policy for organization connectors api tokens
CREATE POLICY connectors_organization_connectors_api_tokens_row_level_security_policy
ON connectors.organization_connectors_api_tokens
FOR ALL
USING (
    organization_id = current_setting('myapp.current_organization_id')::UUID
    AND is_active = true
);
-- enable row level security for organization connectors api tokens
ALTER TABLE connectors.organization_connectors_api_tokens ENABLE ROW LEVEL SECURITY;


-- +goose Down
ALTER TABLE connectors.organization_connectors_api_tokens DISABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS connectors_organization_connectors_api_tokens_row_level_security_policy ON connectors.organization_connectors_api_tokens;
DROP TABLE IF EXISTS connectors.organization_connectors_api_tokens;