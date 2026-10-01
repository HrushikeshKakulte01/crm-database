-- +goose Up
-- the CRM lives in the SAME database as the console, under its own
-- "crm" schema, so every table below can use real foreign keys into the
-- console's core.* tables.
--
-- this file exists ONLY so this migration folder can run on its own —
-- e.g. a fresh developer/CI database that has never run the console
-- project's own migrations. Every statement here is IF NOT EXISTS, so
-- against the real, shared console database (where these tables already
-- exist in full) this file does ABSOLUTELY NOTHING: Postgres sees the
-- name already exists and skips it, columns and all.
--
-- these are deliberately MINIMAL stand-ins — just enough columns to
-- satisfy the foreign keys the crm schema actually uses (organizations,
-- agents, users, plus countries/states for the lead's address, and the
-- citext type for case-insensitive email). The real, authoritative
-- definitions of all of this live in the console project's own
-- migrations, not here. Never ALTER, extend, or add columns to core.*
-- or extensions.* from this project.
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA extensions;

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

CREATE TABLE IF NOT EXISTS core.countries(
    country_id INTEGER PRIMARY KEY,
    country_name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS core.states(
    state_id INTEGER PRIMARY KEY,
    country_id INTEGER NOT NULL REFERENCES core.countries(country_id),
    state_name TEXT NOT NULL
);


-- +goose Down
-- deliberately empty. On the real shared console database, these are
-- the console's actual tables (this file did nothing to create them),
-- so dropping them here would destroy real console data. On a
-- throwaway dev database where this file DID create them, roll back by
-- dropping the whole database rather than relying on this file to undo
-- itself — there is no safe way to tell the two cases apart from here.