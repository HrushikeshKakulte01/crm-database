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
    UNIQUE (organization_id, name),
    CHECK (sort_order >= 0)
);
-- ordered active stages per organization, for rendering the pipeline
CREATE INDEX IF NOT EXISTS idx_crm_issues_states_org_sort_order
    ON crm_issues_states(organization_id, sort_order)
    WHERE is_active = true;


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
    is_default         BOOLEAN NOT NULL DEFAULT false,
    is_delete_locked   BOOLEAN NOT NULL DEFAULT false,
    is_required_locked BOOLEAN NOT NULL DEFAULT false,
    is_visible_locked  BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (state_id, field_key),
    CHECK (sort_order >= 0),
    -- a dropdown without choices is unusable
    CHECK (
        field_type NOT IN('dropdown_single', 'dropdown_multi')
        OR options IS NOT NULL
    )
);
-- a state's active fields in display order, for rendering the form
CREATE INDEX IF NOT EXISTS idx_crm_issues_form_fields_state_sort_order
    ON crm_issues_form_fields(state_id, sort_order)
    WHERE is_active = true;



-- =========================================================
-- TABLE: CRM_ISSUES
-- One row = one actual issue, always tied to exactly one lead/customer,
-- sitting in exactly one state, with one owner and one assignee.
-- title is the "Name" field on the form.
-- current_state_id and assigned_to are the "right now" copies — the
-- history lives in crm_issues_state_entries / crm_issues_assignments,
-- and every change must update both in the same transaction.
-- owner_id = accountable for the issue, rarely changes.
-- assigned_to = the agent working on it right now, changes often.
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
    UNIQUE (organization_id, issue_number),
    CHECK (issue_number > 0)
);
-- active issues by organization and state, for the pipeline columns
CREATE INDEX IF NOT EXISTS idx_crm_issues_org_state_created_issue
    ON crm_issues(organization_id, current_state_id, created_at DESC, issue_id DESC)
    WHERE is_active = true;
-- issues by lead/customer, for the lead detail page
CREATE INDEX IF NOT EXISTS idx_crm_issues_lead_created_issue
    ON crm_issues(lead_id, created_at DESC, issue_id DESC);
-- active issues by current assignee, for "my issues" views
CREATE INDEX IF NOT EXISTS idx_crm_issues_assigned_to_active
    ON crm_issues(assigned_to)
    WHERE is_active = true;
-- active issues by owner
CREATE INDEX IF NOT EXISTS idx_crm_issues_owner_active
    ON crm_issues(owner_id)
    WHERE is_active = true;


-- =========================================================
-- TABLE: CRM_ISSUES_STATE_ENTRIES
-- History log. One row = one visit of an issue into a state —
-- captures the filled-in field data, who owned it and who it was
-- assigned to at that exact moment.
-- Append-only: moving an issue (forward OR backward) inserts a new row;
-- old rows are never deleted, and only the latest row's data is edited.
-- The latest row (ORDER BY created_at DESC, entry_id DESC) is the
-- issue's current entry. Do NOT add UNIQUE (issue_id, state_id): an
-- issue can visit the same state many times.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm_issues_state_entries(
    entry_id UUID PRIMARY KEY DEFAULT uuidv7(),
    issue_id UUID NOT NULL REFERENCES crm_issues(issue_id) ON DELETE CASCADE,
    state_id UUID NOT NULL REFERENCES crm_issues_states(state_id),
    from_state_id UUID REFERENCES crm_issues_states(state_id),   -- NULL for the first entry
    transition_type VARCHAR(10) NOT NULL CHECK (transition_type IN ('initial', 'forward', 'backward')),  -- stored at move time, not recomputed from sort_order
    reason TEXT,                                                 -- required when the move is backward
    data JSONB NOT NULL DEFAULT '{}'::jsonb,                     -- answers keyed by crm_issues_form_fields.field_key
    owner_id UUID NOT NULL REFERENCES core.agents(agent_id),
    assigned_to UUID NOT NULL REFERENCES core.agents(agent_id),  -- assignee at the moment the state was entered
    -- filled_by UUID REFERENCES core.agents(agent_id),
    moved_by UUID REFERENCES core.agents(agent_id),              -- who moved the issue into this state
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    CHECK (transition_type <> 'backward' OR NULLIF(BTRIM(reason), '') IS NOT NULL),  -- backward move needs a non-blank reason
    CHECK ((transition_type = 'initial') = (from_state_id IS NULL)),                  -- only the first entry has no from_state_id
    CHECK (from_state_id IS NULL OR from_state_id <> state_id),                       -- a move can't land in the state it left
);

-- an issue's full timeline, newest first
CREATE INDEX IF NOT EXISTS idx_crm_issues_state_entries_issue
    ON crm_issues_state_entries(issue_id, created_at DESC, entry_id DESC);


-- =========================================================
-- TABLE: CRM_ISSUES_ASSIGNMENTS
-- Assignee history. One row = one change of assignee, including the
-- ones that happen as part of a state move and the ones that happen
-- without any state change (reassign inside the same state).
-- Append-only. crm_issues.assigned_to holds the current value.
-- =========================================================
CREATE TABLE IF NOT EXISTS crm_issues_assignments(
    assignment_id UUID PRIMARY KEY DEFAULT uuidv7(),
    issue_id UUID NOT NULL REFERENCES crm_issues(issue_id) ON DELETE CASCADE,
    entry_id UUID REFERENCES crm_issues_state_entries(entry_id),  -- the state visit during which this happened
    assigned_to UUID NOT NULL REFERENCES core.agents(agent_id),
    assigned_by UUID REFERENCES core.agents(agent_id),
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- an issue's assignee history, newest first
CREATE INDEX IF NOT EXISTS idx_crm_issues_assignments_issue
    ON crm_issues_assignments(issue_id, created_at DESC, assignment_id DESC);


-- +goose Down

DROP TABLE IF EXISTS crm_issues_assignments;
DROP TABLE IF EXISTS crm_issues_state_entries;
DROP TABLE IF EXISTS crm_issues_form_fields;
DROP TABLE IF EXISTS crm_issues;
DROP TABLE IF EXISTS crm_issues_states;
