-- +goose Up
-- whatsapp specific ticket details
-- links ticket with the phone on which the ticket was created/handled
CREATE TABLE IF NOT EXISTS whatsapp.tickets(
    ticket_id UUID PRIMARY KEY REFERENCES core.tickets(ticket_id),
    surrogate_phone_id UUID NOT NULL REFERENCES whatsapp.organization_phones(surrogate_phone_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- lookup tickets by phone
CREATE INDEX IF NOT EXISTS idx_whatsapp_tickets_phone_ticket
    ON whatsapp.tickets(surrogate_phone_id, ticket_id);


-- +goose Down
DROP TABLE IF EXISTS whatsapp.tickets;