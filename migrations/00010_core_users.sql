-- +goose Up
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

-- stock text values for user tags
-- for users by an agent specific to the team they're part of
CREATE TABLE IF NOT EXISTS core.user_tag_stock_values(
    tag_stock_value_id UUID PRIMARY KEY DEFAULT uuidv7(),
    tag TEXT NOT NULL,
    team_id UUID NOT NULL REFERENCES core.organization_teams(team_id),
    created_by_agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (tag, team_id)
);

-- tags assigned to each user by an agent
CREATE TABLE IF NOT EXISTS core.user_tags(
    user_id UUID NOT NULL REFERENCES core.users(user_id),
    tag_stock_value_id UUID NOT NULL REFERENCES core.user_tag_stock_values(tag_stock_value_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    PRIMARY KEY (user_id, tag_stock_value_id)
);

-- stock attributes are key-value pairs assigned
-- for users by an agent specific to the team they're part of
CREATE TABLE IF NOT EXISTS core.user_attribute_stock_values(
    attribute_stock_value_id UUID PRIMARY KEY DEFAULT uuidv7(),
    user_attribute_key extensions.citext NOT NULL,
    user_attribute_value extensions.citext NOT NULL,
    team_id UUID NOT NULL REFERENCES core.organization_teams(team_id),
    created_by_agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (user_attribute_key, user_attribute_value, team_id)
);

-- attributes are key-value pairs assigned to a user by an agent
CREATE TABLE IF NOT EXISTS core.user_attributes(
    user_id UUID NOT NULL REFERENCES core.users(user_id),
    attribute_stock_value_id UUID NOT NULL
        REFERENCES core.user_attribute_stock_values(attribute_stock_value_id),
    assigned_by_agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    PRIMARY KEY (user_id, attribute_stock_value_id)
);

-- groups here (in the core schema) are abstract groups of users
-- E.g., for whatsapp, they are whatsapp groups
CREATE TABLE IF NOT EXISTS core.groups(
    group_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- group participants (users in the group)
CREATE TABLE IF NOT EXISTS core.group_participants(
    group_id UUID NOT NULL REFERENCES core.groups(group_id),
    user_id UUID NOT NULL REFERENCES core.users(user_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    PRIMARY KEY (group_id, user_id)
);

-- user bulk uploads are reusable groups created from files
CREATE TABLE IF NOT EXISTS core.bulk_uploads(
    bulk_upload_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    name VARCHAR(150) NOT NULL,
    file_url TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
-- index for unique active bulk uploads by organization and name
CREATE UNIQUE INDEX IF NOT EXISTS idx_bulk_uploads_org_active_name
    ON core.bulk_uploads(organization_id, name)
    WHERE is_active = true;

-- users in a bulk upload
CREATE TABLE IF NOT EXISTS core.bulk_upload_participants(
    bulk_upload_id UUID NOT NULL REFERENCES core.bulk_uploads(bulk_upload_id),
    user_id UUID NOT NULL REFERENCES core.users(user_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    PRIMARY KEY (bulk_upload_id, user_id)
);


-- +goose Down
DROP TABLE IF EXISTS core.bulk_upload_participants;
DROP TABLE IF EXISTS core.bulk_uploads;
DROP TABLE IF EXISTS core.group_participants;
DROP TABLE IF EXISTS core.groups;
DROP TABLE IF EXISTS core.user_attributes;
DROP TABLE IF EXISTS core.user_attribute_stock_values;
DROP TABLE IF EXISTS core.user_tags;
DROP TABLE IF EXISTS core.user_tag_stock_values;
DROP TABLE IF EXISTS core.users;