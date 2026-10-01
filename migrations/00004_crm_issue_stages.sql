-- +goose Up
-- unlike the console's core.tickets.ticket_status (a fixed CHECK list),
-- an organization's admin can freely add, rename, reorder, and delete
-- issue stages (Admin Settings -> Pipeline Stages), so the stage list is
-- data, not a CHECK constraint. is_order_stage marks which stages also
-- surface on the Orders screen — an "order" is just an issue sitting in
-- one of those stages, not a separate record (the Orders list reuses the
-- same ISS-#### identifiers as Issues).
--
-- organization_id is a copy of the console database's
-- core.organizations.organization_id — not a foreign key (see
-- 00001_crm_schema.sql).
CREATE TABLE IF NOT EXISTS crm.issue_stages(
    stage_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL,
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


-- +goose Down
DROP TABLE IF EXISTS crm.issue_stages;