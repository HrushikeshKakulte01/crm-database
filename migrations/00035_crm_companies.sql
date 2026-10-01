-- +goose Up
-- a lead/customer's own business — e.g. "Acme Co", "Deep Traders".
-- scoped per organization (Bitamin client) so two different Bitamin
-- clients can each have their own "Acme Co" without colliding.
CREATE TABLE IF NOT EXISTS crm.companies(
    company_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    company_name TEXT NOT NULL,
    includes_crm BOOLEAN NOT NULL DEFAULT false,
    linked_organization_id UUID REFERENCES core.organizations(organization_id),
    city TEXT,
    state TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
-- one company row per name within an organization (the "All Companies"
-- filter and the company picker on the lead form both rely on this)
CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_companies_org_name_active
    ON crm.companies(organization_id, company_name)
    WHERE is_active = true;
-- companies by organization, for the "All Companies" filter dropdown
CREATE INDEX IF NOT EXISTS idx_crm_companies_org_active
    ON crm.companies(organization_id)
    WHERE is_active = true;


-- +goose Down
DROP TABLE IF EXISTS crm.companies;