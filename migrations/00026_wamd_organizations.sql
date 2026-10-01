-- +goose Up
-- organization logs
CREATE TABLE IF NOT EXISTS wamd.organization_logs(
    organization_log_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    agent_id UUID REFERENCES core.agents(agent_id),
    event_type VARCHAR(50) NOT NULL CHECK(
        event_type IN(
            'agent-logged-in',
            'agent-logged-out',
            'agent-device-qr-code-generated',
            'agent-device-qr-code-paired',
            'agent-device-registered',
            'agent-device-connected',
            'agent-device-disconnected',
            'agent-device-logged-out',
            'agent-device-client-connection-failure',
            'agent-device-temporary-banned',
            'credit-added',
            'credit-deducted'
        )
    ),
    event_log TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- backs ListActivityLogs (org-wide activity feed, newest first)
CREATE INDEX IF NOT EXISTS idx_organization_logs_org_created_at
    ON wamd.organization_logs(organization_id, created_at DESC);
-- backs ListAgentActivityLogs (single agent's activity feed, newest first)
CREATE INDEX IF NOT EXISTS idx_organization_logs_agent_created_at
    ON wamd.organization_logs(agent_id, created_at DESC)
    WHERE agent_id IS NOT NULL;

-- organization authentication tokens for third-party integrations
CREATE TABLE IF NOT EXISTS wamd.organization_auth_tokens(
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    token_type VARCHAR(50) NOT NULL CHECK(
        token_type IN(
            'tally',
            'busy'
        )
    ),
    token_hash BYTEA NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ,
    PRIMARY KEY (organization_id, token_type)
);
-- create unique index for active token type for an organization
CREATE UNIQUE INDEX IF NOT EXISTS idx_wamd_organization_auth_tokens_active
    ON wamd.organization_auth_tokens(organization_id, token_type)
    WHERE is_active = true;

-- enable row level security for the auth tokens table
-- row level security can be forced on the table owner via the 'FORCE' keyword
-- create a policy to only allow access to the auth tokens table to the organization
-- see: https://www.postgresql.org/docs/current/sql-createpolicy.html
-- see: https://www.postgresql.org/docs/current/ddl-rowsecurity.html
-- 'EXISTS' with a subquery determines if the row exists in the table
-- see: https://www.postgresql.org/docs/current/functions-subquery.html
-- 'myapp.current_organization_id' is set using:
-- BEGIN;
-- SET LOCAL myapp.current_organization_id = <ORGANIZATION_ID>;
-- -- query here
-- COMMIT;
CREATE POLICY wamd_organization_auth_token_row_level_security_policy
ON wamd.organization_auth_tokens
USING (
    organization_id = current_setting('myapp.current_organization_id')::UUID
);
-- enable row level security for the auth tokens table
ALTER TABLE wamd.organization_auth_tokens ENABLE ROW LEVEL SECURITY;

-- +goose StatementBegin
-- create a credit transaction for an organization
-- a_agent_id is appended (not inserted positionally) with a default so
-- existing 6-arg manual invocations (see README.md's "Credits (operations)"
-- example) keep working unchanged; pass it when a top-up should be
-- attributed to the agent/admin who triggered it instead of logging NULL
CREATE OR REPLACE FUNCTION wamd.function_organization_add_credits(
    a_organization_id UUID,
    a_transaction_credits INTEGER,
    a_transaction_amount NUMERIC(10, 2),
    a_transaction_currency VARCHAR(3),
    a_transaction_description TEXT,
    a_created_by_user VARCHAR(255),
    a_agent_id UUID DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_new_balance INTEGER;
    v_log_message TEXT;
BEGIN
    -- update organization credits
    UPDATE core.organization_credits
    SET
        credits_whatsapp_multidevice = credits_whatsapp_multidevice + a_transaction_credits,
        updated_at = NOW()
    WHERE organization_id = a_organization_id
    RETURNING credits_whatsapp_multidevice INTO v_new_balance;

    -- insert organization credit transaction
    INSERT INTO core.organization_credit_transactions(
        organization_id, platform, transaction_type, credits, amount, currency, description, created_by
    )
    VALUES (
        a_organization_id, 'whatsapp-multidevice', 'credit', a_transaction_credits,
        a_transaction_amount, a_transaction_currency, a_transaction_description, a_created_by_user
    );

    -- set log message
    v_log_message := 'credit of ' || a_transaction_credits
        || ' worth ' || a_transaction_amount || ' ' || a_transaction_currency
        || ' added to organization';

    -- update organization logs
    INSERT INTO wamd.organization_logs(organization_id, agent_id, event_type, event_log)
    VALUES (a_organization_id, a_agent_id, 'credit-added', v_log_message);

    -- return new balance
    RETURN v_new_balance;
END;
$$ LANGUAGE plpgsql;
-- +goose StatementEnd


-- +goose Down
DROP FUNCTION IF EXISTS wamd.function_organization_add_credits;
DROP POLICY IF EXISTS wamd_organization_auth_token_row_level_security_policy
    ON wamd.organization_auth_tokens;
DROP TABLE IF EXISTS wamd.organization_auth_tokens;
DROP TABLE IF EXISTS wamd.organization_logs;