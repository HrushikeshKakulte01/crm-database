-- +goose Up
-- types of the tickets
-- (not named issue_tickets: a table and a type in the same schema can't share a name)
CREATE TYPE crm.issue_ticket_type AS ENUM (
    'voice_call',
    'whatsapp_chat',
    'video_call',
    'in_person_meeting'
);
-- this table store the follow up task for an issue(eg. call with the customer, meeting with the customer)
CREATE TABLE IF NOT EXISTS crm.issue_tickets(
    ticket_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL,
    issue_id UUID NOT NULL,
    ticket_type crm.issue_ticket_type NOT NULL,
    description TEXT,
    due_date DATE,
    due_time TIME,
    status VARCHAR(10) NOT NULL DEFAULT 'open' CHECK (
        status IN (
            'open',
            'closed'
        )
    ),
    closed_at TIMESTAMPTZ,
    assigned_to UUID NOT NULL REFERENCES core.agents(agent_id),
    created_by UUID NOT NULL REFERENCES core.agents(agent_id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    FOREIGN KEY (organization_id, issue_id)
        REFERENCES crm.issues(organization_id, issue_id),
    CHECK (due_time is NULL OR due_date is NOT NULL),
    CHECK ((status = 'closed') = (closed_at is NOT NULL))
);

-- +goose Down
DROP TABLE IF EXISTS crm.issue_tickets;
DROP TYPE IF EXISTS crm.issue_ticket_type;