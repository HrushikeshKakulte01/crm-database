-- +goose Up
-- admin issues settings for stage and orders
CREATE TABLE IF NOT EXISTS crm.issues_states(
    state_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    name VARCHAR(100) NOT NULL,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, name),
    UNIQUE (organization_id, sort_order)
);

-- the fields for each stage's form which the admin adds(eg. Notes, attachments, etc)
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
            'date',
            'URL'
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

-- issues from the agent's POV

-- issues should have link to lead details
-- should this table have a state_id to track the current state of the issue?
-- should there be a lead_id here to track and to identify that which lead this issues belongs to
CREATE TABLE IF NOT EXISTS crm.issues(      
    issue_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    issue_number BIGINT NOT NULL,
    user_id UUID NOT NULL REFERENCES core.users(user_id),   -- whhy do we need user_id here? we can get the user_id from the lead_id
    current_state_id UUID NOT NULL REFERENCES crm.issues_states(state_id),
    title VARCHAR(255) NOT NULL,
    description TEXT,                                               
    owner_id UUID NOT NULL REFERENCES core.agents(agent_id),
    assigned_to UUID NOT NULL REFERENCES core.agents(agent_id),
    created_by UUID REFERENCES core.agents(agent_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, issue_number),
    UNIQUE (organization_id, issue_id),
    FOREIGN KEY (organization_id, current_state_id)
        REFERENCES crm.issues_states(organization_id, state_id)
);

-- history of the issues assignee and the states they've been in
-- should there be attachment field in this table
CREATE TABLE IF NOT EXISTS crm.issues_state_entries(    -- can i rename this as pipeline/progress
    entry_id UUID PRIMARY KEY DEFAULT uuidv7(),
    issue_id UUID NOT NULL REFERENCES crm.issues(issue_id) ON DELETE CASCADE,
    state_id UUID NOT NULL REFERENCES crm.issues_states(state_id),
    from_state_id UUID REFERENCES crm.issues_states(state_id),   -- NULL for the first entry
    transition_type VARCHAR(10) NOT NULL CHECK (transition_type IN ('initial', 'forward', 'backward')),  -- stored at move time, not recomputed from sort_order
    reason TEXT,                                                        -- can i rename this as Notes                                 
    data JSONB NOT NULL DEFAULT '{}'::jsonb,                     
    owner_id UUID NOT NULL REFERENCES core.agents(agent_id),
    assigned_to UUID NOT NULL REFERENCES core.agents(agent_id),  -- assignee at the moment the state was entered
    moved_by UUID REFERENCES core.agents(agent_id),              -- who moved the issue into this state
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    CHECK (transition_type <> 'backward' OR NULLIF(BTRIM(reason), '') IS NOT NULL),  -- backward move needs a non-blank reason
    CHECK ((transition_type = 'initial') = (from_state_id IS NULL)),                  -- only the first entry has no from_state_id
    CHECK (from_state_id IS NULL OR from_state_id <> state_id)                        -- a move can't land in the state it left
);

-- a log for every changed assignee
CREATE TABLE IF NOT EXISTS crm.issues_assignments_history(
    assignment_id UUID PRIMARY KEY DEFAULT uuidv7(),
    issue_id UUID NOT NULL REFERENCES crm.issues(issue_id) ON DELETE CASCADE,
    entry_id UUID REFERENCES crm.issues_state_entries(entry_id),  -- the state visit during which this happened
    assigned_to UUID NOT NULL REFERENCES core.agents(agent_id),
    assigned_by UUID REFERENCES core.agents(agent_id),
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_crm_issues_assignments_history_issue
    ON crm.issues_assignments_history(issue_id, created_at DESC, assignment_id DESC);


-- +goose Down
DROP TABLE IF EXISTS crm.issues_assignments_history;
DROP TABLE IF EXISTS crm.issues_state_entries;
DROP TRIGGER IF EXISTS trg_crm_issues_assign_number ON crm.issues;
DROP FUNCTION IF EXISTS crm.assign_issue_number();
DROP TABLE IF EXISTS crm.issues;
DROP TABLE IF EXISTS crm.issue_number_counters;
DROP TABLE IF EXISTS crm.issues_form_fields;
DROP TABLE IF EXISTS crm.issues_states;