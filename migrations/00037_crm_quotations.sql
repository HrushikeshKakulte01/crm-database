-- +goose Up
-- a single price quoted against one issue, with a status tracking whether
-- it's been sent to and accepted by the customer. one issue can have more
-- than one quotation over time (e.g. a revised price).
CREATE TABLE IF NOT EXISTS crm.quotations(
    quotation_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    issue_id UUID NOT NULL REFERENCES crm.issues(issue_id),         -- there should be lead_id
    amount NUMERIC(14, 2) NOT NULL CHECK(
        amount >= 0
    ),
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

-- +goose Down
DROP TABLE IF EXISTS crm.quotations;