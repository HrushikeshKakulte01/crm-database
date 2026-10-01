-- +goose Up
-- the admin-configurable field list behind the "Lead settings" and
-- "Customer settings" screens in Form Settings. A row here either:
--   (a) overrides a built-in field's required/visible setting (e.g. the
--       admin hides "Email", or adds a "Referral" option to "Source"), or
--   (b) defines a brand-new custom field the admin added via "+Add
--       field" (Short answer / Long answer / Number / Dropdown).
-- There's no row for a built-in field until an admin actually changes
-- it — the app applies sensible defaults (Name/Contact number required
-- and locked, others optional) for any field with no row here yet.
--
-- answers to (b)-type fields are stored in crm.contact_details's
-- custom_fields JSONB, keyed by field_key. Answers to (a)-type (built-in)
-- fields stay in their own real column (contact_name, phone, source,
-- ...) — this table only ever describes the form, never the data.
--
-- organization_id is a copy of the console database's
-- core.organizations.organization_id — not a foreign key (see
-- 00001_crm_schema.sql).
CREATE TABLE IF NOT EXISTS crm.form_fields(
    field_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL,
    -- which form this field belongs to; issue forms are configured
    -- separately (see 00008_crm_issue_form_fields.sql), since issues
    -- also need a distinct form per pipeline stage.
    form_type VARCHAR(10) NOT NULL CHECK(
        form_type IN(
            'lead',
            'customer'
        )
    ),
    field_key VARCHAR(50) NOT NULL,
    label VARCHAR(100) NOT NULL,
    field_type VARCHAR(20) NOT NULL CHECK(
        field_type IN(
            'short_answer',
            'long_answer',
            'number',
            'dropdown_single',
            'dropdown_multi'
        )
    ),
    -- choices for dropdown_single/dropdown_multi fields, e.g.
    -- ["Website", "Referral", "Walk-in", "Campaign"]. NULL for other
    -- field types.
    options JSONB,
    is_required BOOLEAN NOT NULL DEFAULT false,
    is_visible BOOLEAN NOT NULL DEFAULT true,
    sort_order INT NOT NULL DEFAULT 0,
    -- a locked field can still have its options edited (e.g. Source) but
    -- can't be deleted/hidden/made-optional from the Form Settings UI —
    -- this is what "Locked fields are always on the form" means for the
    -- handful of built-in fields that must always exist.
    is_delete_locked BOOLEAN NOT NULL DEFAULT false,
    is_required_locked BOOLEAN NOT NULL DEFAULT false,
    is_visible_locked BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, form_type, field_key)
);
-- a form's full field list in display order, for rendering Add
-- Lead/Customer and the Form Settings editor
CREATE INDEX IF NOT EXISTS idx_crm_form_fields_org_type_order
    ON crm.form_fields(organization_id, form_type, sort_order);


-- +goose Down
DROP TABLE IF EXISTS crm.form_fields;