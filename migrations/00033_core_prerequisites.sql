-- +goose Up

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS core;

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

-- [console: 00006_core_references.sql]
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

-- agent team assignments for the organization
CREATE TABLE IF NOT EXISTS core.agent_teams(
    agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    team_id UUID NOT NULL REFERENCES core.organization_teams(team_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    PRIMARY KEY (agent_id, team_id)
);

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

-- +goose Down