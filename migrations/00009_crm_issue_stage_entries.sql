-- +goose Up
-- a history log: one row every time an issue enters a pipeline stage,
-- capturing the answers to that stage's custom fields
-- (crm.issue_stage_fields) at that moment. This is what makes "a form for
-- each state" possible — crm.issues only ever holds the CURRENT stage_id,
-- but this table keeps the full trail of every stage the issue has been
-- through, who filled in each one, and what was recorded.
--
-- issue_id and stage_id ARE real foreign keys: crm.issues and
-- crm.issue_stages both live in this same database. filled_by_agent_id
-- and assigned_to_agent_id are copies of the console database's
-- core.agents.agent_id — not foreign keys (see 00001_crm_schema.sql).
CREATE TABLE IF NOT EXISTS crm.issue_stage_entries(
    entry_id UUID PRIMARY KEY DEFAULT uuidv7(),
    issue_id UUID NOT NULL REFERENCES crm.issues(issue_id) ON DELETE CASCADE,
    stage_id UUID NOT NULL REFERENCES crm.issue_stages(stage_id),
    -- answers to crm.issue_stage_fields for this stage, keyed by field_key
    data JSONB NOT NULL DEFAULT '{}'::jsonb,
    -- who was responsible for the issue while it sat in this stage, if
    -- that differed from (or narrowed down) the issue's overall assignees
    assigned_to_agent_id UUID,
    filled_by_agent_id UUID,
    entered_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- an issue's full stage history, oldest first
CREATE INDEX IF NOT EXISTS idx_crm_issue_stage_entries_issue
    ON crm.issue_stage_entries(issue_id, entered_at);


-- +goose Down
DROP TABLE IF EXISTS crm.issue_stage_entries;