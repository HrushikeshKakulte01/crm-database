-- +goose Up
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

 -- organization partner assignments (for whitelabels)
CREATE TABLE IF NOT EXISTS core.organization_partner_assignments(
    organization_id UUID PRIMARY KEY REFERENCES core.organizations(organization_id),
    partner_id UUID NOT NULL REFERENCES core.partners(partner_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- organization app access
CREATE TABLE IF NOT EXISTS core.organization_app_accesses(
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    app core.app NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    PRIMARY KEY (organization_id, app)
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

-- organization credits
CREATE TABLE IF NOT EXISTS core.organization_credits(
    organization_id UUID PRIMARY KEY REFERENCES core.organizations(organization_id),
    credits_whatsapp_cloud_api INTEGER NOT NULL DEFAULT 0,
    credits_whatsapp_multidevice INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- organization credit transactions
CREATE TABLE IF NOT EXISTS core.organization_credit_transactions(
    credit_transaction_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    platform TEXT NOT NULL CHECK(
        platform IN(
            'whatsapp-cloud-api',
            'whatsapp-multidevice'
        )
    ),
    transaction_type TEXT NOT NULL CHECK(
        transaction_type IN(
            'credit',
            'debit'
        )
    ),
    credits INTEGER NOT NULL CHECK(
        credits > 0
    ),
    amount NUMERIC(10, 2) NOT NULL CHECK(
        amount > 0
    ),
    currency VARCHAR(3) NOT NULL CHECK(
        currency IN(
            'INR',
            'USD',
            'EUR'
        )
    ),
    description TEXT NOT NULL,
    created_by VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- +goose Down
DROP TABLE IF EXISTS core.organization_credit_transactions;
DROP TABLE IF EXISTS core.organization_credits;
DROP TABLE IF EXISTS core.organization_teams;
DROP TABLE IF EXISTS core.organization_app_accesses;
DROP TABLE IF EXISTS core.organization_partner_assignments;
DROP TABLE IF EXISTS core.organizations;