-- +goose Up

CREATE TABLE IF NOT EXISTS crm.companies(
    company_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL,
    company_name TEXT NOT NULL,
    city TEXT,
    state TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_companies_org_name_active
    ON crm.companies(organization_id, company_name)
    WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_crm_companies_org_active
    ON crm.companies(organization_id)
    WHERE is_active = true;


-- +goose Down
DROP TABLE IF EXISTS crm.companies;