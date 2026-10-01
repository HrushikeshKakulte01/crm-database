-- +goose Up
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


-- +goose Down
DROP TABLE IF EXISTS core.partners;