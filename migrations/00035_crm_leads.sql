-- +goose Up

-- =========================================================
-- TABLE: FORM_FIELDS
-- Blueprint for configurable forms (Lead, Customer, ...).
-- One row = one field on one form_type's form.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm_leads_customers_form_fields(
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
-- TABLE: LEADS
-- A lead and a customer are the same row — status moves from
-- 'lead' to 'customer' as the relationship progresses. The Leads
-- screen and Customers screen are two filtered views of this table.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm_leads_customers_leads(
    lead_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),

    name VARCHAR(150) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    email extensions.citext,

    -- lead -> customer progress
    status VARCHAR(10) NOT NULL DEFAULT 'lead',

    -- "new" vs "existing/repeat" contact, picked on the Add Lead form —
    -- separate from status (which tracks lead->customer progress) and
    -- from source (which tracks the channel the lead came in on)
    type VARCHAR(10) NOT NULL DEFAULT 'new',

    -- not a CHECK-constrained enum: Source is an admin-configurable
    -- dropdown (crm_leads_customers_form_fields, field_key = 'source') — this column
    -- just stores whichever value was picked
    source TEXT,

    city TEXT,
    -- country is derivable via core.states.country_id
    state_id INTEGER REFERENCES core.states(state_id),

    -- answers to any admin-added custom fields. Built-in fields
    -- (name, phone, email, source, city, state_id) are never stored here —
    -- only extra fields an admin added via "+ Add field"
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


-- +goose Down

DROP TABLE IF EXISTS crm_leads_customers_leads;
DROP TABLE IF EXISTS crm_leads_customers_form_fields;