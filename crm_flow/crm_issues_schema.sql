-- +goose Up

-- =========================================================
-- TABLE: CRM_ISSUES_STATES
-- The pipeline stages an issue can move through (New, In Progress, ...).
-- One row = one stage.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm_issues_states(
    state_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    name VARCHAR(100) NOT NULL,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, name)
);


-- =========================================================
-- TABLE: CRM_ISSUES_FORM_FIELDS
-- Blueprint for the form inside each state (Notes, Attachments,
-- plus any custom fields the admin adds). One row = one field,
-- with its own type (short_answer, long_answer, dropdown, ...).
-- =========================================================
CREATE TABLE IF NOT EXISTS crm_issues_form_fields(
    field_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    state_id UUID NOT NULL REFERENCES crm_issues_states(state_id) ON DELETE CASCADE,
    field_key VARCHAR(50) NOT NULL,
    label VARCHAR(100) NOT NULL,
    field_type VARCHAR(20) NOT NULL CHECK (
        field_type IN (
            'short_answer',
            'long_answer',
            'number',
            'dropdown_single',
            'dropdown_multi',
            'file_upload',
            'quotation'
        )
    ),
    options JSONB,
    is_required BOOLEAN NOT NULL DEFAULT false,
    is_visible BOOLEAN NOT NULL DEFAULT true,
    sort_order INT NOT NULL DEFAULT 0,
    is_default         BOOLEAN NOT NULL DEFAULT false,
    is_delete_locked   BOOLEAN NOT NULL DEFAULT false,
    is_required_locked BOOLEAN NOT NULL DEFAULT false,
    is_visible_locked  BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (state_id, field_key)
);



-- =========================================================
-- TABLE: CRM_ISSUES
-- One row = one actual issue, always tied to exactly one lead/customer,
-- sitting in exactly one state, with one owner and one assignee.
-- title is the "Name" field on the form.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm_issues(
    issue_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    issue_number BIGINT NOT NULL,
    lead_id UUID NOT NULL REFERENCES crm_leads_customers_leads(lead_id),
    current_state_id UUID NOT NULL REFERENCES crm_issues_states(state_id),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    owner_id UUID NOT NULL REFERENCES core.agents(agent_id),
    assigned_to UUID NOT NULL REFERENCES core.agents(agent_id),
    created_by UUID REFERENCES core.agents(agent_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, issue_number)
);


-- =========================================================
-- TABLE: CRM_ISSUES_STATE_ENTRIES
-- History log. One row = one visit of an issue into a state —
-- captures the filled-in field data, who owned it and who it was
-- assigned to at that exact moment.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm_issues_state_entries(
    entry_id UUID PRIMARY KEY DEFAULT uuidv7(),
    issue_id UUID NOT NULL REFERENCES crm_issues(issue_id) ON DELETE CASCADE,
    state_id UUID NOT NULL REFERENCES crm_issues_states(state_id),
    data JSONB NOT NULL DEFAULT '{}'::jsonb,
    owner_id UUID NOT NULL REFERENCES core.agents(agent_id),
    assigned_to UUID REFERENCES core.agents(agent_id),
    filled_by UUID REFERENCES core.agents(agent_id),
    entered_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- +goose Down

DROP TABLE IF EXISTS crm_issues_state_entries;
DROP TABLE IF EXISTS crm_issues_form_fields;
DROP TABLE IF EXISTS crm_issues;
DROP TABLE IF EXISTS crm_issues_states;
