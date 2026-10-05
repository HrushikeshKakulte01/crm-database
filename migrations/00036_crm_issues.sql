-- +goose Up

-- =========================================================
-- TABLE: ISSUES_STATES
-- The pipeline stages an issue can move through (New, In Progress, ...).
-- One row = one stage.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm.issues_states(
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
-- TABLE: ISSUES_FORM_FIELDS
-- Blueprint for the form inside each state (Notes, Attachments,
-- plus any custom fields the admin adds). One row = one field.
-- There is no separate, state-independent "base" issue form — an
-- issue's starting state (e.g. "New") IS the creation form, since
-- every issue is created directly into some state.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm.issues_form_fields(
    field_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    state_id UUID NOT NULL REFERENCES crm.issues_states(state_id) ON DELETE CASCADE,
    field_key VARCHAR(50) NOT NULL,
    label VARCHAR(100) NOT NULL,
    field_type VARCHAR(20) NOT NULL,
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
    UNIQUE (state_id, field_key),
    CONSTRAINT chk_crm_issues_form_fields_type CHECK (
        field_type IN (
            'short_answer',
            'long_answer',
            'number',
            'dropdown_single',
            'dropdown_multi',
            'file_upload',
            'quotation'
        )
    )
);



-- =========================================================
-- TABLE: ISSUES
-- One row = one actual issue, always tied to exactly one lead/customer,
-- sitting in exactly one state, with one owner (the department head
-- responsible for assigning it out) and many assignees (see
-- issues_assignees). title is the "Name" field on the form.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm.issues(
    issue_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    issue_number BIGINT NOT NULL,
    lead_id UUID NOT NULL REFERENCES crm.leads_customers(lead_id),
    current_state_id UUID NOT NULL REFERENCES crm.issues_states(state_id),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    -- the department head responsible for this issue, always required —
    -- they're the one who assigns it out to agents (see issues_assignees)
    owner_id UUID NOT NULL REFERENCES core.agents(agent_id),    -- need to create a role for the owner in prerequisite.
    created_by UUID REFERENCES core.agents(agent_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, issue_number)
);

-- assigns the next issue_number for an organization and stamps it on
-- the new row, so callers never have to compute it themselves
CREATE OR REPLACE FUNCTION crm.assign_issue_number() RETURNS TRIGGER AS $$
DECLARE
    assigned_number BIGINT;
BEGIN
    INSERT INTO crm.issue_number_counters (organization_id, next_number)
        VALUES (NEW.organization_id, 1001)
        ON CONFLICT (organization_id) DO NOTHING;

    UPDATE crm.issue_number_counters
        SET next_number = next_number + 1
        WHERE organization_id = NEW.organization_id
        RETURNING next_number - 1 INTO assigned_number;

    NEW.issue_number := assigned_number;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_crm_issues_assign_number
    BEFORE INSERT ON crm.issues
    FOR EACH ROW
    EXECUTE FUNCTION crm.assign_issue_number();


-- =========================================================
-- TABLE: ISSUES_ASSIGNEES
-- The "Assignees" field — an issue can have many agents, assigned
-- out by the owner (department head) above.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm.issues_assignees(                                -- is linking of the assignee and the issuse tab needed ?
    issue_id UUID NOT NULL REFERENCES crm.issues(issue_id) ON DELETE CASCADE,
    agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (issue_id, agent_id)
);


-- =========================================================
-- TABLE: ISSUES_STATE_ENTRIES
-- History log. One row = one visit of an issue into a state —
-- captures the filled-in field data and who it was assigned to
-- at that exact moment.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm.issues_state_entries(
    entry_id UUID PRIMARY KEY DEFAULT uuidv7(),
    issue_id UUID NOT NULL REFERENCES crm.issues(issue_id) ON DELETE CASCADE,
    state_id UUID NOT NULL REFERENCES crm.issues_states(state_id),
    data JSONB NOT NULL DEFAULT '{}'::jsonb,
    assigned_to UUID REFERENCES core.agents(agent_id),
    filled_by UUID REFERENCES core.agents(agent_id),
    entered_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- +goose Down

DROP TABLE IF EXISTS crm.issues_state_entries;
DROP TABLE IF EXISTS crm.issues_assignees;
DROP TRIGGER IF EXISTS trg_crm_issues_assign_number ON crm.issues;
DROP FUNCTION IF EXISTS crm.assign_issue_number();
DROP TABLE IF EXISTS crm.issues;
DROP TABLE IF EXISTS crm.issue_number_counters;
DROP TABLE IF EXISTS crm.issues_form_fields;
DROP TABLE IF EXISTS crm.issues_states;