-- +goose Up
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

-- agent invitation
CREATE TABLE IF NOT EXISTS core.agent_invitations(
    invitation_id UUID PRIMARY KEY DEFAULT uuidv4(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    agent_role core.agent_role NOT NULL,
    agent_name TEXT NOT NULL,
    phone VARCHAR(20) NOT NULL,
    email extensions.citext NOT NULL,
    teams UUID[] NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    UNIQUE (organization_id, phone),
    UNIQUE (organization_id, email)
);

-- agent runtime store and online status
CREATE TABLE IF NOT EXISTS core.agent_store(
    agent_id UUID PRIMARY KEY REFERENCES core.agents(agent_id),
    online_status BOOLEAN NOT NULL DEFAULT false,
    store JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- index for agent store
CREATE INDEX IF NOT EXISTS idx_agent_store_agent_id
    ON core.agent_store(agent_id)
    WHERE online_status = true;

-- agent oauth associations
-- this association is created for the oauth providers
-- so the main database is connected to the auth database via this association
CREATE TABLE IF NOT EXISTS core.agent_oauth_associations(
    agent_id UUID PRIMARY KEY REFERENCES core.agents(agent_id), 
    user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- +goose Down
DROP TABLE IF EXISTS core.agent_oauth_associations;
DROP TABLE IF EXISTS core.agent_store;
DROP TABLE IF EXISTS core.agent_invitations;
DROP TABLE IF EXISTS core.agent_teams;
DROP TABLE IF EXISTS core.agents;