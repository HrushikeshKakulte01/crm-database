-- +goose Up
-- bots are automated conversation flows
-- created by an admin agent
-- participant type      - single, group (if bot is for a single user or a group of users)
-- vertical              - support, course, game
-- platform              - TYPE ENUM core.platform
-- store_stock_value_id  - the stock value id of the store for the bot
CREATE TABLE IF NOT EXISTS core.bots(
    bot_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id	UUID NOT NULL REFERENCES core.organizations(organization_id),
    bot_name TEXT NOT NULL,
    description TEXT NOT NULL,
    participant_type VARCHAR(10) NOT NULL CHECK(
        participant_type IN(
            'single',
            'group'
        )
    ),
    vertical VARCHAR(10) NOT NULL CHECK(
        vertical IN(
            'support',
            'course',
            'game'
        )
    ),
    platform core.platform NOT NULL,
    default_store JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT true,
    is_published BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (organization_id, bot_name)
);

-- bot functions are the functions that the bot can perform
CREATE TABLE IF NOT EXISTS core.bot_functions(
    function_id UUID PRIMARY KEY DEFAULT uuidv7(),
    bot_id UUID NOT NULL REFERENCES core.bots(bot_id) ON DELETE CASCADE,
    function_name TEXT NOT NULL,
    function_code JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (bot_id, function_name)
);

-- tags assigned to each bot by the admin
-- specific to the organization
CREATE TABLE IF NOT EXISTS core.bot_tags(
    bot_id UUID NOT NULL REFERENCES core.bots(bot_id),
    tag TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    PRIMARY KEY (bot_id, tag)
);

-- nodes (conversation action elements) for each bot
-- delete from table if node is deleted from the bot
-- (does not follow the 'is_active' column pattern)
-- is_sequential - false -> wait for user reply
CREATE TABLE IF NOT EXISTS core.bot_nodes(
    node_id UUID PRIMARY KEY DEFAULT uuidv7(),
    bot_id UUID NOT NULL REFERENCES core.bots(bot_id),
    node_type VARCHAR(50) NOT NULL CHECK(
        node_type IN(
            'message',
            'condition',
            'operation',
            'connector'
        )
    ),
    is_sequential BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
-- lookup nodes by bot with creation order
CREATE INDEX IF NOT EXISTS idx_bot_nodes_bot_created_at
    ON core.bot_nodes(bot_id, created_at, node_id);

-- node-scoped triggers: a (trigger_type, event_key) pair attaches to a specific bot
-- node so one bot can expose multiple webhook entry points (one per triggered node).
-- the default whatsapp/incoming_message flow is intentionally NOT registered here;
-- it uses the phone -> bot mapping in whatsapp.bot_platform_associations instead.
-- bot_id and organization_id are denormalized because postgres partial unique indexes
-- cannot reference other tables via subqueries; carrying bot_id on the row lets us put
-- the per-bot uniqueness constraint directly on the columns.
CREATE TABLE IF NOT EXISTS core.bot_node_triggers(
    node_id UUID PRIMARY KEY REFERENCES core.bot_nodes(node_id) ON DELETE CASCADE,
    bot_id UUID NOT NULL REFERENCES core.bots(bot_id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    trigger_type TEXT NOT NULL,
    event_key TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
-- one (trigger_type, event_key) pair per bot for active triggers
CREATE UNIQUE INDEX IF NOT EXISTS idx_bot_node_triggers_bot_event_active
    ON core.bot_node_triggers(bot_id, trigger_type, event_key)
    WHERE is_active = true;
-- lookup path used by the worker on webhook delivery
CREATE INDEX IF NOT EXISTS idx_bot_node_triggers_lookup
    ON core.bot_node_triggers(trigger_type, event_key)
    WHERE is_active = true;
-- "list a bot's node triggers" reads from the admin UI
CREATE INDEX IF NOT EXISTS idx_bot_node_triggers_bot
    ON core.bot_node_triggers(bot_id);

-- edges between bot nodes
-- a node can have multiple parent nodes and multiple child nodes
-- supports loop-backs into the bot flow downstream but not self-loops
CREATE TABLE IF NOT EXISTS core.bot_node_edges(
    edge_id UUID PRIMARY KEY DEFAULT uuidv7(),
    parent_node_id UUID NOT NULL REFERENCES core.bot_nodes(node_id) ON DELETE CASCADE,
    child_node_id UUID NOT NULL REFERENCES core.bot_nodes(node_id) ON DELETE CASCADE,
    is_fallback BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (parent_node_id, child_node_id),
    CHECK (parent_node_id <> child_node_id)
);
-- one fallback edge per parent node
CREATE UNIQUE INDEX IF NOT EXISTS idx_core_bot_node_edges_one_fallback_per_parent
    ON core.bot_node_edges(parent_node_id)
    WHERE is_fallback = true;
-- lookup edges by child node
CREATE INDEX IF NOT EXISTS idx_bot_node_edges_child
    ON core.bot_node_edges(child_node_id);
CREATE INDEX IF NOT EXISTS idx_bot_node_edges_parent_created_at
    ON core.bot_node_edges(parent_node_id, created_at, child_node_id);

-- choices in the conversation are decided by conditions
-- 'condition_type' and 'condition' combined decide the flow
-- for example, if 'condition_type' is 'exact_text_match', the
-- 'condition' is the text that the admin decides needs to be matched
-- single condition for single node
CREATE TABLE IF NOT EXISTS core.bot_conditions(
    node_id UUID PRIMARY KEY REFERENCES core.bot_nodes(node_id) ON DELETE CASCADE,
    condition_type VARCHAR(50) NOT NULL CHECK(
        condition_type IN(
            'session_replay_sequence_completion',
            'code_execution',
            'symbolic_equivalency',
            'equivalency',
            'exact_text_match',
            'location_check',
            'boolean',
            'list',
            'range',
            'type_check',
            'trigger'
        )
    ),
    condition JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- bot node operations
-- to perform operations on the bot node
-- operation structure for bot operations
-- for ticket operation:
-- {
--     "assignment_criteria": # "to-online-agent-with-least-count" | "to-specific-team" | "to-online-agent-in-team-with-least-count"
--     "assignment_message": # "Your support ticket has been created and is being assigned to our agent. Please wait for the agent to respond."
--     "team_id": "123e4567-e89b-12d3-a456-426614174000" # if assignment_criteria is 'to-specific-team' or 'to-online-agent-in-team-with-least-count'
-- }
CREATE TABLE IF NOT EXISTS core.bot_operations(
    node_id UUID PRIMARY KEY REFERENCES core.bot_nodes(node_id) ON DELETE CASCADE,
    operation_type VARCHAR(50) NOT NULL CHECK(
        operation_type IN(
            'ticket',
            'store_action',
            'scheduler',
            'generator_document',
            'fetch_user_details'
        )
    ),
    operation JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- bot node connectors link to outside artifacts like LLMs, special components, etc
CREATE TABLE IF NOT EXISTS core.bot_node_connectors(
    node_id UUID PRIMARY KEY REFERENCES core.bot_nodes(node_id) ON DELETE CASCADE,
    connector_type core.connector NOT NULL,
    connector_details JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- bot node coordinates
-- to display bot nodes on frontend canvas properly
CREATE TABLE IF NOT EXISTS core.bot_node_coordinates(
    node_id UUID PRIMARY KEY REFERENCES core.bot_nodes(node_id) ON DELETE CASCADE,
    x INTEGER NOT NULL DEFAULT 0,
    y INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- tracks which user is currently at which node in a bot conversation
-- only one active state per user per bot
-- turn 'is_active' to false when the conversation ends
-- 'store' is a JSONB object that stores the state of the bot conversation
CREATE TABLE IF NOT EXISTS core.bot_conversation_states_user(
    state_id UUID PRIMARY KEY DEFAULT uuidv7(),
    bot_id UUID NOT NULL REFERENCES core.bots(bot_id),
    node_id UUID REFERENCES core.bot_nodes(node_id) ON DELETE SET NULL,
    user_id UUID NOT NULL REFERENCES core.users(user_id),
    store JSONB, -- may be null -- TODO make not null
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
-- unique active conversation per user per bot
CREATE UNIQUE INDEX IF NOT EXISTS idx_core_bot_conversation_states_user_active
    ON core.bot_conversation_states_user(bot_id, user_id)
    WHERE is_active = true;
-- active bot states by user
CREATE INDEX IF NOT EXISTS idx_bot_conversation_states_user_active_user
    ON core.bot_conversation_states_user(user_id)
    WHERE is_active = true;

-- tracks which group is currently at which node in a bot conversation
-- for group bots
-- turn 'is_active' to false when the group conversation ends
-- 'store is a JSONB object that stores the state of the bot conversation
CREATE TABLE IF NOT EXISTS core.bot_conversation_states_group(
    state_id UUID PRIMARY KEY DEFAULT uuidv7(),
    bot_id UUID NOT NULL REFERENCES core.bots(bot_id),
    node_id UUID NOT NULL REFERENCES core.bot_nodes(node_id),
    group_id UUID NOT NULL REFERENCES core.groups(group_id),
    store JSONB, -- may be null -- TODO make not null
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
-- unique active conversation per group per bot
CREATE UNIQUE INDEX IF NOT EXISTS idx_core_bot_conversation_states_group_active
    ON core.bot_conversation_states_group(bot_id, group_id)
    WHERE is_active = true;
-- active bot states by group
CREATE INDEX IF NOT EXISTS idx_bot_conversation_states_group_active_group
    ON core.bot_conversation_states_group(group_id)
    WHERE is_active = true;

-- pending delay executions for async scheduler firing (worker claims via NATS)
CREATE TABLE IF NOT EXISTS core.bot_delay_executions(
    delay_id UUID PRIMARY KEY DEFAULT uuidv7(),
    bot_id UUID NOT NULL REFERENCES core.bots(bot_id) ON DELETE CASCADE,
    node_id UUID NOT NULL REFERENCES core.bot_nodes(node_id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES core.organizations(organization_id),
    user_phone TEXT NOT NULL,
    delay_type TEXT NOT NULL CHECK (
        delay_type IN (
            'interval_time',
            'fixed_time',
            'variable_time'
        )
    ),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (
        status IN (
            'pending',
            'processing',
            'fired',
            'failed'
        )
    ),
    fire_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- index for pending delay executions
CREATE INDEX IF NOT EXISTS idx_bot_delay_executions_pending
    ON core.bot_delay_executions (fire_at ASC)
    WHERE status = 'pending';
-- pending-only index doesn't cover bot_id/user_phone or status IN (pending, processing)
CREATE INDEX IF NOT EXISTS idx_bot_delay_executions_bot_user_status
    ON core.bot_delay_executions (bot_id, user_phone, status);


-- +goose Down
DROP TABLE IF EXISTS core.bot_delay_executions;
DROP TABLE IF EXISTS core.bot_conversation_states_group;
DROP TABLE IF EXISTS core.bot_conversation_states_user;
DROP TABLE IF EXISTS core.bot_node_coordinates;
DROP TABLE IF EXISTS core.bot_node_connectors;
DROP TABLE IF EXISTS core.bot_operations;
DROP TABLE IF EXISTS core.bot_conditions;
DROP TABLE IF EXISTS core.bot_node_edges;
DROP TABLE IF EXISTS core.bot_node_triggers;
DROP TABLE IF EXISTS core.bot_nodes;
DROP TABLE IF EXISTS core.bot_tags;
DROP TABLE IF EXISTS core.bot_functions;
DROP TABLE IF EXISTS core.bots;