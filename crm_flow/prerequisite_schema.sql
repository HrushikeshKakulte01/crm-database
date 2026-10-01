-- +goose Up

-- +goose Up
-- +goose StatementBegin
CREATE TABLE IF NOT EXISTS core.countries(
    country_id INTEGER PRIMARY KEY,
    name TEXT NOT NULL
);
-- insert a few countries during migration
INSERT INTO core.countries(country_id, name) VALUES
(1, 'India'),
(2, 'US'),
(3, 'UK'),
(4, 'Germany');
-- +goose StatementEnd

-- +goose StatementBegin
-- geographical states of a country
CREATE TABLE IF NOT EXISTS core.states(
    state_id INTEGER PRIMARY KEY,
    country_id INTEGER NOT NULL REFERENCES core.countries(country_id),
    name TEXT NOT NULL
);
-- insert states of India during migration
INSERT INTO core.states(state_id, country_id, name) VALUES
(1,  1, 'Andhra Pradesh'),
(2,  1, 'Arunachal Pradesh'),
(3,  1, 'Assam'),
(4,  1, 'Bihar'),
(5,  1, 'Chhattisgarh'),
(6,  1, 'Goa'),
(7,  1, 'Gujarat'),
(8,  1, 'Haryana'),
(9,  1, 'Himachal Pradesh'),
(10, 1, 'Jharkhand'),
(11, 1, 'Karnataka'),
(12, 1, 'Kerala'),
(13, 1, 'Madhya Pradesh'),
(14, 1, 'Maharashtra'),
(15, 1, 'Manipur'),
(16, 1, 'Meghalaya'),
(17, 1, 'Mizoram'),
(18, 1, 'Nagaland'),
(19, 1, 'Odisha'),
(20, 1, 'Punjab'),
(21, 1, 'Rajasthan'),
(22, 1, 'Sikkim'),
(23, 1, 'Tamil Nadu'),
(24, 1, 'Telangana'),
(25, 1, 'Tripura'),
(26, 1, 'Uttar Pradesh'),
(27, 1, 'Uttarakhand'),
(28, 1, 'West Bengal'),
(29, 1, 'Andaman and Nicobar Islands'),
(30, 1, 'Chandigarh'),
(31, 1, 'Dadra and Nagar Haveli and Daman and Diu'),
(32, 1, 'Delhi'),
(33, 1, 'Jammu and Kashmir'),
(34, 1, 'Ladakh'),
(35, 1, 'Lakshadweep'),
(36, 1, 'Puducherry');



-- partner table
CREATE TABLE IF NOT EXISTS core.partners(
    partner_id UUID PRIMARY KEY DEFAULT uuidv7(),
    country_id INTEGER NOT NULL REFERENCES core.countries(country_id),
    state_id INTEGER NOT NULL REFERENCES core.states(state_id),
    phone TEXT NOT NULL UNIQUE,
    email extensions.citext NOT NULL UNIQUE,
    name TEXT NOT NULL CHECK (name <> ''),
    city TEXT NOT NULL,
    address TEXT NOT NULL,
    logo_url TEXT NOT NULL UNIQUE,
    domain TEXT UNIQUE, -- optional; NULL permitted if not present
    theme_id UUID NOT NULL REFERENCES core.frontend_themes(theme_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);



-- organization table
CREATE TABLE IF NOT EXISTS core.organizations(
    organization_id UUID PRIMARY KEY DEFAULT uuidv7(),
    partner_id UUID NOT NULL REFERENCES core.partners(partner_id),
    country_id INTEGER NOT NULL REFERENCES core.countries(country_id),
    state_id INTEGER NOT NULL REFERENCES core.states(state_id),
    theme_id UUID NOT NULL REFERENCES core.frontend_themes(theme_id),
    phone TEXT NOT NULL UNIQUE,
    email extensions.citext NOT NULL UNIQUE,
    name TEXT NOT NULL CHECK (name <> ''),
    city TEXT NOT NULL,
    address TEXT NOT NULL,
    logo_url TEXT,
    is_whitelabel BOOLEAN NOT NULL DEFAULT false, -- refer to partner_assignments below
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);



-- agents (employees) table
CREATE TYPE core.agent_role AS ENUM(
    'admin',
    'support',
    'coordinator'
);
CREATE TABLE IF NOT EXISTS core.agents(
    agent_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    role core.agent_role NOT NULL,
    name TEXT NOT NULL CHECK (name <> ''),
    phone TEXT NOT NULL,
    email extensions.citext NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, phone),
    UNIQUE (organization_id, email)
);