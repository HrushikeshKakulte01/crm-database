-- +goose Up
-- the CRM now lives in the SAME database as the console, under its own
-- "crm" schema, so every table below can use real foreign keys into the
-- console's core.organizations/core.agents/core.users.
--
-- this file exists ONLY so this migration folder can run on its own —
-- e.g. a fresh developer/CI database that has never run the console
-- project's own migrations. Every statement here is IF NOT EXISTS, so
-- against the real, shared console database (where these tables
-- already exist in full, created by the console's own 00008/00009/00010
-- migrations) this file does ABSOLUTELY NOTHING: Postgres sees the
-- table name already exists and skips it, columns and all.
--
-- these are deliberately MINIMAL stand-ins (just the id, organization
-- link, and a display name) — not a full copy of the console's real
-- columns. The console's core.organizations alone also references
-- core.partners, core.countries, core.states, and core.frontend_themes,
-- which this project does not own and should not try to reproduce. If
-- the CRM ever needs more console columns than this, pull them from the
-- console's API/data rather than widening this stub.
--
-- the real, authoritative definitions of these tables live in the
-- console project's own migrations, not here. Never ALTER, extend, or
-- add columns to core.* from this project.
CREATE SCHEMA IF NOT EXISTS core;

CREATE TABLE IF NOT EXISTS core.organizations(
    organization_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS core.agents(
    agent_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    agent_name VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS core.users(
    user_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    user_name TEXT
);


-- +goose Down
-- deliberately empty. On the real shared console database, these are
-- the console's actual tables (this file did nothing to create them),
-- so dropping them here would destroy real console data. On a
-- throwaway dev database where this file DID create them, roll back by
-- dropping the whole database rather than relying on this file to undo
-- itself — there is no safe way to tell the two cases apart from here.