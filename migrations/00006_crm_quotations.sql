-- +goose Up
-- a single price quoted against one issue, with a status tracking whether
-- it's been sent to and accepted by the customer. one issue can have more
-- than one quotation over time (e.g. a revised price).
--
-- organization_id is a copy of the console database's
-- core.organizations.organization_id, and created_by_agent_id a copy of
-- core.agents.agent_id — neither is a foreign key (see
-- 00001_crm_schema.sql). issue_id IS a real foreign key: crm.issues
-- lives in this same database.
CREATE TABLE IF NOT EXISTS crm.quotations(
    quotation_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL,
    issue_id UUID NOT NULL REFERENCES crm.issues(issue_id),
    amount NUMERIC(14, 2) NOT NULL CHECK(
        amount >= 0
    ),
    currency VARCHAR(3) NOT NULL DEFAULT 'INR' CHECK(
        currency IN(
            'INR',
            'USD',
            'EUR'
        )
    ),
    status VARCHAR(10) NOT NULL DEFAULT 'draft' CHECK(
        status IN(
            'draft',
            'sent',
            'accepted',
            'rejected'
        )
    ),
    created_by_agent_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
-- quotations by issue, most recent first
CREATE INDEX IF NOT EXISTS idx_crm_quotations_issue
    ON crm.quotations(issue_id, created_at DESC);


-- +goose Down
DROP TABLE IF EXISTS crm.quotations;