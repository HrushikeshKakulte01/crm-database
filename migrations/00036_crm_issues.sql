-- +goose Up
CREATE TYPE crm.issues_form_field_system_key AS ENUM (
    'notes',
    'documents',
    'name',
    'description',
    'stage',
    'assignees',
    'due_date',
    'lead'
);

CREATE TYPE crm.issues_field_type AS ENUM (
    'short_answer',
    'long_answer',
    'date',
    'url',
    'number',
    'dropdown_single',
    'dropdown_multi',
    'file_upload',
    'quotation',
    'stage',
    'assignees',
    'lead'
);

-- admin issues settings for stage and orders
CREATE TABLE IF NOT EXISTS crm.issues_states(
    state_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL,
    group_type VARCHAR(10) NOT NULL CHECK (group_type IN ('enquiry', 'order')),
    name VARCHAR(100) NOT NULL,
    sort_order INT NOT NULL DEFAULT 0,
    is_default BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, state_id),
    CHECK (NOT is_default OR is_active)
);

-- the fields for each stage's form which the admin adds(eg. Notes, documents, etc)
CREATE TABLE IF NOT EXISTS crm.issues_form_fields(
    field_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL  REFERENCES core.organizations(organization_id),
    -- NULL = the Create issue form, otherwise the form of that stage
    state_id UUID,
    system_key crm.issues_form_field_system_key,
    -- list of field types a field can have
    field_type crm.issues_field_type NOT NULL,
    label VARCHAR(100) NOT NULL,
    -- choices for a dropdown
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
    -- a stage must exist in the same organization
    FOREIGN KEY (organization_id, state_id)
        REFERENCES crm.issues_states(organization_id, state_id) ON DELETE CASCADE,
    -- a dropdown must carry a list of choices
    CHECK (
        field_type NOT IN ('dropdown_single', 'dropdown_multi')
        OR (options IS NOT NULL AND jsonb_typeof(options) = 'array')
    ),
    -- built-in fields are exactly the default ones
    CHECK (is_default = (system_key IS NOT NULL)),
    -- notes and documents belong to a stage form, the other keys to the Create issue form
    CHECK (system_key IS NULL OR ((system_key IN ('notes', 'documents')) = (state_id IS NOT NULL))),
    -- a field that can't be hidden must be visible
    CHECK (NOT is_visible_locked OR is_visible)
);

-- issues from the agent's POV(issues, create issue, issue details)
CREATE TABLE IF NOT EXISTS crm.issues(
    issue_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL,
    lead_id UUID NOT NULL,
    -- the state where the issue is currently present
    current_state_id UUID NOT NULL,
    -- issues title
    title VARCHAR(255) NOT NULL,
    -- issues description
    description TEXT,
    -- due date of the issue
    due_date DATE,
    -- answers for the fields the admin added to the Create issue form, keyed by field_id
    custom_fields JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(custom_fields) = 'object'),
    -- the agent who created the issue
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
    organization_id UUID NOT NULL,
    issue_id UUID NOT NULL,
    state_id UUID NOT NULL REFERENCES crm.issues_states(state_id),
    -- the state the issues came from(null for the initial state)
    from_state_id UUID REFERENCES crm.issues_states(state_id),
    -- tells how the issue arrived in a state
    transition_type VARCHAR(10) NOT NULL CHECK (transition_type IN (
            'initial',
            'forward',
            'backward'
    )),
    -- reason why the move happened and reason is compulsary for a backward move(eg. from negotiation to new    )
    reason TEXT,
    -- stores the answer for the custom field
    data JSONB NOT NULL DEFAULT '{}'::jsonb,
    -- who moved the issue into this state
    moved_by UUID REFERENCES core.agents(agent_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
        UNIQUE (organization_id, issue_id, entry_id),
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
    -- the state visit while someone was assigned
    entry_id UUID NOT NULL,
    -- an agent can be assigned to an issue only once
    UNIQUE (issue_id, agent_id),
    FOREIGN KEY (organization_id, issue_id)
        REFERENCES crm.issues(organization_id, issue_id),
    FOREIGN KEY (organization_id, issue_id, entry_id)
        REFERENCES crm.issues_pipeline_progress(organization_id, issue_id, entry_id)
);

-- note history for an issue
CREATE TABLE IF NOT EXISTS crm.issues_notes(
    note_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL,
    issue_id UUID NOT NULL,
    entry_id UUID NOT NULL,
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
    organization_id UUID NOT NULL,
    issue_id UUID NOT NULL,
    entry_id UUID NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    storage_key TEXT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    uploaded_by UUID NOT NULL REFERENCES core.agents(agent_id),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (organization_id, issue_id, entry_id)
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
DROP TYPE IF EXISTS crm.issues_field_type;
DROP TYPE IF EXISTS crm.issues_form_field_system_key;