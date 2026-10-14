-- +goose Up
-- admin issues settings for stage and orders
CREATE TABLE IF NOT EXISTS crm.issues_states(
    state_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    name VARCHAR(100) NOT NULL,
    group_type VARCHAR(10) NOT NULL CHECK (group_type IN ('enquiry', 'order')),
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
    organization_id UUID NOT NULL,
    state_id UUID NOT NULL,
    system_key VARCHAR(20) CHECK (system_key IN ('notes', 'documents')),
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
    FOREIGN KEY (organization_id, state_id)
        REFERENCES crm.issues_states(organization_id, state_id) ON DELETE CASCADE,
    CHECK (
        field_type NOT IN ('dropdown_single', 'dropdown_multi')
        OR (options IS NOT NULL AND jsonb_typeof(options) = 'array')
    ),
    CHECK (is_default = (system_key IS NOT NULL)),
    CHECK (NOT is_visible_locked OR is_visible),
    UNIQUE (state_id, system_key)   -- one Notes and one Documents row per stage
);

-- issues from the agent's POV
CREATE TABLE IF NOT EXISTS crm.issues(      
    issue_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    lead_id UUID NOT NULL, 
    current_state_id UUID NOT NULL REFERENCES crm.issues_states(state_id),
    title VARCHAR(255) NOT NULL,
    description TEXT,      
    due_date DATE,                                         
    created_by UUID REFERENCES core.agents(agent_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, issue_id),
    UNIQUE (organization_id, issue_id, lead_id),
    FOREIGN KEY (organization_id, lead_id)
        REFERENCES crm.leads(organization_id, lead_id),
    FOREIGN KEY (organization_id, current_state_id)
        REFERENCES crm.issues_states(organization_id, state_id)
); 

-- history of the states for an issue
CREATE TABLE IF NOT EXISTS crm.issues_pipeline_progress(
    entry_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    issue_id UUID NOT NULL REFERENCES crm.issues(issue_id) ON DELETE CASCADE,
    state_id UUID NOT NULL REFERENCES crm.issues_states(state_id),
    from_state_id UUID REFERENCES crm.issues_states(state_id),   -- the state the issues came from(null for the initial state)
    transition_type VARCHAR(10) NOT NULL CHECK (transition_type IN ('initial', 'forward', 'backward')), -- the state transition means the issue going forward or backward in the pipeline
    reason TEXT,                                    -- reason for why the move happened, especially for backward moves                                              
    data JSONB NOT NULL DEFAULT '{}'::jsonb,
    moved_by UUID REFERENCES core.agents(agent_id),              -- who moved the issue into this state
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    FOREIGN KEY (organization_id, issue_id)
        REFERENCES crm.issues(organization_id, issue_id),
    FOREIGN KEY (organization_id, state_id)
        REFERENCES crm.issues_states(organization_id, state_id),
    FOREIGN KEY (organization_id, from_state_id)
        REFERENCES crm.issues_states(organization_id, state_id),
    CHECK (transition_type <> 'backward' OR NULLIF(BTRIM(reason), '') IS NOT NULL),  -- backward move needs a non-blank reason
    CHECK ((transition_type = 'initial') = (from_state_id IS NULL)),                  -- only the first entry has no from_state_id
    CHECK (from_state_id IS NULL OR from_state_id <> state_id),                         -- a move can't land in the state it left
    CHECK (jsonb_typeof(data) = 'object')                              -- accepts the data in json form {"name": "hrushikesh"}
);

-- a log for every changed assignee
CREATE TABLE IF NOT EXISTS crm.issues_assignments(
    assignment_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL,
    issue_id UUID NOT NULL,
    agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    assigned_by UUID NOT NULL REFERENCES core.agents(agent_id),
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    entry_id UUID NOT NULL,  
    unassigned_by UUID REFERENCES core.agents(agent_id),
    unassigned_at TIMESTAMPTZ,
    unassign_reason TEXT,
    FOREIGN KEY (organization_id, issue_id)
        REFERENCES crm.issues(organization_id, issue_id),
    FOREIGN KEY (organization_id, issue_id, entry_id)
        REFERENCES crm.issues_pipeline_progress(organization_id, issue_id, entry_id),
    CHECK ((unassigned_at IS NULL) = (unassigned_by IS NULL)),
    CHECK (unassigned_at IS NULL OR unassigned_at >= assigned_at)
);

-- note history for an issue 
CREATE TABLE IF NOT EXISTS crm.issues_notes(
    note_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL,
    issue_id NOT NULL,
    entry_id NOT NULL,
    body TEXT NOT NULL CHECK (NULLIF(BTRIM(body), '') IS NOT NULL),
    created_by UUID NOT NULL REFERENCES core.agents(agent_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    FOREIGN KEY (organization_id, issue_id, entry_id)
        REFERENCES crm.issues_pipeline_progress(organization_id, issue_id, entry_id)
);

CREATE TABLE IF NOT EXISTS crm.issues_documents(
    document_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id NOT NULL,
    issues_id NOT NULL,
    entry_id NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    storage_key TEXT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    uploaded_by UUID NOT NULL REFERENCES core.agents(agent_id),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (organization_id, issues_id, entry_id)
        REFERENCES crm.issues_pipeline_progress(organization_id, issue_id, entry_id)
);

-- +goose Down
DROP TABLE IF EXISTS crm.issues_documents;
DROP TABLE IF EXISTS crm.issues_notes;
DROP TABLE IF EXISTS crm.issues_assignments;
DROP TABLE IF EXISTS crm.issues_pipeline_progress;
DROP TABLE IF EXISTS crm.issues;
DROP TABLE IF EXISTS crm.issues_form_fields;
DROP TABLE IF EXISTS crm.issues_states;