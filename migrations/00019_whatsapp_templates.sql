-- +goose Up
-- whatsapp message templates

-- actual 'template_type' values are:
--     'authentication',
--     'coupon',
--     'catalog',
--     'interactive',
--     'limited_time_offer',
--     'media_card_carousel',
--	   'multi_product_message',
--     'product_card_carousel',
--     'single_product_message',
--     'text',
--     'media'
CREATE TABLE IF NOT EXISTS whatsapp.templates(
    template_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    surrogate_waba_id UUID NOT NULL REFERENCES whatsapp.organization_wabas(surrogate_waba_id),
    whatsapp_template_id TEXT NOT NULL,
    message_type whatsapp.message_type NOT NULL,
    agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    template_name TEXT NOT NULL CHECK(
        template_name <> '' -- do not allow '' (empty string)
    ),
    quality_rating TEXT,
    template_language TEXT,
    category TEXT,
    sub_category TEXT,
    allow_category_change BOOLEAN DEFAULT FALSE,
    parameter_format TEXT,
    message_send_ttl_seconds INTEGER,
    library_template_name TEXT,
    template_status TEXT NOT NULL CHECK(
        template_status IN(
            'draft',
            'approved',
            'pending',
            'rejected',
            'deleted'
        )
    ),
    template_object JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, surrogate_waba_id, template_name)
);
-- templates by organization and name with recency
CREATE INDEX IF NOT EXISTS idx_templates_org_name_updated_at
    ON whatsapp.templates(organization_id, template_name, updated_at DESC);
-- templates by name and whatsapp id
CREATE INDEX IF NOT EXISTS idx_templates_name_whatsapp_id
    ON whatsapp.templates(template_name, whatsapp_template_id);


-- +goose Down
DROP TABLE IF EXISTS whatsapp.templates;