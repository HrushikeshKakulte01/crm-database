-- +goose Up
-- embedded signup flows
-- a worker is responsible for picking up flows when 'is_completed' is true
-- and update the portfolio, waba, phone and api token tables with the 
-- corresponding data
-- worker only picks up flows when 'is_completed' is true and 'is_consumed_by_worker' is false
CREATE TABLE IF NOT EXISTS facebook.organization_embedded_signup_flows(
    embedded_signup_flow_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    flow_type TEXT NOT NULL,
    flow_event TEXT NOT NULL,
    current_step TEXT, -- current step of the flow if not completed
    error_code INTEGER,
    error_message TEXT,
    error_id TEXT,
    session_id TEXT,
    is_from_coexistence BOOLEAN NOT NULL DEFAULT false,
    is_completed BOOLEAN NOT NULL DEFAULT false, -- if the flow is completed
    is_consumed_by_worker BOOLEAN NOT NULL DEFAULT false, -- if the flow is consumed by a worker
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    consumed_at TIMESTAMPTZ,
    UNIQUE (organization_id, flow_type, flow_event)
);

-- store facebook business portfolio details of the organization
-- surrogate primary key as data is fetched from facebook and not created by the system
CREATE TABLE IF NOT EXISTS facebook.organization_business_portfolios(
    surrogate_business_portfolio_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    facebook_business_portfolio_id TEXT NOT NULL,
    business_name TEXT,
    verification_status VARCHAR(20) NOT NULL DEFAULT 'verified',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (facebook_business_portfolio_id, organization_id)
);
-- lookup business portfolios by organization
CREATE INDEX IF NOT EXISTS idx_facebook_org_business_portfolios_org
    ON facebook.organization_business_portfolios(organization_id);

-- store facebook api tokens
-- surrogate primary key as data is fetched from facebook and not created by the system
-- token_type - what mode was used to generate the token
-- webhook secret and access token stored as bytea
CREATE TABLE IF NOT EXISTS facebook.organization_api_tokens(
    surrogate_api_token_id UUID PRIMARY KEY DEFAULT uuidv7(),
    surrogate_business_portfolio_id UUID NOT NULL
        REFERENCES facebook.organization_business_portfolios(surrogate_business_portfolio_id),
    token_type TEXT NOT NULL CHECK(
        token_type IN(
            'system-user-access-token',
            'business-integration-system-user-access-token'
        )
    ),
    access_token BYTEA NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
);
-- create unique index for active token type for a business portfolio
CREATE UNIQUE INDEX IF NOT EXISTS idx_facebook_organization_api_tokens_active
    ON facebook.organization_api_tokens(surrogate_business_portfolio_id, token_type)
    WHERE is_active = true;

-- enable row level security for the api keys table
-- row level security can be forced on the table owner via the 'FORCE' keyword
-- create a policy to only allow access to the api keys table to the organization
-- see: https://www.postgresql.org/docs/current/sql-createpolicy.html
-- see: https://www.postgresql.org/docs/current/ddl-rowsecurity.html
-- 'EXISTS' with a subquery determines if the row exists in the table
-- see: https://www.postgresql.org/docs/current/functions-subquery.html
-- 'myapp.current_organization_id' is set using:
-- BEGIN;
-- SET LOCAL myapp.current_organization_id = <ORGANIZATION_ID>;
-- -- query here
-- COMMIT;
CREATE POLICY facebook_organization_api_token_row_level_security_policy
ON facebook.organization_api_tokens
USING (
    surrogate_business_portfolio_id IN (
        SELECT surrogate_business_portfolio_id
        FROM facebook.organization_business_portfolios
        WHERE organization_id = current_setting('myapp.current_organization_id')::UUID
        AND is_active = true
    )
);
-- enable row level security for the api keys table
ALTER TABLE facebook.organization_api_tokens ENABLE ROW LEVEL SECURITY;

-- organization catalogs
-- surrogate primary key as data is fetched from facebook and not created by the system
CREATE TABLE IF NOT EXISTS facebook.organization_catalogs(
    surrogate_catalog_id UUID PRIMARY KEY DEFAULT uuidv7(),
    surrogate_business_portfolio_id UUID NOT NULL
        REFERENCES facebook.organization_business_portfolios(surrogate_business_portfolio_id),
    facebook_catalog_id TEXT NOT NULL,
    catalog_name TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (facebook_catalog_id, surrogate_business_portfolio_id)
);

-- organization catalog products
-- surrogate primary key as data is fetched from facebook and not created by the system
CREATE TABLE IF NOT EXISTS facebook.organization_catalog_products(
    surrogate_catalog_product_id UUID PRIMARY KEY DEFAULT uuidv7(),
    surrogate_catalog_id UUID REFERENCES facebook.organization_catalogs(surrogate_catalog_id),
    facebook_catalog_product_id TEXT NOT NULL,
    retailer_id TEXT,
    product_name TEXT,
    description TEXT,
    product_url TEXT,
    image_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (facebook_catalog_product_id, surrogate_catalog_id)
);

-- advertisement account id
-- surrogate primary key as data is fetched from facebook and not created by the system
CREATE TABLE IF NOT EXISTS facebook.organization_ad_accounts(
    surrogate_ad_account_id UUID PRIMARY KEY DEFAULT uuidv7(),
    surrogate_business_portfolio_id UUID NOT NULL
        REFERENCES facebook.organization_business_portfolios(surrogate_business_portfolio_id),
    facebook_ad_account_id TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (facebook_ad_account_id, surrogate_business_portfolio_id)
);

-- organization facebook pages
-- surrogate primary key as data is fetched from facebook and not created by the system
CREATE TABLE IF NOT EXISTS facebook.organization_facebook_pages(
    surrogate_page_id UUID PRIMARY KEY DEFAULT uuidv7(),
    surrogate_business_portfolio_id UUID NOT NULL
        REFERENCES facebook.organization_business_portfolios(surrogate_business_portfolio_id),
    facebook_page_id TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (facebook_page_id, surrogate_business_portfolio_id)
);

-- organization dataset ids
-- surrogate primary key as data is fetched from facebook and not created by the system
CREATE TABLE IF NOT EXISTS facebook.organization_datasets(
    surrogate_dataset_id UUID PRIMARY KEY DEFAULT uuidv7(),
    surrogate_business_portfolio_id UUID NOT NULL
        REFERENCES facebook.organization_business_portfolios(surrogate_business_portfolio_id),
    facebook_dataset_id TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (facebook_dataset_id, surrogate_business_portfolio_id)
);

-- organization instagram accounts
-- surrogate primary key as data is fetched from instagram and not created by the system
CREATE TABLE IF NOT EXISTS facebook.organization_instagram_accounts(
    surrogate_instagram_account_id UUID PRIMARY KEY DEFAULT uuidv7(),
    surrogate_business_portfolio_id UUID NOT NULL
        REFERENCES facebook.organization_business_portfolios(surrogate_business_portfolio_id),
    instagram_account_id TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (instagram_account_id, surrogate_business_portfolio_id)
);

-- store facebook developer app details of the organization
-- surrogate primary key as data is fetched from facebook and not created by the system
CREATE TABLE IF NOT EXISTS facebook.organization_developer_apps(
    surrogate_developer_app_id UUID PRIMARY KEY DEFAULT uuidv7(),
    surrogate_business_portfolio_id UUID NOT NULL
        REFERENCES facebook.organization_business_portfolios(surrogate_business_portfolio_id),
    facebook_developer_app_id TEXT NOT NULL,
    facebook_developer_app_secret BYTEA,
    app_name TEXT,
    app_link TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (facebook_developer_app_id, surrogate_business_portfolio_id)
);


-- +goose Down
DROP TABLE IF EXISTS facebook.organization_developer_apps;
DROP TABLE IF EXISTS facebook.organization_instagram_accounts;
DROP TABLE IF EXISTS facebook.organization_datasets;
DROP TABLE IF EXISTS facebook.organization_facebook_pages;
DROP TABLE IF EXISTS facebook.organization_ad_accounts;
DROP TABLE IF EXISTS facebook.organization_catalog_products;
DROP TABLE IF EXISTS facebook.organization_catalogs;
DROP POLICY IF EXISTS facebook_organization_api_token_row_level_security_policy ON facebook.organization_api_tokens;
DROP TABLE IF EXISTS facebook.organization_api_tokens;
DROP TABLE IF EXISTS facebook.organization_business_portfolios;
DROP TABLE IF EXISTS facebook.organization_embedded_signup_flows;