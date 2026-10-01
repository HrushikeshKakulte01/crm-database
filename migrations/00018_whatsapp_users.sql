-- +goose Up
-- user details from whatsapp
-- every change in the user's whatsapp account should be
-- stored as a new row in this table
CREATE TABLE IF NOT EXISTS whatsapp.users(
    user_id UUID REFERENCES core.users(user_id),
    whatsapp_user_id TEXT NOT NULL, -- not sure if this changes on user details update
    whatsapp_profile_name TEXT,
    identity_hash TEXT, -- only included if identity change check enabled
    is_from_coexistence BOOLEAN NOT NULL DEFAULT false,
    is_blocked BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
-- create unique index for active whatsapp user details
CREATE UNIQUE INDEX IF NOT EXISTS idx_whatsapp_users_active
    ON whatsapp.users(user_id)
    WHERE is_active = true;
-- partial active index can't serve lookups that omit is_active = true
-- (e.g. func_whatsapp_process_message's "latest row for user_id, active first")
CREATE INDEX IF NOT EXISTS idx_whatsapp_users_user_id
    ON whatsapp.users (user_id, is_active DESC);

-- store associations from coexistence wabas to users
-- user can be associated with multiple coexistence wabas
CREATE TABLE IF NOT EXISTS whatsapp.user_coexistence_waba_associations(
    user_id UUID NOT NULL REFERENCES core.users(user_id),
    surrogate_waba_id UUID NOT NULL REFERENCES whatsapp.organization_wabas(surrogate_waba_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, surrogate_waba_id)
);

-- table for storing system changes to the user's whatsapp account
CREATE TABLE IF NOT EXISTS whatsapp.user_system_changes(
    user_id UUID PRIMARY KEY REFERENCES core.users(user_id),
    user_system_change whatsapp.user_system_change NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- whatsapp groups
CREATE TABLE IF NOT EXISTS whatsapp.groups(
    group_id UUID PRIMARY KEY NOT NULL REFERENCES core.groups(group_id),
    whatsapp_group_id TEXT NOT NULL,
    subject TEXT NOT NULL,
    description TEXT,
    join_approval_mode VARCHAR(20) NOT NULL CHECK(
        join_approval_mode IN(
            'approval_required',
            'auto_approve'
        )
    ) DEFAULT 'auto_approve',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (whatsapp_group_id)
);


-- +goose Down
DROP TABLE IF EXISTS whatsapp.groups;
DROP TABLE IF EXISTS whatsapp.user_system_changes;
DROP TABLE IF EXISTS whatsapp.user_coexistence_waba_associations;
DROP TABLE IF EXISTS whatsapp.users;