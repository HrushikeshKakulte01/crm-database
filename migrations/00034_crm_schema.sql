-- +goose Up
-- all CRM tables live under this schema, inside the same database as
-- the console. Every table below that references an organization,
-- agent, or user uses a real foreign key into core.organizations /
-- core.agents / core.users (see 00033_core_prerequisites.sql).
CREATE SCHEMA IF NOT EXISTS crm;


-- +goose Down
DROP SCHEMA IF EXISTS crm;