-- +goose Up

CREATE TABLE IF NOT EXISTS crm.quotations(
    quotation_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    lead_id UUID REFERENCES crm.leads(lead_id),
    issue_id UUID NOT NULL REFERENCES crm.issues(issue_id),
    customer_id UUID REFERENCES crm.customers(customer_id),
    total_amount NUMERIC(14, 2) NOT NULL CHECK(
        total_amount >= 0
    ),
    status VARCHAR(10) NOT NULL DEFAULT 'draft' CHECK(
        status IN(
            'draft',
            'sent',
            'accepted',
            'rejected'
        )
    ),
    created_by UUID REFERENCES core.agents(agent_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id),
    CHECK (num_nonnulls(lead_id, customer_id) = 1) 
);

CREATE TABLE IF NOT EXISTS crm.quotation_items(
    item_id UUID PRIMARY KEY DEFAULT uuidv7(),
    quotation_id UUID NOT NULL REFERENCES crm.quotations(quotation_id) ON DELETE CASCADE,
    item_name VARCHAR(150) NOT NULL,
    price NUMERIC(14, 2) NOT NULL CHECK(
        price >= 0
    ),
    quantity INT NOT NULL DEFAULT 1 CHECK(
        quantity > 0
    )
);

-- +goose Down
DROP TABLE IF EXISTS crm.quotation_items;
DROP TABLE IF EXISTS crm.quotations;