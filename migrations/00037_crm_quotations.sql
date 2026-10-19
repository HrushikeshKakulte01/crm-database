-- +goose Up
-- statuses of the quotation
CREATE TYPE crm.quotation_status AS ENUM (
    'new',
    'sent_internal',
    'approved_internal',
    'declined_internal',
    'sent_client',
    'approved_client',
    'declined_client'
);
-- stores quotations
CREATE TABLE IF NOT EXISTS crm.quotations(
    quotation_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    lead_id UUID NOT NULL,
    issue_id UUID NOT NULL,
    status crm.quotation_status NOT NULL DEFAULT 'new',
    -- subtotal means the total price before any tax, discount and any other charges
    subtotal NUMERIC(14, 2) NOT NULL CHECK(
        subtotal >= 0
    ),
    -- total means the total amount of the quotation after taxes, discount and other charges
    total NUMERIC(14, 2) NOT NULL CHECK(
        total >= 0
    ),
    notes TEXT,
    -- the old quotation that this quotation replaces (a changed quote is a new quotation)
    replace_quotation_id UUID,
    created_by UUID REFERENCES core.agents(agent_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, quotation_id),
    FOREIGN KEY (organization_id, lead_id)
        REFERENCES crm.leads(organization_id, lead_id),
    FOREIGN KEY (organization_id, issue_id, lead_id)
        REFERENCES crm.issues(organization_id, issue_id, lead_id),
    FOREIGN KEY (organization_id, replace_quotation_id)
        REFERENCES crm.quotations(organization_id, quotation_id),
    CHECK (replace_quotation_id IS NULL OR replace_quotation_id <> quotation_id)
);

-- fields to create a new quotation
CREATE TABLE IF NOT EXISTS crm.quotation_items(
    item_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL,
    quotation_id UUID NOT NULL,
    item_name VARCHAR(150) NOT NULL,
    price NUMERIC(14, 2) NOT NULL CHECK(
        price >= 0
    ),
    quantity INT NOT NULL DEFAULT 1 CHECK(
        quantity > 0
    ),
    amount NUMERIC(18, 2) GENERATED ALWAYS AS (price * quantity) STORED,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (organization_id, quotation_id)
        REFERENCES crm.quotations(organization_id, quotation_id)
);

-- This table adds up the tax, discount and other charges.
CREATE TABLE IF NOT EXISTS crm.quotation_adjustments(
    adjustment_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL,
    quotation_id UUID NOT NULL,
    additional_charges VARCHAR(20) NOT NULL CHECK(
        additional_charges IN (
            'tax',
            'discount',
            'other_charges'
        )
    ),
    label VARCHAR(100) NOT NULL,
    value_type VARCHAR(100) NOT NULL CHECK(
        value_type IN(
            'fixed',    -- fixed is a fixed amount(not related to percentage eg. discount on $100 is $10 not 10%)
            'percentage'
        )
    ),
    value NUMERIC(14, 2) NOT NULL CHECK(
        value >= 0
    ),
    amount NUMERIC(18, 2) NOT NULL CHECK(
        amount >= 0
    ),
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (organization_id, quotation_id)
        REFERENCES crm.quotations(organization_id, quotation_id),
    CHECK (value_type <> 'percentage' OR value <= 100),
    CHECK (value_type <> 'fixed' OR amount = value)
);

-- keeping a log of the quotation sent through the states(eg. sent_internal, sent_client, approved_internal, approved_client)
CREATE TABLE IF NOT EXISTS crm.quotation_status_history(
    history_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL,
    quotation_id UUID NOT NULL,
    from_status crm.quotation_status,
    to_status crm.quotation_status NOT NULL,
    changed_by UUID NOT NULL REFERENCES core.agents(agent_id),
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (organization_id, quotation_id)
        REFERENCES crm.quotations(organization_id, quotation_id),
    CHECK (from_status IS NULL OR from_status <> to_status)
);

-- +goose Down
DROP TABLE IF EXISTS crm.quotation_status_history;
DROP TABLE IF EXISTS crm.quotation_adjustments;
DROP TABLE IF EXISTS crm.quotation_items;
DROP TABLE IF EXISTS crm.quotations;
DROP TYPE IF EXISTS crm.quotation_status;