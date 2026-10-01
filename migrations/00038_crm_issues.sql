-- +goose Up

-- =========================================================
-- TABLE: ISSUE_STAGES
-- =========================================================
-- unlike the console's core.tickets.ticket_status (a fixed CHECK list),
-- an organization's admin can freely add, rename, reorder, and delete
-- issue stages (Admin Settings -> Pipeline Stages), so the stage list is
-- data, not a CHECK constraint. is_order_stage marks which stages also
-- surface on the Orders screen — an "order" is just an issue sitting in
-- one of those stages, not a separate record (the Orders list reuses the
-- same ISS-#### identifiers as Issues).
CREATE TABLE IF NOT EXISTS crm.issue_stages(
    stage_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    stage_name TEXT NOT NULL,
    stage_position INTEGER NOT NULL,
    is_order_stage BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, stage_name)
);
-- ordered stage list per organization, for rendering the Kanban columns
-- and the Admin Settings reorderable list
CREATE INDEX IF NOT EXISTS idx_crm_issue_stages_org_position
    ON crm.issue_stages(organization_id, stage_position)
    WHERE is_active = true;


-- =========================================================
-- TABLE: ISSUE_FORM_FIELDS
-- =========================================================
-- the base form filled in when an issue is first created — same idea as
-- crm.form_fields (00036) but for issues. Per-stage extra fields are a
-- separate table below (issue_stage_fields), since "Issue settings"
-- configures both a base Issue form AND a form for each pipeline stage.
CREATE TABLE IF NOT EXISTS crm.issue_form_fields(
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
            'dropdown_multi'
        )
    ),
    options JSONB,
    is_required BOOLEAN NOT NULL DEFAULT false,
    is_visible BOOLEAN NOT NULL DEFAULT true,
    sort_order INT NOT NULL DEFAULT 0,
    is_delete_locked BOOLEAN NOT NULL DEFAULT false,
    is_required_locked BOOLEAN NOT NULL DEFAULT false,
    is_visible_locked BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, field_key)
);
CREATE INDEX IF NOT EXISTS idx_crm_issue_form_fields_org_order
    ON crm.issue_form_fields(organization_id, sort_order);


-- =========================================================
-- TABLE: ISSUE_STAGE_FIELDS
-- =========================================================
-- per-stage extra fields — e.g. a "Closed" stage might require a
-- resolution note that "New" doesn't ask for. Answers to these are
-- captured each time an issue enters that stage (see
-- issue_stage_entries below), not stored on crm.issues itself, since the
-- same issue can pass through (and re-enter) several stages over its
-- lifetime and each pass can have its own answers.
CREATE TABLE IF NOT EXISTS crm.issue_stage_fields(
    field_id UUID PRIMARY KEY DEFAULT uuidv7(),
    stage_id UUID NOT NULL REFERENCES crm.issue_stages(stage_id) ON DELETE CASCADE,
    field_key VARCHAR(50) NOT NULL,
    label VARCHAR(100) NOT NULL,
    field_type VARCHAR(20) NOT NULL CHECK(
        field_type IN(
            'short_answer',
            'long_answer',
            'number',
            'dropdown_single',
            'dropdown_multi'
        )
    ),
    options JSONB,
    is_required BOOLEAN NOT NULL DEFAULT false,
    is_visible BOOLEAN NOT NULL DEFAULT true,
    sort_order INT NOT NULL DEFAULT 0,
    -- true for the small set of fields every stage starts with out of
    -- the box (as opposed to ones an admin added to this specific stage)
    is_default BOOLEAN NOT NULL DEFAULT false,
    is_delete_locked BOOLEAN NOT NULL DEFAULT false,
    is_required_locked BOOLEAN NOT NULL DEFAULT false,
    is_visible_locked BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (stage_id, field_key)
);
CREATE INDEX IF NOT EXISTS idx_crm_issue_stage_fields_stage_order
    ON crm.issue_stage_fields(stage_id, sort_order);


-- =========================================================
-- TABLE: ISSUE_NUMBER_COUNTERS
-- =========================================================
-- one running counter per organization, so issue numbers read as
-- ISS-1001, ISS-1002, ... starting fresh for each Bitamin client instead
-- of sharing one global counter across every organization.
CREATE TABLE IF NOT EXISTS crm.issue_number_counters(
    organization_id UUID PRIMARY KEY REFERENCES core.organizations(organization_id),
    next_number BIGINT NOT NULL DEFAULT 1001
);


-- =========================================================
-- TABLE: ISSUES
-- =========================================================
-- the single record that carries a lead/customer through the whole
-- pipeline — from first contact through negotiation and, once it
-- reaches an is_order_stage stage, fulfillment. There is no separate
-- "order" table: the Orders screen is this same table filtered by
-- stage. owner_agent_id is the single agent responsible for this issue,
-- kept separate from issue_assignees below, which can hold several
-- agents at once (the Issues list shows both an Owner column and an
-- Assignees column).
CREATE TABLE IF NOT EXISTS crm.issues(
    issue_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    issue_number BIGINT NOT NULL,
    contact_id UUID NOT NULL REFERENCES crm.contacts(contact_id),
    stage_id UUID NOT NULL REFERENCES crm.issue_stages(stage_id),
    owner_agent_id UUID REFERENCES core.agents(agent_id),
    title TEXT NOT NULL,
    description TEXT,
    -- answers to this organization's base Issue form (issue_form_fields
    -- above) — separate from the per-stage fields captured in
    -- issue_stage_entries as the issue moves through the pipeline.
    custom_fields JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ,
    UNIQUE (organization_id, issue_number)
);
-- issues by organization and stage, for the Kanban board columns
CREATE INDEX IF NOT EXISTS idx_crm_issues_org_stage
    ON crm.issues(organization_id, stage_id, created_at DESC);
-- issues by contact, so a lead/customer's detail page can list their issues
CREATE INDEX IF NOT EXISTS idx_crm_issues_contact
    ON crm.issues(contact_id, created_at DESC);
-- an agent's owned issues, for "my issues" views
CREATE INDEX IF NOT EXISTS idx_crm_issues_owner_agent
    ON crm.issues(owner_agent_id);

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
-- TABLE: ISSUE_ASSIGNEES
-- =========================================================
-- an issue can have more than one agent assigned (the design shows
-- "Amit Kapoor, Jaya Shah" on a single card), so this is many-to-many
-- rather than a single column.
CREATE TABLE IF NOT EXISTS crm.issue_assignees(
    issue_id UUID NOT NULL REFERENCES crm.issues(issue_id),
    agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (issue_id, agent_id)
);
-- an agent's assigned issues, for "my issues" views
CREATE INDEX IF NOT EXISTS idx_crm_issue_assignees_agent
    ON crm.issue_assignees(agent_id, issue_id);


-- =========================================================
-- TABLE: ISSUE_STAGE_ENTRIES
-- =========================================================
-- a history log: one row every time an issue enters a pipeline stage,
-- capturing the answers to that stage's custom fields (issue_stage_fields
-- above) at that moment. This is what makes "a form for each state"
-- possible — crm.issues only ever holds the CURRENT stage_id, but this
-- table keeps the full trail of every stage the issue has been through,
-- who filled in each one, and what was recorded.
CREATE TABLE IF NOT EXISTS crm.issue_stage_entries(
    entry_id UUID PRIMARY KEY DEFAULT uuidv7(),
    issue_id UUID NOT NULL REFERENCES crm.issues(issue_id) ON DELETE CASCADE,
    stage_id UUID NOT NULL REFERENCES crm.issue_stages(stage_id),
    -- answers to issue_stage_fields for this stage, keyed by field_key
    data JSONB NOT NULL DEFAULT '{}'::jsonb,
    -- who was responsible for the issue while it sat in this stage, if
    -- that differed from (or narrowed down) the issue's overall assignees
    assigned_to_agent_id UUID REFERENCES core.agents(agent_id),
    filled_by_agent_id UUID REFERENCES core.agents(agent_id),
    entered_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- an issue's full stage history, oldest first
CREATE INDEX IF NOT EXISTS idx_crm_issue_stage_entries_issue
    ON crm.issue_stage_entries(issue_id, entered_at);


-- +goose Down
DROP TABLE IF EXISTS crm.issue_stage_entries;
DROP TABLE IF EXISTS crm.issue_assignees;
DROP TRIGGER IF EXISTS trg_crm_issues_assign_number ON crm.issues;
DROP FUNCTION IF EXISTS crm.assign_issue_number();
DROP TABLE IF EXISTS crm.issues;
DROP TABLE IF EXISTS crm.issue_number_counters;
DROP TABLE IF EXISTS crm.issue_stage_fields;
DROP TABLE IF EXISTS crm.issue_form_fields;
DROP TABLE IF EXISTS crm.issue_stages;