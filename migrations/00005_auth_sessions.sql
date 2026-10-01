-- +goose Up
--
-- tables
--
-- users table
CREATE TABLE IF NOT EXISTS auth.users(
    id UUID PRIMARY KEY DEFAULT uuidv4(),
    name TEXT NOT NULL,
    image TEXT,
    email extensions.citext UNIQUE,
    email_verified BOOLEAN,
    phone_number TEXT UNIQUE,
    phone_number_verified BOOLEAN,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- user sessions table
CREATE TABLE IF NOT EXISTS auth.sessions(
    id UUID PRIMARY KEY DEFAULT uuidv4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token TEXT NOT NULL UNIQUE,
    ip_address TEXT,
    user_agent TEXT,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
-- index for user sessions
CREATE INDEX IF NOT EXISTS idx_auth_sessions_users ON auth.sessions(user_id);

-- user accounts table
CREATE TABLE IF NOT EXISTS auth.accounts(
    id UUID PRIMARY KEY DEFAULT uuidv4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    account_id TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    access_token TEXT,
    refresh_token TEXT,
    id_token TEXT,
    scope TEXT,
    password TEXT,
    access_token_expires_at TIMESTAMPTZ,
    refresh_token_expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
-- index for user accounts
CREATE INDEX IF NOT EXISTS idx_auth_accounts_users ON auth.accounts(user_id);

-- verifications table
CREATE TABLE IF NOT EXISTS auth.verifications(
    id UUID PRIMARY KEY DEFAULT uuidv4(),
    identifier TEXT NOT NULL,
    value TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
-- index for identifier
CREATE INDEX IF NOT EXISTS idx_auth_verifications_identifiers ON auth.verifications(identifier);


-- +goose Down
DROP TABLE IF EXISTS auth.verifications;
DROP TABLE IF EXISTS auth.accounts;
DROP TABLE IF EXISTS auth.sessions;
DROP TABLE IF EXISTS auth.users;