-- +goose Up
-- conversations of users
-- over different platforms
CREATE TABLE IF NOT EXISTS core.conversations(
    conversation_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    participant_type VARCHAR(10) NOT NULL CHECK(
        participant_type IN(
            'single',
            'group'
        )
    ),
    platform core.platform NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ
);
-- active conversations by organization and participant type
CREATE INDEX IF NOT EXISTS idx_conversations_org_single_active
    ON core.conversations(organization_id, participant_type, conversation_id)
    WHERE ended_at IS NULL;

-- conversation participants when conversation is by a single user
CREATE TABLE IF NOT EXISTS core.conversation_participant_singles(
    conversation_id UUID PRIMARY KEY REFERENCES core.conversations(conversation_id),
    user_id UUID NOT NULL REFERENCES core.users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- lookup by user and conversation pair
CREATE INDEX IF NOT EXISTS idx_conversation_participant_singles_user_conversation
    ON core.conversation_participant_singles(user_id, conversation_id);

-- conversation participants when conversation is by a group of users
CREATE TABLE IF NOT EXISTS core.conversation_participant_groups(
    conversation_id UUID PRIMARY KEY REFERENCES core.conversations(conversation_id),
    group_id UUID NOT NULL REFERENCES core.groups(group_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- contain the actual content for each conversation unit
-- can be part of:
-- - bot
-- - broadcast (in the platform specific schema conversations table)
-- - ticket
-- conversation element can be both bot and ticket at the same time
-- (for when ticket is created as a result of a bot node)
-- 'element_type' is 'internal' when element is for internal use only
-- (not visible to the user)
CREATE TABLE IF NOT EXISTS core.conversation_elements(
    element_id UUID PRIMARY KEY DEFAULT uuidv7(),
    conversation_id UUID NOT NULL REFERENCES core.conversations(conversation_id),
    element_type VARCHAR(20) NOT NULL CHECK(
        element_type IN(
            'incoming',
            'outgoing',
            'internal'
        )
    ),
    is_bot BOOLEAN NOT NULL DEFAULT false,
    is_ticket BOOLEAN NOT NULL DEFAULT false,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK(
        status IN(
            'pending',
            'cancelled',
            'sent',
            'delivered',
            'read',
            'failed',
            'played',
            'deleted'
        )
    ),
    cancelled_at TIMESTAMPTZ,
    sent_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ,
    failed_at TIMESTAMPTZ,
    played_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
-- elements by conversation with recency
CREATE INDEX IF NOT EXISTS idx_conversation_elements_conversation_created_element
    ON core.conversation_elements(conversation_id, created_at DESC, element_id DESC);

-- details of which user wrote the conversation element
-- group conversations - identifies the specific group participant who sent the incoming message
-- single conversations - copy user_id from conversation_participant_singles
-- (compulsory enter a copy for consistency)
CREATE TABLE IF NOT EXISTS core.conversation_element_user_write_details(
    element_id UUID PRIMARY KEY REFERENCES core.conversation_elements(element_id),
    user_id UUID NOT NULL REFERENCES core.users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- details of which agent wrote the conversation element
-- covers all agent-authored elements including outgoing messages, ticket notes,
-- ticket assignment messages, and any other internal elements
CREATE TABLE IF NOT EXISTS core.conversation_element_agent_write_details(
    element_id UUID PRIMARY KEY REFERENCES core.conversation_elements(element_id),
    agent_id UUID NOT NULL REFERENCES core.agents(agent_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- details of the bot that the conversation elements are a part of
CREATE TABLE IF NOT EXISTS core.conversation_element_bot_details(
    element_id UUID PRIMARY KEY REFERENCES core.conversation_elements(element_id),
    node_id UUID REFERENCES core.bot_nodes(node_id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- lookup bot details by node
CREATE INDEX IF NOT EXISTS idx_conversation_element_bot_details_node_element
    ON core.conversation_element_bot_details(node_id, element_id);

-- details of the ticket that the conversation elements are a part of
CREATE TABLE IF NOT EXISTS core.conversation_element_ticket_details(
    element_id UUID PRIMARY KEY REFERENCES core.conversation_elements(element_id),
    ticket_id UUID NOT NULL REFERENCES core.tickets(ticket_id),
    is_note BOOLEAN NOT NULL DEFAULT false,
    is_ticket_assignment BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- lookup ticket details by ticket
CREATE INDEX IF NOT EXISTS idx_conversation_element_ticket_details_ticket_element
    ON core.conversation_element_ticket_details(ticket_id, element_id);

-- conversation assignment message
-- linked to the conversation_elements table via 'is_ticket_assignment' boolean flag
-- a copy of the ticket assignment message from the core.ticket_assignment_histories table
-- it is stored here to avoid the need to join the tables to get the assignment message
CREATE TABLE IF NOT EXISTS core.conversation_element_ticket_assignment_details(
    element_id UUID PRIMARY KEY REFERENCES core.conversation_elements(element_id),
    assignment_message TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- note in a ticket conversation
-- linked to the conversation_elements table via 'is_note' boolean flag
-- admin agents can add notes to the conversation without having
-- the ticket assigned to them
CREATE TABLE IF NOT EXISTS core.conversation_element_ticket_notes(
    element_id UUID PRIMARY KEY REFERENCES core.conversation_elements(element_id),
    note TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- +goose Down
DROP TABLE IF EXISTS core.conversation_element_ticket_notes;
DROP TABLE IF EXISTS core.conversation_element_ticket_assignment_details;
DROP TABLE IF EXISTS core.conversation_element_ticket_details;
DROP TABLE IF EXISTS core.conversation_element_bot_details;
DROP TABLE IF EXISTS core.conversation_element_agent_write_details;
DROP TABLE IF EXISTS core.conversation_element_user_write_details;
DROP TABLE IF EXISTS core.conversation_elements;
DROP TABLE IF EXISTS core.conversation_participant_groups;
DROP TABLE IF EXISTS core.conversation_participant_singles;
DROP TABLE IF EXISTS core.conversations;