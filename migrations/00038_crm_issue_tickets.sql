-- +goose Up

CREATE TABLE IF NOT EXISTS crm.issue_tickets(
    ticket_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL,
    issue_id UUID NOT NULL,
    ticket_type VARCHAR(20) NOT NULL CHECK (ticket_type IN ('voice_call', 'whatsapp_chat', 'video_call', 'in_person_meeting')),
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