-- +goose Up

-- =========================================================
-- TABLE: FORM_FIELDS
-- Blueprint for configurable forms (Lead, Customer, ...).
-- One row = one field on one form_type's form.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm.form_fields(
    field_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    type VARCHAR(20) NOT NULL,     -- which form this field belongs to: 'lead' or 'customer'
    field_key VARCHAR(50) NOT NULL,
    label VARCHAR(100) NOT NULL,
    field_type VARCHAR(20) NOT NULL,
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
    CONSTRAINT chk_form_fields_type CHECK (
        type IN ('lead', 'customer')
    ),
    CONSTRAINT chk_form_fields_field_type CHECK (
        field_type IN (
            'short_answer',
            'long_answer',
            'number',
            'dropdown_single',
            'dropdown_multi',
            'phone',
            'email'
        )
    )
);

-- =========================================================
-- TABLE: LEADS_CUSTOMERS
-- A lead and a customer are the same row — status moves from
-- 'lead' to 'customer' as the relationship progresses. The Leads
-- screen and Customers screen are two filtered views of this table.
--
-- company_name is a free-text field directly on the lead (there is
-- no separate crm.companies table) — the "All Companies" filter is a
-- DISTINCT query over this column per organization, not a lookup
-- join. Note this means two leads at the same business only group
-- together under "All Companies" if company_name is spelled
-- identically — there's no dedup/autocomplete enforced at the
-- database level the way a separate companies table would give you.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm.leads_customers(
    lead_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),

    name VARCHAR(150) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    email extensions.citext,
    company_name VARCHAR(150),

    -- lead -> customer progress
    status VARCHAR(10) NOT NULL DEFAULT 'lead',

    -- "new" vs "existing/repeat" contact, picked on the Add Lead form —
    -- separate from status (which tracks lead->customer progress) and
    -- from source (which tracks the channel the lead came in on)
    type VARCHAR(10) NOT NULL DEFAULT 'new',

    -- not a CHECK-constrained enum: Source is an admin-configurable
    -- dropdown (crm.form_fields, field_key = 'source') — this column
    -- just stores whichever value was picked
    source TEXT,
    city TEXT,
    -- country is derivable via core.states.country_id
    state_id INTEGER REFERENCES core.states(state_id),

    -- answers to any admin-added custom fields. Built-in fields
    -- (name, phone, email, company_name, source, city, state_id) are
    -- never stored here — only extra fields an admin added via "+ Add field"
    custom_fields JSONB NOT NULL DEFAULT '{}'::jsonb,

    assigned_to UUID REFERENCES core.agents(agent_id),
    created_by UUID REFERENCES core.agents(agent_id),

    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,

    UNIQUE (organization_id, phone),

    CONSTRAINT chk_leads_status CHECK (
        status IN ('lead', 'customer')
    ),
    CONSTRAINT chk_leads_type CHECK (
        type IN ('new', 'existing')
    )
);
-- leads/customers by organization and company, for the "All Companies" filter
CREATE INDEX IF NOT EXISTS idx_crm_leads_customers_org_company
    ON crm.leads_customers(organization_id, company_name)
    WHERE is_active = true;


-- +goose Down

DROP TABLE IF EXISTS crm.leads_customers;
DROP TABLE IF EXISTS crm.form_fields;