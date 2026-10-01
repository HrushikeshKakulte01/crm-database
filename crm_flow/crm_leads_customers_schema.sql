-- +goose Up

-- =========================================================
-- TABLE: FORM_FIELDS
-- Blueprint for the configurable Lead / Customer form.
-- One row = one field on an organization's form.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm_leads_customers_form_fields(
    field_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    field_key VARCHAR(50) NOT NULL,
    label VARCHAR(100) NOT NULL,
    field_type VARCHAR(20) NOT NULL CHECK (field_type IN ('short_answer', 'long_answer', 'number', 'dropdown_single', 'dropdown_multi', 'file_upload', 'quotation')),
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
    UNIQUE (organization_id, field_key)
);

-- =========================================================
-- TABLE: LEADS
-- A lead and a customer are the same row — status moves from
-- 'lead' to 'customer' as the relationship progresses. The Leads
-- screen and Customers screen are two filtered views of this table.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm_leads_customers_leads(
    lead_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),

    name VARCHAR(150) NOT NULL,
    company_name VARCHAR(150),
    phone VARCHAR(20) NOT NULL,

    -- lead -> customer progress
    owner_agent_id UUID REFERENCES core.agents(agent_id),
    status VARCHAR(10) NOT NULL CHECK (status IN ('lead', 'customer')),

    -- not a CHECK-constrained enum: Source is an admin-configurable
    -- dropdown (crm_leads_customers_form_fields, field_key = 'source') — this column
    -- just stores whichever value was picked
    source TEXT,

    -- answers to every other field on the form (email, city, state, and any
    -- field an admin adds via "+ Add field"), keyed by field_key. Only the
    -- always-there fields (name, company_name, phone, source) are real columns.
    custom_fields JSONB NOT NULL DEFAULT '{}'::jsonb,

    -- assigned_to UUID REFERENCES core.agents(agent_id),
    -- created_by UUID REFERENCES core.agents(agent_id),

    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,

    UNIQUE (organization_id, phone)
);


-- +goose Down

DROP TABLE IF EXISTS crm_leads_customers_leads;
DROP TABLE IF EXISTS crm_leads_customers_form_fields;
