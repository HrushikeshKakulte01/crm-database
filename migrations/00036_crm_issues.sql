-- +goose Up
-- =========================================================
-- TABLE: ISSUES_STATES
-- The pipeline stages an issue can move through (New, In Progress, ...).
-- One row = one stage.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm.issues_states(       -- admin issues settings for stage and orders
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
    field_type VARCHAR(20) NOT NULL CHECK(
        field_type IN(
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
    is_default BOOLEAN NOT NULL DEFAULT false,
    is_delete_locked BOOLEAN NOT NULL DEFAULT false,
    is_required_locked BOOLEAN NOT NULL DEFAULT false,
    is_visible_locked BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (state_id, field_key)
);


-- =========================================================
-- TABLE: ISSUES
-- One row = one actual issue, always tied to exactly one lead/customer,
-- sitting in exactly one state, with one owner and one assignee.
-- title is the "Name" field on the form.
-- current_state_id and assigned_to are the "right now" copies — the
-- history lives in issues_state_entries / issues_assignments,
-- and every change must update both in the same transaction.
-- owner_id = accountable for the issue (the department head), rarely changes.
-- assigned_to = the agent working on it right now, changes often.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm.issues(      -- issues from the lead/customer POV
    issue_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    issue_number BIGINT NOT NULL,
    lead_id UUID NOT NULL REFERENCES crm.leads_customers(lead_id),
    current_state_id UUID NOT NULL REFERENCES crm.issues_states(state_id),
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
-- TABLE: ISSUES_STATE_ENTRIES
-- History log. One row = one visit of an issue into a state —
-- captures the filled-in field data, who owned it and who it was
-- assigned to at that exact moment.
-- Append-only: moving an issue (forward OR backward) inserts a new row;
-- old rows are never deleted, and only the latest row's data is edited.
-- The latest row (ORDER BY created_at DESC, entry_id DESC) is the
-- issue's current entry. Do NOT add UNIQUE (issue_id, state_id): an
-- issue can visit the same state many times.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm.issues_state_entries(    -- history of the issues and the states they've been in
    entry_id UUID PRIMARY KEY DEFAULT uuidv7(),
    issue_id UUID NOT NULL REFERENCES crm.issues(issue_id) ON DELETE CASCADE,
    state_id UUID NOT NULL REFERENCES crm.issues_states(state_id),
    from_state_id UUID REFERENCES crm.issues_states(state_id),   -- NULL for the first entry
    transition_type VARCHAR(10) NOT NULL CHECK (transition_type IN ('initial', 'forward', 'backward')),  -- stored at move time, not recomputed from sort_order
    reason TEXT,                                                 -- required when the move is backward
    data JSONB NOT NULL DEFAULT '{}'::jsonb,                     -- answers keyed by issues_form_fields.field_key
    owner_id UUID NOT NULL REFERENCES core.agents(agent_id),
    assigned_to UUID NOT NULL REFERENCES core.agents(agent_id),  -- assignee at the moment the state was entered
    moved_by UUID REFERENCES core.agents(agent_id),              -- who moved the issue into this state
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    CHECK (transition_type <> 'backward' OR NULLIF(BTRIM(reason), '') IS NOT NULL),  -- backward move needs a non-blank reason
    CHECK ((transition_type = 'initial') = (from_state_id IS NULL)),                  -- only the first entry has no from_state_id
    CHECK (from_state_id IS NULL OR from_state_id <> state_id)                        -- a move can't land in the state it left
);

-- an issue's full timeline, newest first
CREATE INDEX IF NOT EXISTS idx_crm_issues_state_entries_issue
    ON crm.issues_state_entries(issue_id, created_at DESC, entry_id DESC);


-- =========================================================
-- TABLE: ISSUES_ASSIGNMENTS
-- Assignee history. One row = one change of assignee, including the
-- ones that happen as part of a state move and the ones that happen
-- without any state change (reassign inside the same state).
-- Append-only. issues.assigned_to holds the current value.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm.issues_assignees(      -- history of who the issue was assigned to
    assignment_id UUID PRIMARY KEY DEFAULT uuidv7(),
    issue_id UUID NOT NULL REFERENCES crm.issues(issue_id) ON DELETE CASCADE,
    entry_id UUID REFERENCES crm.issues_state_entries(entry_id),  -- the state visit during which this happened
    assigned_to UUID NOT NULL REFERENCES core.agents(agent_id),
    assigned_by UUID REFERENCES core.agents(agent_id),
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- an issue's assignee history, newest first
CREATE INDEX IF NOT EXISTS idx_crm_issues_assignments_issue
    ON crm.issues_assignments(issue_id, created_at DESC, assignment_id DESC);


-- +goose Down
DROP TABLE IF EXISTS crm.issues_assignments;
DROP TABLE IF EXISTS crm.issues_state_entries;
DROP TRIGGER IF EXISTS trg_crm_issues_assign_number ON crm.issues;
DROP FUNCTION IF EXISTS crm.assign_issue_number();
DROP TABLE IF EXISTS crm.issues;
DROP TABLE IF EXISTS crm.issue_number_counters;
DROP TABLE IF EXISTS crm.issues_form_fields;
DROP TABLE IF EXISTS crm.issues_states;