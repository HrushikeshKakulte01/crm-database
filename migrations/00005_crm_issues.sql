-- +goose Up
-- one running counter per organization, so issue numbers read as
-- ISS-1001, ISS-1002, ... starting fresh for each Bitamin client instead
-- of sharing one global counter across every organization.
--
-- organization_id is a copy of the console database's
-- core.organizations.organization_id — not a foreign key (see
-- 00001_crm_schema.sql).
CREATE TABLE IF NOT EXISTS crm.issue_number_counters(
    organization_id UUID PRIMARY KEY,
    next_number BIGINT NOT NULL DEFAULT 1001
);

-- an issue is the single record that carries a lead/customer through the
-- whole pipeline — from first contact through negotiation and, once it
-- reaches an is_order_stage stage, fulfillment. There is no separate
-- "order" table: the Orders screen is this same table filtered by stage.
--
-- organization_id is a copy of the console database's
-- core.organizations.organization_id — not a foreign key (see
-- 00001_crm_schema.sql). contact_id and stage_id ARE real foreign keys:
-- crm.contact_details and crm.issue_stages both live in this same
-- database. owner_agent_id is a copy of core.agents.agent_id, also not a
-- foreign key — it is the single agent responsible for this issue, kept
-- separate from crm.issue_assignees below, which can hold several agents
-- at once (the Issues list shows both an Owner column and an Assignees
-- column).
CREATE TABLE IF NOT EXISTS crm.issues(
    issue_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL,
    issue_number BIGINT NOT NULL,
    contact_id UUID NOT NULL REFERENCES crm.contact_details(contact_id),
    stage_id UUID NOT NULL REFERENCES crm.issue_stages(stage_id),
    owner_agent_id UUID,
    title TEXT NOT NULL,
    description TEXT,
    -- answers to this organization's custom fields on the base Issue
    -- form (crm.issue_form_fields) — separate from the per-stage fields
    -- captured in crm.issue_stage_entries as the issue moves through
    -- the pipeline.
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

-- an issue can have more than one agent assigned (the design shows
-- "Amit Kapoor, Jaya Shah" on a single card), so this is many-to-many
-- rather than a single assigned_to column. issue_id IS a real foreign
-- key (crm.issues lives here); agent_id is a copy of the console
-- database's core.agents.agent_id, not a foreign key.
CREATE TABLE IF NOT EXISTS crm.issue_assignees(
    issue_id UUID NOT NULL REFERENCES crm.issues(issue_id),
    agent_id UUID NOT NULL,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (issue_id, agent_id)
);
-- an agent's assigned issues, for "my issues" views
CREATE INDEX IF NOT EXISTS idx_crm_issue_assignees_agent
    ON crm.issue_assignees(agent_id, issue_id);


-- +goose Down
DROP TABLE IF EXISTS crm.issue_assignees;
DROP TRIGGER IF EXISTS trg_crm_issues_assign_number ON crm.issues;
DROP FUNCTION IF EXISTS crm.assign_issue_number();
DROP TABLE IF EXISTS crm.issues;
DROP TABLE IF EXISTS crm.issue_number_counters;