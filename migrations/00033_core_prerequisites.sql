-- +goose Up
-- the CRM lives in the SAME database as the console, under its own "crm"
-- schema, so CRM tables can use real foreign keys into the console's core.*
-- tables.
--
-- this file exists ONLY so this migration folder can run on its own — e.g. a
-- fresh developer/CI database that has never run the console project's own
-- migrations. It holds EXACT copies of the console tables the CRM needs (plus
-- the tables those depend on), taken from the console migrations named in the
-- comment above each table.
--
-- every statement is idempotent. Against the real, shared console database
-- (where all of this already exists) this file does NOTHING: tables and
-- indexes are IF NOT EXISTS, and the enum is guarded below because
-- CREATE TYPE has no IF NOT EXISTS.
--
-- what is deliberately NOT copied:
--   * seed rows (countries, states, themes) — insert what a dev database
--     needs yourself; the real database already has them
--   * core.agent_oauth_associations — points at auth.users, which would pull
--     in the whole auth schema
--   * tickets, bots, whatsapp/facebook/wamd/instagram/connectors tables — the
--     CRM does not reference them
--
-- the console owns these tables. Never ALTER, extend, or add columns to
-- core.* or extensions.* from this project. If the console changes one of
-- these tables, update the copy here to match.
--
-- the table defaults below call uuidv7(), which is built into PostgreSQL 18+.
-- On an older dev database, create a uuidv7() function first.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS core;
-- case insensitive text type (emails)   [console: 00003_extensions.sql]
CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA extensions;

-- +goose StatementBegin
-- agent role enum   [console: 00004_types.sql]
DO $$
BEGIN
    CREATE TYPE core.agent_role AS ENUM(
        'admin',
        'support',
        'coordinator'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END
$$;
-- +goose StatementEnd

-- ---------------------------------------------------------
-- [console: 00006_core_references.sql]
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.countries(
    country_id INTEGER PRIMARY KEY,
    country_name TEXT NOT NULL
);

-- geographical states of a country
CREATE TABLE IF NOT EXISTS core.states(
    state_id INTEGER PRIMARY KEY,
    country_id INTEGER NOT NULL REFERENCES core.countries(country_id),
    state_name TEXT NOT NULL
);

-- frontend theme colors for the organization
CREATE TABLE IF NOT EXISTS core.frontend_themes(
    theme_id UUID PRIMARY KEY DEFAULT uuidv7(),
    theme_name TEXT NOT NULL UNIQUE,
    theme_object JSONB NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- ---------------------------------------------------------
-- [console: 00007_core_partners.sql]
-- ---------------------------------------------------------
-- partner table
CREATE TABLE IF NOT EXISTS core.partners(
    partner_id UUID PRIMARY KEY DEFAULT uuidv7(),
    country_id INTEGER NOT NULL REFERENCES core.countries(country_id),
    state_id INTEGER NOT NULL REFERENCES core.states(state_id),
    phone VARCHAR(20) NOT NULL UNIQUE,
    email extensions.citext NOT NULL UNIQUE,
    partner_name TEXT NOT NULL,
    city TEXT NOT NULL,
    address TEXT NOT NULL,
    logo_url TEXT NOT NULL UNIQUE,
    domain TEXT UNIQUE, -- optional; NULL permitted if not present
    theme_id UUID NOT NULL REFERENCES core.frontend_themes(theme_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- ---------------------------------------------------------
-- [console: 00008_core_organizations.sql]
-- ---------------------------------------------------------
-- organization table
CREATE TABLE IF NOT EXISTS core.organizations(
    organization_id UUID PRIMARY KEY DEFAULT uuidv7(),
    partner_id UUID NOT NULL REFERENCES core.partners(partner_id),
    country_id INTEGER NOT NULL REFERENCES core.countries(country_id),
    state_id INTEGER NOT NULL REFERENCES core.states(state_id),
    theme_id UUID NOT NULL REFERENCES core.frontend_themes(theme_id),
    phone VARCHAR(20) NOT NULL UNIQUE,
    email extensions.citext NOT NULL UNIQUE,
    organization_name TEXT NOT NULL,
    city TEXT NOT NULL,
    address TEXT NOT NULL,
    logo_url TEXT,
    domain TEXT UNIQUE,
    is_whitelabel BOOLEAN NOT NULL DEFAULT false, -- refer to partner_assignments below
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- teams inside organizations
CREATE TABLE IF NOT EXISTS core.organization_teams(
    team_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    team TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, team)
);

-- ---------------------------------------------------------
-- [console: 00009_core_agents.sql]
-- ---------------------------------------------------------
-- agents (employees) table
CREATE TABLE IF NOT EXISTS core.agents(
    agent_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    agent_role core.agent_role NOT NULL,
    agent_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    email extensions.citext NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, phone),
    UNIQUE (organization_id, email)
);

-- active agents by organization
CREATE INDEX IF NOT EXISTS idx_agents_active_org_agent
    ON core.agents(organization_id, agent_id)
    WHERE is_active = true;

-- agent team assignments for the organization
CREATE TABLE IF NOT EXISTS core.agent_teams(
    agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    team_id UUID NOT NULL REFERENCES core.organization_teams(team_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    PRIMARY KEY (agent_id, team_id)
);

-- active team memberships by team
CREATE INDEX IF NOT EXISTS idx_agent_teams_active_team_agent
    ON core.agent_teams(team_id, agent_id)
    WHERE is_active = true;

-- ---------------------------------------------------------
-- [console: 00010_core_users.sql]
-- ---------------------------------------------------------
-- users are the customers of organizations
-- "endusers"
CREATE TABLE IF NOT EXISTS core.users(
    user_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    user_name TEXT,
    phone VARCHAR(20),
    email extensions.citext,
    is_employee BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- unique active users by organization and phone
CREATE UNIQUE INDEX IF NOT EXISTS idx_core_users_org_phone_active
    ON core.users(organization_id, phone)
    WHERE is_active = true;

-- lookup users by phone number
CREATE INDEX IF NOT EXISTS idx_users_phone
    ON core.users(phone);


-- +goose Down
-- deliberately empty. On the real shared console database these are the
-- console's actual tables (this file did nothing to create them), so dropping
-- them here would destroy real console data. On a throwaway dev database where
-- this file DID create them, roll back by dropping the whole database rather
-- than relying on this file to undo itself — there is no safe way to tell the
-- two cases apart from here.