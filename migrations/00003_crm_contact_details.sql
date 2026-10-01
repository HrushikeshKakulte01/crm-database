-- +goose Up
-- a lead/customer, as known to the CRM. A "lead" and a "customer" are the
-- same row — status just moves from 'lead' to 'customer' as the
-- relationship progresses, so the Leads and Customers screens are two
-- filtered views of this one table.
--
-- unlike an earlier version of this table, contact_name/phone/email are
-- stored directly here rather than only referenced via the console's
-- core.users — an agent can "Add Lead" for someone who has never
-- messaged in on WhatsApp and has no console user record yet. user_id is
-- therefore nullable: it stays NULL until/unless this contact is later
-- linked (or promoted) to a real core.users row, at which point we copy
-- that id here. It is never a foreign key, since core.users lives in the
-- console's own database (see 00001_crm_schema.sql) — same rule for
-- organization_id, owner_agent_id, and linked_organization_id below.
-- company_id, by contrast, IS a real foreign key: crm.companies lives in
-- this same database.
CREATE TABLE IF NOT EXISTS crm.contact_details(
    contact_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL,
    user_id UUID,
    contact_name TEXT NOT NULL,
    phone VARCHAR(20) NOT NULL,
    email TEXT,
    company_id UUID REFERENCES crm.companies(company_id),
    owner_agent_id UUID,
    status VARCHAR(10) NOT NULL DEFAULT 'lead' CHECK(
        status IN(
            'lead',
            'customer'
        )
    ),
    -- "new" vs "existing/repeat" contact for the organization, as picked
    -- on the Add Lead form ("Type") — a separate classification from
    -- status above (which tracks lead -> customer progress) and from
    -- source below (which tracks the channel the lead came in on).
    contact_type VARCHAR(10) NOT NULL DEFAULT 'new' CHECK(
        contact_type IN(
            'new',
            'existing'
        )
    ),
    -- NOT a CHECK-constrained enum: the Admin Settings "Lead settings"
    -- screen shows Source as a dropdown whose options (Website, Referral,
    -- Walk-in, Campaign, ...) the admin can add to, same as any other
    -- field. The allowed values for a given organization live in
    -- crm.form_fields (field_key = 'source') — this column just stores
    -- whichever value was picked.
    source TEXT,
    -- true when this contact's deal includes the CRM product itself (not
    -- just the organization's own product/service). When that deal goes
    -- through, the console creates a brand-new core.organizations row for
    -- them, and linked_organization_id is set to that organization_id —
    -- so this contact becomes traceable to the new Bitamin organization
    -- it turned into. Stays NULL until that happens.
    includes_crm BOOLEAN NOT NULL DEFAULT false,
    linked_organization_id UUID,
    city TEXT,
    state TEXT,
    -- answers to any organization-defined custom fields (the "+Add
    -- field" builder in Form Settings), keyed by crm.form_fields.field_key.
    -- Built-in fields (name, phone, source, city, state, ...) are never
    -- stored here — only extra fields an admin added themselves.
    custom_fields JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    -- prevents the same phone number being added twice within one
    -- organization, whether as a lead or a customer
    UNIQUE (organization_id, phone)
);
-- leads/customers by organization and status, for the Leads/Customers list screens
CREATE INDEX IF NOT EXISTS idx_crm_contact_details_org_status
    ON crm.contact_details(organization_id, status);
-- lookups by company, for the "All Companies" filter
CREATE INDEX IF NOT EXISTS idx_crm_contact_details_company
    ON crm.contact_details(company_id);
-- lookups by owning agent
CREATE INDEX IF NOT EXISTS idx_crm_contact_details_owner_agent
    ON crm.contact_details(owner_agent_id);
-- lookup once a contact has been linked to a console user
CREATE INDEX IF NOT EXISTS idx_crm_contact_details_user
    ON crm.contact_details(user_id)
    WHERE user_id IS NOT NULL;
-- search/filter on custom field answers
CREATE INDEX IF NOT EXISTS idx_crm_contact_details_custom_fields
    ON crm.contact_details USING GIN (custom_fields);


-- +goose Down
DROP TABLE IF EXISTS crm.contact_details;