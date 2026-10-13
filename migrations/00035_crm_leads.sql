-- +goose Up
-- form fields that the admin adds for leads and customers
CREATE TABLE IF NOT EXISTS crm.form_fields(
    field_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    label VARCHAR(100) NOT NULL,
    field_type VARCHAR(20) NOT NULL CHECK(
        field_type IN(
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
    is_delete_locked BOOLEAN NOT NULL DEFAULT false,
    is_required_locked BOOLEAN NOT NULL DEFAULT false,
    is_visible_locked BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, label)
);

-- stores leads and converts it to customers for the organization
CREATE TABLE IF NOT EXISTS crm.leads(
    lead_id UUID PRIMARY KEY DEFAULT uuidv7(),
    user_id UUID NOT NULL REFERENCES core.users(user_id),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    owner_id UUID NOT NULL REFERENCES core.agents(agent_id),
    company_name VARCHAR(150),
    source TEXT NOT NULL,
    state_id INTEGER REFERENCES core.states(state_id),
    city VARCHAR(100),
    custom_fields JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(custom_fields) = 'object'),
    is_converted BOOLEAN NOT NULL DEFAULT false CHECK (is_converted = (converted_at IS NOT NULL)),
    converted_at TIMESTAMPTZ,
    converted_by UUID REFERENCES core.agents(agent_id) CHECK (converted_by IS NULL OR is_converted),
    created_by UUID REFERENCES core.agents(agent_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, user_id),
    UNIQUE (organization_id, lead_id)
);
-- +goose Down
DROP TABLE IF EXISTS crm.leads;
DROP TABLE IF EXISTS crm.form_fields;