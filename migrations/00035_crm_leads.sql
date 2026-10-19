-- +goose Up
-- the built-in fields every form starts with
CREATE TYPE crm.form_field_system_key AS ENUM (
    'name',
    'company',
    'owner',
    'phone',
    'source',
    'email',
    'state',
    'city'
);
-- the types of fields an admin can choose from
CREATE TYPE crm.form_field_type AS ENUM (
    'short_answer',
    'long_answer',
    'date',
    'url',
    'phone',
    'email',
    'number',
    'dropdown_single',
    'dropdown_multi'
);

-- form fields that the admin adds for leads and customers
CREATE TABLE IF NOT EXISTS crm.form_fields(
    field_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    -- system_key stores the by default fields
    system_key crm.form_field_system_key,
    -- field_type shows the types of fields that a admin can choose from
    field_type crm.form_field_type NOT NULL,
    -- label is the name for the field type selected
    label VARCHAR(100) NOT NULL,
    -- option stores the list of the options for the dropdown field
    options JSONB,
    is_required BOOLEAN NOT NULL DEFAULT false,
    is_visible BOOLEAN NOT NULL DEFAULT true,
    sort_order INT NOT NULL DEFAULT 0,
    is_default BOOLEAN NOT NULL DEFAULT false,
    is_delete_locked BOOLEAN NOT NULL DEFAULT false,
    is_required_locked BOOLEAN NOT NULL DEFAULT false,
    is_visible_locked BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, form_type, label),
    UNIQUE (organization_id, form_type, system_key),
    CHECK (is_default = (system_key IS NOT NULL)),
    CHECK (system_key NOT IN ('name', 'owner', 'phone', 'source')
       OR (is_required AND is_visible AND is_required_locked AND is_visible_locked))
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
    -- holds the data for the new custom fields created by the admin
    custom_fields JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(custom_fields) = 'object'),
    is_converted BOOLEAN NOT NULL DEFAULT false CHECK (is_converted = (converted_at IS NOT NULL)),
    converted_at TIMESTAMPTZ,
    converted_by UUID REFERENCES core.agents(agent_id) CHECK (converted_by IS NULL OR is_converted),
    created_by UUID REFERENCES core.agents(agent_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, user_id),
    UNIQUE (organization_id, lead_id),
    CHECK (is_converted = (converted_at IS NOT NULL))
);

-- +goose Down
DROP TABLE IF EXISTS crm.leads;
DROP TABLE IF EXISTS crm.form_fields;
DROP TYPE IF EXISTS crm.form_field_type;
DROP TYPE IF EXISTS crm.form_field_system_key;