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
    UNIQUE (organization_id, state_id)
);

-- the fields for each stage's form which the admin adds(eg. Notes, attachments, etc)
CREATE TABLE IF NOT EXISTS crm.issues_form_fields(      
    field_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    state_id UUID NOT NULL REFERENCES crm.issues_states(state_id) ON DELETE CASCADE,
    label VARCHAR(100) NOT NULL,
    field_type VARCHAR(20) NOT NULL CHECK(
        field_type IN(
            'short_answer',
            'long_answer',
            'date',
            'url',
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
    UNIQUE (state_id, label)
);

-- issues from the agent's POV
CREATE TABLE IF NOT EXISTS crm.issues(      
    issue_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    lead_id UUID NOT NULL,   
    current_state_id UUID NOT NULL REFERENCES crm.issues_states(state_id),
    title VARCHAR(255) NOT NULL,
    description TEXT,                                               
    owner_id UUID NOT NULL REFERENCES core.agents(agent_id),
    created_by UUID REFERENCES core.agents(agent_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, lead_id),
    UNIQUE (organization_id, issue_id),
    FOREIGN KEY (organization_id, lead_id)
    REFERENCES crm.leads(organization_id, lead_id)
); 

-- history of the states for an issue
CREATE TABLE IF NOT EXISTS crm.issues_pipeline_progress(
    entry_id UUID PRIMARY KEY DEFAULT uuidv7(),
    issue_id UUID NOT NULL REFERENCES crm.issues(issue_id) ON DELETE CASCADE,
    state_id UUID NOT NULL REFERENCES crm.issues_states(state_id),
    from_state_id UUID REFERENCES crm.issues_states(state_id),   -- NULL for the first entry
    transition_type VARCHAR(10) NOT NULL CHECK (transition_type IN ('initial', 'forward', 'backward')),  -- stored at move time, not recomputed from sort_order
    reason TEXT,                                                                                  
    data JSONB NOT NULL DEFAULT '{}'::jsonb,                     
    owner_id UUID NOT NULL REFERENCES core.agents(agent_id),
    moved_by UUID REFERENCES core.agents(agent_id),              -- who moved the issue into this state
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    CHECK (transition_type <> 'backward' OR NULLIF(BTRIM(reason), '') IS NOT NULL),  -- backward move needs a non-blank reason
    CHECK ((transition_type = 'initial') = (from_state_id IS NULL)),                  -- only the first entry has no from_state_id
    CHECK (from_state_id IS NULL OR from_state_id <> state_id)                        -- a move can't land in the state it left
);

-- a log for every changed assignee
CREATE TABLE IF NOT EXISTS crm.issues_assignments(
    assignment_id UUID PRIMARY KEY DEFAULT uuidv7(),
    issue_id UUID NOT NULL REFERENCES crm.issues(issue_id) ON DELETE CASCADE,
    agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    assigned_by UUID NOT NULL REFERENCES core.agents(agent_id),
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    entry_id UUID REFERENCES crm.issues_pipeline_progress(entry_id),  -- stage the issue was in
    unassigned_by UUID REFERENCES core.agents(agent_id),
    unassigned_at TIMESTAMPTZ,
    unassign_reason TEXT,
    CHECK ((unassigned_at IS NULL) = (unassigned_by IS NULL)),
    CHECK (unassigned_at IS NULL OR unassigned_at >= assigned_at)
);

-- +goose Down
DROP TABLE IF EXISTS crm.issues_assignments;
DROP TABLE IF EXISTS crm.issues_pipeline_progress;
DROP TABLE IF EXISTS crm.issues;
DROP TABLE IF EXISTS crm.issues_form_fields;
DROP TABLE IF EXISTS crm.issues_states;