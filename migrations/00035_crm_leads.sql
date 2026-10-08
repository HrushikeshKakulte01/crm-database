-- +goose Up
-- form fields that the admin adds for leads and customers
CREATE TABLE IF NOT EXISTS crm.form_fields(
    field_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    field_key VARCHAR(50) NOT NULL,
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
    UNIQUE (organization_id, field_type, field_key)
);

-- stores leads and converts it to customers for the organization
CREATE TABLE IF NOT EXISTS crm.leads(
    lead_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    user_id UUID NOT NULL REFERENCES core.users(user_id),
    company_name VARCHAR(150),
    source TEXT,
    custom_fields JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_converted BOOLEAN NOT NULL DEFAULT false,
    converted_at TIMESTAMPTZ,
    created_by UUID REFERENCES core.agents(agent_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, user_id)
    CHECK(
        is_converted = (converted_at IS NOT NULL)
    )
);
-- +goose Down
DROP TABLE IF EXISTS crm.leads;
DROP TABLE IF EXISTS crm.form_fields;