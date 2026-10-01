-- +goose Up
-- all CRM tables live under this schema, inside the same database as
-- the console. Because it's the same database, every table below that
-- references an organization, agent, or user uses a real foreign key
-- into core.organizations / core.agents / core.users (see
-- 00033_core_prerequisites.sql) — unlike an earlier draft of this
-- project, which assumed a separate CRM database and had to fall back
-- to plain, unenforced UUID columns for those references.
CREATE SCHEMA IF NOT EXISTS crm;


-- +goose Down
DROP SCHEMA IF EXISTS crm;