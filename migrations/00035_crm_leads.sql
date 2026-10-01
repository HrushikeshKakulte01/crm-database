-- +goose Up

-- =========================================================
-- TABLE: FORM_FIELDS
-- Blueprint for configurable forms (Lead, Customer, ...).
-- One row = one field on one form_type's form.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm.form_fields(
    field_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),  
    field_key VARCHAR(50) NOT NULL,
    label VARCHAR(100) NOT NULL,
    field_type VARCHAR(20) NOT NULL CHECK (
        field_type IN (
            'short_answer',
            'long_answer', 
            'number',
            'dropdown_single',
            'dropdown_multi',
            'phone',
            'email'
        )
    ),
    options JSONB,
    is_required BOOLEAN NOT NULL DEFAULT false,
    is_visible BOOLEAN NOT NULL DEFAULT true,
    sort_order INT NOT NULL DEFAULT 0,      
    is_delete_locked   BOOLEAN NOT NULL DEFAULT false,
    is_required_locked BOOLEAN NOT NULL DEFAULT false,
    is_visible_locked  BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, type, field_key),
);

CREATE TABLE IF NOT EXISTS crm.leads(
    lead_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),

    name VARCHAR(150) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    company_name VARCHAR(150),

    -- not a CHECK-constrained enum: Source is an admin-configurable
    -- dropdown (crm.form_fields, field_key = 'source')
    source TEXT,

    custom_fields JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_by UUID REFERENCES core.agents(agent_id),

    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,

    UNIQUE (organization_id, phone),

    CONSTRAINT chk_leads_type CHECK (
        type IN ('new', 'existing')
    )
);

-- =========================================================
-- TABLE: CUSTOMERS
-- A lead "converts" into a customer — converted_from_lead_id keeps
-- that link so you can trace a customer back to the lead they
-- started as (nullable, since a customer could in theory be added
-- directly without ever being a lead).
-- =========================================================
CREATE TABLE IF NOT EXISTS crm.customers(
    customer_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    converted_from_lead_id UUID REFERENCES crm.leads(lead_id),  -- When a lead is converted to a customer, this field stores the lead_id of the original lead. This allows for tracking the conversion history and maintaining a relationship between leads and customers.

    name VARCHAR(150) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    company_name VARCHAR(150),
    source TEXT,

    custom_fields JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_by UUID REFERENCES core.agents(agent_id),

    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,

    UNIQUE (organization_id, phone),

    CONSTRAINT chk_customers_type CHECK (
        type IN ('new', 'existing')
    )
);

-- +goose Down

DROP TABLE IF EXISTS crm.leads_customers;
DROP TABLE IF EXISTS crm.form_fields;