-- +goose Up
-- a single price quoted against one issue, with a status tracking whether
-- it's been sent to and accepted by the customer. one issue can have more
-- than one quotation over time (e.g. a revised price).
CREATE TABLE IF NOT EXISTS crm_quotations(
    quotation_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    issue_id UUID NOT NULL REFERENCES crm.issues(issue_id),
    amount NUMERIC(14, 2) NOT NULL CHECK(
        amount >= 0
    ),
    -- currency VARCHAR(3) NOT NULL DEFAULT 'INR' CHECK(
    --     currency IN(
    --         'INR',
    --         'USD',
    --         'EUR'
    --     )
    -- ),
    status VARCHAR(10) NOT NULL DEFAULT 'draft' CHECK(
        status IN(
            'draft',
            'sent',
            'accepted',
            'rejected'
        )
    ),
    created_by_agent_id UUID REFERENCES core.agents(agent_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
-- quotations by issue, most recent first
CREATE INDEX IF NOT EXISTS idx_crm_quotations_issue
    ON crm.quotations(issue_id, created_at DESC);


-- +goose Down
DROP TABLE IF EXISTS crm_quotations;