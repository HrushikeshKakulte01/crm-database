-- +goose Up
-- store the whatsapp business account id for the organization
-- surrogate primary key as data is fetched from whatsapp and not created by the system
-- also link api tokens for each whatsapp business account
CREATE TABLE IF NOT EXISTS whatsapp.organization_wabas(
    surrogate_waba_id UUID PRIMARY KEY DEFAULT uuidv7(),
    surrogate_business_portfolio_id UUID NOT NULL
        REFERENCES facebook.organization_business_portfolios(surrogate_business_portfolio_id),
    surrogate_api_token_id UUID NOT NULL
        REFERENCES facebook.organization_api_tokens(surrogate_api_token_id),
    whatsapp_business_account_id TEXT NOT NULL,
    name TEXT,
    currency TEXT,
    timezone_id TEXT,
    account_review_status TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
-- lookup wabas by whatsapp business account id
CREATE INDEX IF NOT EXISTS idx_org_wabas_whatsapp_business_account_id
    ON whatsapp.organization_wabas(whatsapp_business_account_id);
-- create unique index for active wabas
CREATE UNIQUE INDEX IF NOT EXISTS idx_organization_wabas_whatsapp_business_account_id_active
    ON whatsapp.organization_wabas(whatsapp_business_account_id)
    WHERE is_active = true;

-- linking developer applications to wabas
CREATE TABLE IF NOT EXISTS whatsapp.organization_developer_app_waba_links(
    surrogate_developer_app_id UUID NOT NULL
        REFERENCES facebook.organization_developer_apps(surrogate_developer_app_id),
    surrogate_waba_id UUID NOT NULL
        REFERENCES whatsapp.organization_wabas(surrogate_waba_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    PRIMARY KEY (surrogate_developer_app_id, surrogate_waba_id)
);

-- store the whatsapp business phone numbers for the organization
-- surrogate primary key as data is fetched from whatsapp and not created by the system
CREATE TABLE IF NOT EXISTS whatsapp.organization_phones(
    surrogate_phone_id UUID PRIMARY KEY DEFAULT uuidv7(),
    surrogate_waba_id UUID NOT NULL
        REFERENCES whatsapp.organization_wabas(surrogate_waba_id),
    whatsapp_business_phone_number_id TEXT NOT NULL,
    phone VARCHAR(20) NOT NULL,
    account_mode TEXT,
    status TEXT,
    country_code TEXT,
    country_dial_code TEXT,
    messaging_limit_tier TEXT,
    platform_type TEXT,
    host_platform TEXT,
    display_name TEXT,
    name_status TEXT,
    pin TEXT,
    code_verification_status TEXT,
    quality_rating TEXT,
    whatsapp_business_manager_messaging_limit TEXT,
    throughput_level TEXT,
    official_business_account_status TEXT,
    is_official_business_account BOOLEAN,
    is_on_biz_app BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
-- create unique index for active whatsapp business phone number ids
CREATE UNIQUE INDEX IF NOT EXISTS idx_organization_phones_whatsapp_business_phone_number_id_active
    ON whatsapp.organization_phones (whatsapp_business_phone_number_id)
    WHERE is_active = true;
-- create unique index for active phone numbers
CREATE UNIQUE INDEX IF NOT EXISTS idx_organization_phones_phone_active
    ON whatsapp.organization_phones(phone)
    WHERE is_active = true;

-- store request ids for smb_app_data sync requests
-- surrogate primary key as data is fetched from whatsapp and not created by the system
-- 'sync_type' are of two types:
--   - 'smb_app_state_sync' : sync's the business app's state (contacts, etc)
--   - 'history'            : sync's the message history
CREATE TABLE IF NOT EXISTS whatsapp.organization_phone_app_data_sync_requests(
    surrogate_request_id UUID PRIMARY KEY DEFAULT uuidv7(),
    surrogate_phone_id UUID NOT NULL
        REFERENCES whatsapp.organization_phones(surrogate_phone_id),
    sync_type TEXT NOT NULL CHECK(
        sync_type IN(
            'smb_app_state_sync',
            'history'
        )
    ),
    request_id TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- view: waba details view
CREATE OR REPLACE VIEW whatsapp.view_phone_waba_details AS (
    SELECT
        obp.organization_id,
        op.surrogate_phone_id,
        op.surrogate_waba_id,
        op.phone,
        op.display_name AS phone_name,
        owa.whatsapp_business_account_id AS waba_id,
        owa.name AS waba_name,
        CASE
            WHEN op.is_on_biz_app = true AND lower(op.platform_type) = 'cloud_api' THEN 'coexistence'
            ELSE 'cloud'
        END AS account_type
    FROM whatsapp.organization_phones op
    INNER JOIN whatsapp.organization_wabas owa ON owa.surrogate_waba_id = op.surrogate_waba_id
    INNER JOIN facebook.organization_business_portfolios obp ON obp.surrogate_business_portfolio_id = owa.surrogate_business_portfolio_id
    WHERE
        op.is_active = true AND
        owa.is_active = true AND
        obp.is_active = true
);


-- +goose Down
DROP VIEW IF EXISTS whatsapp.view_phone_waba_details;
DROP TABLE IF EXISTS whatsapp.organization_phone_app_data_sync_requests;
DROP TABLE IF EXISTS whatsapp.organization_phones;
DROP TABLE IF EXISTS whatsapp.organization_developer_app_waba_links;
DROP TABLE IF EXISTS whatsapp.organization_wabas;