-- +goose Up
-- tickets can be part of a bot
-- or can be directly started by a user
-- if from a bot, when a ticket is started, the conversation state of the user
-- is stuck at a bot "ticket" node
CREATE TABLE IF NOT EXISTS core.tickets(
    ticket_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    description TEXT,
    participant_type VARCHAR(10) NOT NULL CHECK(
        participant_type IN(
            'single',
            'group'
        )
    ),
    is_bot BOOLEAN NOT NULL DEFAULT false,
    ticket_status VARCHAR(10) NOT NULL CHECK(
        ticket_status IN(
            'active',
            'resolved',
            'deleted'
        )
    ),
    platform core.platform NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);
-- tickets by organization, status, and recency
CREATE INDEX IF NOT EXISTS idx_tickets_org_status_created_ticket
    ON core.tickets(organization_id, ticket_status, created_at DESC, ticket_id DESC);
-- tickets by status and recency
CREATE INDEX IF NOT EXISTS idx_tickets_status_created_ticket
    ON core.tickets(ticket_status, created_at DESC, ticket_id DESC);
-- tickets by platform, participant type, status, and recency
CREATE INDEX IF NOT EXISTS idx_tickets_platform_participant_status_created_at
    ON core.tickets(platform, participant_type, ticket_status, created_at DESC);

-- ticket participants when ticket is by a single user
CREATE TABLE IF NOT EXISTS core.ticket_participant_singles(
    ticket_id UUID PRIMARY KEY REFERENCES core.tickets(ticket_id),
    user_id UUID NOT NULL REFERENCES core.users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- lookup ticket participants by user
CREATE INDEX IF NOT EXISTS idx_ticket_participant_singles_user_ticket
    ON core.ticket_participant_singles(user_id, ticket_id);

-- ticket participants when ticket is by a group of users
CREATE TABLE IF NOT EXISTS core.ticket_participant_groups(
    ticket_id UUID PRIMARY KEY REFERENCES core.tickets(ticket_id),
    group_id UUID NOT NULL REFERENCES core.groups(group_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- node_id of the bot node that the ticket is a part of
CREATE TABLE IF NOT EXISTS core.ticket_bot_details(
    ticket_id UUID PRIMARY KEY REFERENCES core.tickets(ticket_id),
    node_id UUID REFERENCES core.bot_nodes(node_id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- history of ticket assignments between agents and departments
-- 'assignment criteria' is the algorithm by which the ticket was
-- assigned the way it was.
-- options:
-- 'to-specific-agent'
-- 'to-online-agent-with-least-count' 
-- 'to-specific-team'
-- 'to-online-agent-in-team-with-least-count'
CREATE TABLE IF NOT EXISTS core.ticket_assignment_histories(
    assignment_history_id UUID PRIMARY KEY DEFAULT uuidv7(),
    ticket_id UUID NOT NULL REFERENCES core.tickets(ticket_id),
    agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    assignment_message TEXT NOT NULL,
    assignment_criteria TEXT NOT NULL CHECK(
        assignment_criteria IN (
            'to-specific-agent',
            'to-online-agent-with-least-count',
            'to-specific-team',
            'to-online-agent-in-team-with-least-count'
        )
    ),
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- covering index for assignment history by ticket with recency
CREATE INDEX IF NOT EXISTS idx_ticket_assignment_histories_ticket_assigned_at
    ON core.ticket_assignment_histories(ticket_id, assigned_at DESC)
    INCLUDE (assignment_history_id, agent_id, assignment_message);
-- assignment history by agent with recency
CREATE INDEX IF NOT EXISTS idx_ticket_assignment_histories_agent_assigned_at
    ON core.ticket_assignment_histories(agent_id, assigned_at DESC);

-- tags for tickets
CREATE TABLE IF NOT EXISTS core.ticket_tags(
    ticket_id UUID NOT NULL REFERENCES core.tickets(ticket_id),
    tag TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    PRIMARY KEY (ticket_id, tag)
);
-- active tags for a ticket
CREATE INDEX IF NOT EXISTS idx_ticket_tags_ticket_active
    ON core.ticket_tags(ticket_id)
    WHERE is_active = true;

-- ratings for tickets
CREATE TABLE IF NOT EXISTS core.ticket_ratings(
    ticket_id UUID PRIMARY KEY REFERENCES core.tickets(ticket_id),
    rating INTEGER NOT NULL,
    comment TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- +goose Down
DROP TABLE IF EXISTS core.ticket_ratings;
DROP TABLE IF EXISTS core.ticket_tags;
DROP TABLE IF EXISTS core.ticket_assignment_histories;
DROP TABLE IF EXISTS core.ticket_bot_details;
DROP TABLE IF EXISTS core.ticket_participant_groups;
DROP TABLE IF EXISTS core.ticket_participant_singles;
DROP TABLE IF EXISTS core.tickets;