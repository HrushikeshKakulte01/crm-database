-- +goose Up
-- the "Issue settings" screen configures two different things, so this
-- file has two tables:
--   1. crm.issue_form_fields — the base form filled in when an issue is
--      first created, same idea as crm.form_fields but for issues.
--   2. crm.issue_stage_fields — an ADDITIONAL form specific to one
--      pipeline stage (e.g. a "Closed" stage might require a resolution
--      note that "New" doesn't ask for). This is what the Admin Settings
--      summary "4 states · 5 fields" refers to.
--
-- organization_id is a copy of the console database's
-- core.organizations.organization_id — not a foreign key (see
-- 00001_crm_schema.sql). stage_id IS a real foreign key: crm.issue_stages
-- lives in this same database.
CREATE TABLE IF NOT EXISTS crm.issue_form_fields(
    field_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL,
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

-- per-stage extra fields — answers to these are captured each time an
-- issue enters that stage (see crm.issue_stage_entries,
-- 00009_crm_issue_stage_entries.sql), not stored on crm.issues itself,
-- since the same issue can pass through (and re-enter) several stages
-- over its lifetime and each pass can have its own answers.
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


-- +goose Down
DROP TABLE IF EXISTS crm.issue_stage_fields;
DROP TABLE IF EXISTS crm.issue_form_fields;