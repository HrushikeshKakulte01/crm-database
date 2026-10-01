-- +goose Up

-- +goose StatementBegin
-- ensures a user entry exists and is active in both core.users and whatsapp.users
-- when that user messages on whatsapp
-- handles all combinations of existing/missing and active/inactive states
CREATE OR REPLACE FUNCTION whatsapp.func_upsert_whatsapp_user(
    a_organization_id   UUID,
    a_user_phone        TEXT,
    a_user_name         TEXT -- user's name from whatsapp
)
RETURNS                 UUID
AS $$
DECLARE
    v_core_user_id      UUID;
    v_core_is_active    BOOLEAN;
    v_wa_user_id        UUID;
    v_wa_is_active      BOOLEAN;
BEGIN
    -- get core user details
    SELECT user_id, is_active
    INTO v_core_user_id, v_core_is_active
    FROM core.users
    WHERE organization_id = a_organization_id AND phone = a_user_phone
    ORDER BY is_active DESC
    LIMIT 1;

    -- get whatsapp user details
    SELECT user_id, is_active
    INTO v_wa_user_id, v_wa_is_active
    FROM whatsapp.users
    WHERE user_id = v_core_user_id
    ORDER BY is_active DESC
    LIMIT 1;

    -- if core user is inactive, but whatsapp user is active, raise an exception
    IF v_core_user_id IS NOT NULL AND v_core_is_active IS FALSE AND v_wa_user_id IS NOT NULL AND v_wa_is_active IS TRUE THEN
        RAISE EXCEPTION USING
            ERRCODE = 'DB001',
            MESSAGE = 'core user is inactive, but whatsapp user is active',
            DETAIL  = format('organization_id=%s user_phone=%s', a_organization_id, a_user_phone);
    END IF;

    -- if core user does not exist, create it
    -- if core user exists, and is inactive, recreate new user
    IF v_core_user_id IS NULL OR (v_core_user_id IS NOT NULL AND v_core_is_active IS FALSE) THEN
        INSERT INTO core.users(organization_id, phone, user_name, is_active)
        VALUES (a_organization_id, a_user_phone, a_user_name, true)
        RETURNING user_id
        INTO v_core_user_id;
    END IF;

    -- if whatsapp user does not exist, or is inactive, create it
    IF (v_wa_user_id IS NULL) OR (v_wa_user_id IS NOT NULL AND v_wa_is_active IS FALSE) THEN
        INSERT INTO whatsapp.users(user_id, whatsapp_user_id, whatsapp_profile_name, is_active)
        VALUES (v_core_user_id, a_user_phone, a_user_name, true)
        RETURNING user_id
        INTO v_wa_user_id;
    END IF;

    -- if whatsapp user exists and is active, update it
    IF (v_core_user_id IS NOT NULL AND v_core_is_active IS TRUE) AND (v_wa_user_id IS NOT NULL AND v_wa_is_active IS TRUE) THEN
        UPDATE whatsapp.users
        SET whatsapp_profile_name = a_user_name, updated_at = NOW()
        WHERE user_id = v_wa_user_id AND is_active = true
        RETURNING user_id
        INTO v_wa_user_id;
    END IF;

    -- return the whatsapp user id
    RETURN v_wa_user_id;
END;
$$
LANGUAGE plpgsql;
-- +goose StatementEnd


-- +goose StatementBegin
-- reassigns a ticket to an agent based on criteria
-- NOTE: a_id is agent_id or team_id depending on a_criteria
CREATE OR REPLACE FUNCTION whatsapp.func_reassign_ticket(
    a_organization_id   UUID,
    a_ticket_id         UUID,
    a_id                UUID,
    a_message           TEXT,
    a_criteria          TEXT
)
RETURNS                 VOID
AS $$
DECLARE
    v_agent_id          UUID;
    v_conversation_id   UUID;
    v_element_id        UUID;
BEGIN
    ------------------------------
    -- SECTION 1: RESOLVE AGENT --
    ------------------------------
    IF a_criteria = 'to-specific-agent' THEN
        v_agent_id := a_id;
    ELSIF a_criteria IN ('to-specific-team', 'to-online-agent-with-least-count', 'to-online-agent-in-team-with-least-count') THEN
        SELECT a.agent_id
        INTO v_agent_id
        FROM core.agents a
        INNER JOIN core.agent_store ags ON a.agent_id = ags.agent_id AND ags.online_status = true
        INNER JOIN core.agent_teams at ON a.agent_id = at.agent_id AND at.is_active = true
        INNER JOIN core.organization_teams ot ON at.team_id = ot.team_id AND ot.is_active = true
        WHERE a.organization_id = a_organization_id AND at.team_id = a_id
        ORDER BY (
            SELECT COUNT(*)
            FROM core.ticket_assignment_histories tah
            INNER JOIN core.tickets t ON tah.ticket_id = t.ticket_id
            WHERE tah.agent_id = a.agent_id AND t.ticket_status = 'active'
        ) ASC
        LIMIT 1;
    ELSE
        RAISE EXCEPTION USING
            ERRCODE = 'DB001',
            MESSAGE = 'invalid assignment criteria',
            DETAIL  = format('organization_id=%s ticket_id=%s criteria=%s', a_organization_id, a_ticket_id, a_criteria);
    END IF;

    IF v_agent_id IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = 'DB001',
            MESSAGE = 'no eligible agent found',
            DETAIL  = format('organization_id=%s ticket_id=%s criteria=%s', a_organization_id, a_ticket_id, a_criteria);
    END IF;

    ------------------------------------------
    -- SECTION 2: INSERT ASSIGNMENT HISTORY --
    ------------------------------------------

    -- insert assignment history
    INSERT INTO core.ticket_assignment_histories(ticket_id, agent_id, assignment_message, assignment_criteria)
    VALUES (a_ticket_id, v_agent_id, a_message, a_criteria);

    ---------------------------------------------
    -- SECTION 3: FIND CONVERSATION FOR TICKET --
    ---------------------------------------------
    SELECT c.conversation_id
    INTO v_conversation_id
    FROM core.ticket_participant_singles tps
    INNER JOIN core.conversation_participant_singles cps ON tps.user_id = cps.user_id
    INNER JOIN core.conversations c ON cps.conversation_id = c.conversation_id
    WHERE tps.ticket_id = a_ticket_id AND c.ended_at IS NULL
    LIMIT 1;

    IF v_conversation_id IS NOT NULL THEN
        -- create conversation element
        INSERT INTO core.conversation_elements(conversation_id, element_type, status, is_bot, is_ticket)
        VALUES (v_conversation_id, 'internal', 'sent', false, true)
        RETURNING element_id
        INTO v_element_id;

        -- ticket detail
        INSERT INTO core.conversation_element_ticket_details(element_id, ticket_id, is_ticket_assignment)
        VALUES (v_element_id, a_ticket_id, true);

        -- assignment detail
        INSERT INTO core.conversation_element_ticket_assignment_details(element_id, assignment_message)
        VALUES (v_element_id, a_message);

        -- agent write detail
        INSERT INTO core.conversation_element_agent_write_details(element_id, agent_id)
        VALUES (v_element_id, v_agent_id);
    END IF;

    RETURN;
END;
$$
LANGUAGE plpgsql;
-- +goose StatementEnd


-- +goose StatementBegin
-- creates a ticket and assigns it to an agent based on criteria
CREATE OR REPLACE FUNCTION whatsapp.func_create_and_assign_ticket(
    a_surrogate_phone_id    UUID,
    a_conversation_id       UUID,
    a_assignment_criteria   TEXT,
    a_assignment_message    TEXT,
    a_is_bot                BOOLEAN DEFAULT false,
    a_team_id               UUID DEFAULT NULL
)
RETURNS                     UUID
AS $$
DECLARE
    v_platform              core.platform;
    v_organization_id       UUID;
    v_user_id               UUID;
    v_ticket_id             UUID;
    v_assigned_agent_id     UUID;
BEGIN
    -----------------------------------
    -- SECTION 1: USER & TICKET INFO --
    -----------------------------------
    SELECT c.organization_id, c.platform, cps.user_id
    INTO v_organization_id, v_platform, v_user_id
    FROM core.conversations c
    INNER JOIN core.conversation_participant_singles cps ON c.conversation_id = cps.conversation_id
    WHERE c.conversation_id = a_conversation_id;

    ------------------------------
    -- SECTION 2: CREATE TICKET --
    ------------------------------
    INSERT INTO core.tickets(organization_id, participant_type, is_bot, ticket_status, platform)
    VALUES (v_organization_id, 'single', a_is_bot, 'active', v_platform)
    RETURNING ticket_id
    INTO v_ticket_id;

    INSERT INTO whatsapp.tickets(ticket_id, surrogate_phone_id)
    VALUES (v_ticket_id, a_surrogate_phone_id);

    INSERT INTO core.ticket_participant_singles(ticket_id, user_id)
    VALUES (v_ticket_id, v_user_id);

    -------------------------------------
    -- SECTION 3: FIND AGENT TO ASSIGN --
    -------------------------------------
    IF a_assignment_criteria IN ('to-online-agent-in-team-with-least-count', 'to-specific-team') THEN
        SELECT a.agent_id
        INTO v_assigned_agent_id
        FROM core.agents a
        INNER JOIN core.agent_store ags ON a.agent_id = ags.agent_id AND ags.online_status = true
        INNER JOIN core.agent_teams at ON a.agent_id = at.agent_id AND at.is_active = true
        INNER JOIN core.organization_teams ot ON at.team_id = ot.team_id
        WHERE a.organization_id = v_organization_id AND ot.team_id = a_team_id AND a.is_active = true
        ORDER BY (
            SELECT COUNT(*)
            FROM core.ticket_assignment_histories tah
            INNER JOIN core.tickets t ON tah.ticket_id = t.ticket_id
            WHERE tah.agent_id = a.agent_id AND t.ticket_status = 'active'
        ) ASC
        LIMIT 1;
    ELSE
        SELECT a.agent_id
        INTO v_assigned_agent_id
        FROM core.agents a
        INNER JOIN core.agent_store ags ON a.agent_id = ags.agent_id AND ags.online_status = true
        WHERE a.organization_id = v_organization_id AND a.is_active = true
        ORDER BY (
            SELECT COUNT(*)
            FROM core.ticket_assignment_histories tah
            INNER JOIN core.tickets t ON tah.ticket_id = t.ticket_id
            WHERE tah.agent_id = a.agent_id AND t.ticket_status = 'active'
        ) ASC
        LIMIT 1;
    END IF;

    ------------------------------------------
    -- SECTION 4: CREATE ASSIGNMENT HISTORY --
    ------------------------------------------
    IF v_assigned_agent_id IS NOT NULL THEN
        INSERT INTO core.ticket_assignment_histories(ticket_id, agent_id, assignment_message, assignment_criteria)
        VALUES (v_ticket_id, v_assigned_agent_id, a_assignment_message, a_assignment_criteria);
    END IF;

    -----------------------------
    -- SECTION 5: FINAL RETURN --
    -----------------------------
    RETURN v_ticket_id;
END;
$$
LANGUAGE plpgsql;
-- +goose StatementEnd


-- +goose StatementBegin
-- builds a standard whatsapp text message payload wrapper used by bot responses
CREATE OR REPLACE FUNCTION whatsapp.func_build_text_bot_payload(
    a_element_id    UUID,
    a_user_phone    TEXT,
    a_body          TEXT
)
RETURNS             JSONB
AS $$
    SELECT jsonb_build_object(
        'element_id', a_element_id,
        'message_type', 'text',
        'message', jsonb_build_object(
            'messaging_product', 'whatsapp',
            'recipient_type', 'individual',
            'to', a_user_phone,
            'type', 'text',
            'text', jsonb_build_object(
                'body', a_body
            )
        )
    );
$$
LANGUAGE sql;
-- +goose StatementEnd


-- +goose StatementBegin
-- this function takes in the incoming whatsapp message
-- and processes it through either a bot, a ticket, both, or a direct message
CREATE OR REPLACE FUNCTION whatsapp.func_whatsapp_process_message(
    a_organization_whatsapp_phone_number_id TEXT,
    a_organization_phone                    TEXT,
    a_user_phone                            TEXT,
    a_user_profile_name                     TEXT,
    a_whatsapp_message_id                   TEXT,
    a_message_type                          TEXT,
    a_message_text                          TEXT,
    a_message_payload                       JSONB,
    a_is_trial                              BOOLEAN DEFAULT false,
    a_trial_bot_id                          UUID    DEFAULT NULL
)
RETURNS                                     JSONB
AS $$
DECLARE
    -- resolve user
    v_organization_id                       UUID;
    v_surrogate_phone_id                    UUID;
    v_user_id                               UUID;
    -- resolve bot
    v_bot_id                                UUID := NULL;
    v_ticket_id                             UUID := NULL;
    v_current_node_id                       UUID;
    -- next node
    v_next_node_id                          UUID;
    v_conversation_id                       UUID;
    v_state_bot_id                          UUID;
    v_root_node_id                          UUID;
    -- traversal
    v_walk_node_id                          UUID;
    v_skip_state_update                     BOOLEAN;
    v_is_ticket_operation                   BOOLEAN;
    -- condition evaluation
    v_condition_nodes                       UUID[];
    v_operation_nodes                       UUID[];
    v_message_nodes                         UUID[];
    v_has_conditions                        BOOLEAN;
    v_has_operations                        BOOLEAN;
    v_has_messages                          BOOLEAN;
    v_first_condition_node_id               UUID;
    v_condition_node_id_item                UUID;
    v_condition_type                        TEXT;
    v_condition_value                       TEXT;
    v_condition_json                        JSONB;
    v_condition_expected_boolean            BOOLEAN;
    v_condition_store_value                 JSONB;
    v_condition_passed                      BOOLEAN;
    v_all_conditions_passed                 BOOLEAN;
    v_array_sequential_condition_node_ids   UUID[];
    v_matched_condition_node_id             UUID;
    v_invalid_reply_node_id                 UUID;
    -- operation execution
    v_operation_node_id_item                UUID;
    v_operation_node_type                   TEXT;
    v_operation_type                        TEXT;
    v_operation_value                       JSONB;
    v_operation_connector_type              TEXT;
    v_operation_connector_details           JSONB;
    v_array_sequential_operation_node_ids   UUID[];
    v_last_operation_node_id                UUID;
    v_is_new_ticket                         BOOLEAN := false;
    -- message collection
    v_new_state_node_id                     UUID;
    v_is_last_node_executing                BOOLEAN;
    v_new_state_operation_type              TEXT;
    v_array_executable_node_ids             UUID[];
    v_node_id                               UUID;
    v_executable_node_type                  TEXT;
    v_prefetched_message_type               TEXT;
    v_prefetched_message_object             JSONB;
    v_prefetched_connector_type             TEXT;
    v_prefetched_connector_details          JSONB;
    v_inline_ticket_operation_node_id       UUID;
    v_element_id                            UUID;
    v_message_object                        JSONB;
    v_result                                JSONB := '[]'::JSONB;
    -- incoming message
    v_incoming_element_id                   UUID;
    v_is_ticket                             BOOLEAN := false;
    v_is_ticket_resolved_trigger            BOOLEAN := false;
    v_is_delay_fire_trigger                 BOOLEAN := (
        (a_message_type = 'system' AND COALESCE(a_message_payload->>'event', '') = 'delay_fire') OR
        a_whatsapp_message_id LIKE 'delay-fire-%'
    );
    v_is_workflow_continue_trigger          BOOLEAN := (
        a_whatsapp_message_id LIKE 'workflow-continue%' OR
        (
            a_message_type = 'system' AND
            (
                LOWER(TRIM(COALESCE(a_message_text, ''))) = 'workflow_continue' OR
                LOWER(TRIM(COALESCE(a_message_payload #>> '{text,body}', ''))) = 'workflow_continue'
            )
        )
    );
    v_is_scheduler_operation                BOOLEAN := false;
    v_has_ticket_history_for_current_node   BOOLEAN := false;
    v_forced_bot_id                         UUID := NULL;
    v_forced_trigger_node_id                UUID := NULL;
BEGIN
    -- internal trigger from API when ticket is resolved by agent
    v_is_ticket_resolved_trigger := (
        a_whatsapp_message_id LIKE 'ticket-resolved-%' OR
        (a_message_type = 'system' AND COALESCE(a_message_payload->>'event', '') = 'ticket_resolved')
    );

    -----------------------------
    -- SECTION 1: RESOLVE USER --
    -----------------------------
    -- get organization_id and surrogate_phone_id from organization phone id/number
    SELECT fobp.organization_id, wop.surrogate_phone_id
    INTO v_organization_id, v_surrogate_phone_id
    FROM whatsapp.organization_phones wop
    JOIN whatsapp.organization_wabas wow ON wop.surrogate_waba_id = wow.surrogate_waba_id
    JOIN facebook.organization_business_portfolios fobp ON wow.surrogate_business_portfolio_id = fobp.surrogate_business_portfolio_id
    WHERE
        wop.is_active = true AND
        wow.is_active = true AND
        fobp.is_active = true AND
        (
            wop.whatsapp_business_phone_number_id = a_organization_whatsapp_phone_number_id OR
            wop.whatsapp_business_phone_number_id = a_organization_phone OR
            wop.phone = a_organization_phone
        )
    ORDER BY wop.is_active DESC, wop.updated_at DESC NULLS LAST, wop.created_at DESC
    LIMIT 1;

    IF v_organization_id IS NULL OR v_surrogate_phone_id IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = 'DB001',
            MESSAGE = 'organization phone not mapped',
            DETAIL = format(
                'organization_whatsapp_phone_number_id=%s organization_phone=%s',
                COALESCE(a_organization_whatsapp_phone_number_id, 'NULL'),
                COALESCE(a_organization_phone, 'NULL')
            );
    END IF;

    -- upsert whatsapp user details
    -- ensures there is an active user in both core.users and whatsapp.users
    v_user_id := whatsapp.func_upsert_whatsapp_user(
        a_organization_id => v_organization_id,
        a_user_phone => a_user_phone,
        a_user_name => a_user_profile_name
    );

    -- resolve/create conversation only for non-trial flow
    IF NOT a_is_trial THEN
        SELECT c.conversation_id
        INTO v_conversation_id
        FROM core.conversations c
        INNER JOIN core.conversation_participant_singles cps ON cps.conversation_id = c.conversation_id
        WHERE
            c.organization_id = v_organization_id AND
            c.participant_type = 'single' AND
            c.platform = 'whatsapp'::core.platform AND
            c.ended_at IS NULL AND
            cps.user_id = v_user_id
        ORDER BY c.started_at DESC
        LIMIT 1;

        -- if no conversation exists, create a new one
        IF v_conversation_id IS NULL THEN
            -- one active single-participant whatsapp conversation per user/org
            INSERT INTO core.conversations(organization_id, participant_type, platform)
            VALUES (v_organization_id, 'single', 'whatsapp'::core.platform)
            RETURNING conversation_id
            INTO v_conversation_id;

            INSERT INTO core.conversation_participant_singles(conversation_id, user_id)
            VALUES (v_conversation_id, v_user_id);

            INSERT INTO whatsapp.conversations(conversation_id, surrogate_phone_id)
            VALUES (v_conversation_id, v_surrogate_phone_id)
            ON CONFLICT (conversation_id) DO NOTHING;
        END IF; -- if no conversation exists, create a new one
    END IF; -- if not trial flow

    ----------------------------
    -- SECTION 2: RESOLVE BOT --
    ----------------------------
    -- allow upstream runtime to force bot selection for trigger-based routing.
    IF a_message_payload ? 'bot_id' THEN
        BEGIN
            v_forced_bot_id := NULLIF(a_message_payload->>'bot_id', '')::UUID;
        EXCEPTION WHEN others THEN
            v_forced_bot_id := NULL;
        END;
    END IF;

    -- allow upstream runtime to start the bot flow at a specific node (node-scoped trigger).
    -- when present and valid, this node is used as the root for the sequential walk in STEP 4
    -- instead of the bot's parent-less root node. NULL falls back to legacy behavior.
    IF a_message_payload ? 'trigger_node_id' THEN
        BEGIN
            v_forced_trigger_node_id := NULLIF(a_message_payload->>'trigger_node_id', '')::UUID;
        EXCEPTION WHEN others THEN
            v_forced_trigger_node_id := NULL;
        END;
    END IF;

    IF a_is_trial THEN
        -- trial flow uses explicit bot id and can run unpublished bots
        IF a_trial_bot_id IS NULL THEN
            RAISE EXCEPTION USING
                ERRCODE = 'DB001',
                MESSAGE = 'bot_id required for trial flow',
                DETAIL = 'pass a_trial_bot_id when a_is_trial=true';
        END IF;

        SELECT b.bot_id
        INTO v_bot_id
        FROM core.bots b
        JOIN whatsapp.bots wb ON wb.bot_id = b.bot_id
        WHERE
            b.bot_id = a_trial_bot_id AND
            b.organization_id = v_organization_id AND
            b.platform = 'whatsapp'::core.platform AND
            b.is_active = true;

        IF v_bot_id IS NULL THEN
            RAISE EXCEPTION USING
                ERRCODE = 'DB001',
                MESSAGE = 'trial bot not found or inactive',
                DETAIL = format('bot_id=%s organization_id=%s', a_trial_bot_id, v_organization_id);
        END IF;
    ELSE
        -- non-trial flow prefers forced bot id when provided; otherwise fallback to phone mapping.
        IF v_forced_bot_id IS NOT NULL THEN
            SELECT b.bot_id
            INTO v_bot_id
            FROM core.bots b
            WHERE
                b.bot_id = v_forced_bot_id AND
                b.organization_id = v_organization_id AND
                b.is_active = true AND
                b.is_published = true AND
                b.platform = 'whatsapp'::core.platform
            LIMIT 1;
        ELSE
            SELECT bpa.bot_id
            INTO v_bot_id
            FROM whatsapp.bot_platform_associations bpa
            JOIN core.bots b ON b.bot_id = bpa.bot_id
            WHERE
                bpa.surrogate_phone_id = v_surrogate_phone_id AND
                bpa.is_active = true AND
                b.is_active = true AND
                b.is_published = true AND
                b.platform = 'whatsapp'::core.platform
            ORDER BY b.created_at DESC
            LIMIT 1;
        END IF;
    END IF;

    -- check if there is an active whatsapp ticket for this user on this phone
    -- this ticket is used to mark incoming/outgoing message context (ticket vs non-ticket)
    SELECT ct.ticket_id
    INTO v_ticket_id
    FROM core.tickets ct
    JOIN core.ticket_participant_singles ctps ON ct.ticket_id = ctps.ticket_id
    JOIN whatsapp.tickets wt ON wt.ticket_id = ct.ticket_id
    WHERE
        ctps.user_id = v_user_id AND
        ct.participant_type = 'single' AND
        ct.ticket_status = 'active' AND
        ct.platform = 'whatsapp'::core.platform AND -- we're in the whatsapp schema
        wt.surrogate_phone_id = v_surrogate_phone_id
    ORDER BY ct.created_at DESC
    LIMIT 1;

    -- if bot is active on the phone
    IF v_bot_id IS NOT NULL THEN
        -- get the current node information from the conversation state
        -- if the conversation state does not exist, all of the values will be NULL
        SELECT cbcsu.bot_id, cbcsu.node_id
        INTO v_state_bot_id, v_current_node_id
        FROM core.bot_conversation_states_user cbcsu
        JOIN core.bot_nodes cbn ON cbcsu.node_id = cbn.node_id
        WHERE cbcsu.bot_id = v_bot_id AND cbcsu.user_id = v_user_id AND cbcsu.is_active = true;

        IF v_state_bot_id IS NOT NULL AND v_current_node_id IS NULL THEN
            RAISE EXCEPTION USING
                ERRCODE = 'DB001',
                MESSAGE = 'active state found without node',
                DETAIL = format('bot_id=%s user_id=%s', v_bot_id, v_user_id);
        END IF;
    END IF; -- if bot is active on the phone

    -- for first inbound message (no active state), defer to STEP 4
    -- so root welcome message(s) are emitted before state advances
    IF v_bot_id IS NOT NULL AND v_state_bot_id IS NULL THEN
        NULL;
    END IF;

    -----------------------------------------------------------------
    -- STEP 3: BOT ON PHONE AND USER HAS ACTIVE STATE FOR SAME BOT --
    -----------------------------------------------------------------
    IF v_bot_id IS NOT NULL AND v_state_bot_id IS NOT NULL AND v_bot_id = v_state_bot_id THEN
        -- while a delay is queued, ignore unrelated inbound (menu, branch switches, small talk).
        -- delay_fire and workflow_continue still run (post-delay auto-schedule uses workflow_continue).
        IF NOT a_is_trial AND NOT v_is_delay_fire_trigger AND NOT v_is_workflow_continue_trigger THEN
            IF EXISTS (
                SELECT 1
                FROM core.bot_delay_executions bde
                WHERE
                    bde.bot_id = v_bot_id AND
                    bde.user_phone = a_user_phone AND
                    bde.status IN ('pending', 'processing')
            ) THEN
                RETURN JSONB_STRIP_NULLS(v_result);
            END IF;
        END IF;

        -- keep latest inbound text in store so runtime store_action functions can use it
        -- (for example, storing user-entered budget from the most recent message).
        IF NOT a_is_trial THEN
            UPDATE core.bot_conversation_states_user bcsu
            SET
                store = jsonb_set(
                    jsonb_set(
                        COALESCE(bcsu.store, '{}'::jsonb),
                        '{user}',
                        COALESCE(bcsu.store->'user', '{}'::jsonb),
                        true
                    ),
                    '{user,last_message_text}',
                    to_jsonb(COALESCE(a_message_text, '')),
                    true
                ),
                updated_at = NOW()
            WHERE bcsu.user_id = v_user_id AND bcsu.bot_id = v_bot_id AND bcsu.is_active = true;
        END IF;

        -------------------------------------------------------
        -- STEP 3.1: CHECK IF STATE IS AT TICKET OR SCHEDULER NODE --
        -------------------------------------------------------
        SELECT bo.operation_type
        INTO v_operation_type
        FROM core.bot_operations bo
        WHERE bo.node_id = v_current_node_id;

        IF v_operation_type = 'scheduler' AND NOT a_is_trial AND NOT v_is_delay_fire_trigger AND NOT v_is_workflow_continue_trigger THEN
            -- parked on scheduler: ignore duplicate inbound while a delay is already queued
            IF EXISTS (
                SELECT 1
                FROM core.bot_delay_executions bde
                WHERE
                    bde.bot_id = v_bot_id AND
                    bde.node_id = v_current_node_id AND
                    bde.user_phone = a_user_phone AND
                    bde.status IN ('pending', 'processing')
            ) THEN
                RETURN JSONB_STRIP_NULLS(v_result);
            END IF;

            -- stale park (schedule failed earlier): re-emit scheduler so the worker can insert the delay row
            SELECT bo.operation
            INTO v_operation_value
            FROM core.bot_operations bo
            WHERE bo.node_id = v_current_node_id;

            v_result := v_result || jsonb_build_array(
                jsonb_build_object(
                    'element_id', uuidv7(),
                    'node_id', v_current_node_id,
                    'node_type', 'operation',
                    'operation_type', 'scheduler',
                    'operation', COALESCE(v_operation_value, '{}'::jsonb),
                    'store', COALESCE(
                        (
                            SELECT bcsu.store
                            FROM core.bot_conversation_states_user bcsu
                            WHERE bcsu.user_id = v_user_id AND bcsu.bot_id = v_bot_id AND bcsu.is_active = true
                            ORDER BY bcsu.updated_at DESC NULLS LAST, bcsu.created_at DESC
                            LIMIT 1
                        ),
                        (SELECT b.default_store FROM core.bots b WHERE b.bot_id = v_bot_id LIMIT 1),
                        '{}'::jsonb
                    )
                )
            );
            RETURN JSONB_STRIP_NULLS(v_result);
        END IF;

        IF v_operation_type = 'ticket' THEN
            IF a_is_trial THEN
                -- trial: terminate state on ticket_resolved so the next user input re-triggers the bot.
                IF v_is_ticket_resolved_trigger THEN
                    UPDATE core.bot_conversation_states_user
                    SET is_active = false, updated_at = NOW()
                    WHERE user_id = v_user_id AND bot_id = v_bot_id AND is_active = true;
                    -- prevent traversal/state re-activation in this call
                    v_is_ticket := true;
                END IF;
            ELSE
                IF v_is_ticket_resolved_trigger THEN
                    -- external ticket resolution trigger.
                    -- If current ticket-op node is terminal (no outgoing edges), terminate state
                    -- immediately like a terminal message node.
                    IF NOT EXISTS (
                        SELECT 1
                        FROM core.bot_node_edges
                        WHERE parent_node_id = v_current_node_id
                    ) THEN
                        UPDATE core.bot_conversation_states_user
                        SET is_active = false, updated_at = NOW()
                        WHERE user_id = v_user_id AND bot_id = v_bot_id AND is_active = true;

                        -- prevent traversal/state re-advancement in this call.
                        v_is_ticket := true;
                    ELSE
                        -- non-terminal ticket-op: unlock traversal; generic traversal below will
                        -- move to the proper next node while skipping ticket-op execution.
                        v_is_ticket := false;
                    END IF;
                ELSE
                    -- if current state points to a ticket operation node, verify if ticket is still active
                    SELECT cet.ticket_id
                    INTO v_ticket_id
                    FROM core.conversation_element_ticket_details cet
                    INNER JOIN core.tickets t ON t.ticket_id = cet.ticket_id
                    INNER JOIN core.conversation_elements ce ON cet.element_id = ce.element_id
                    INNER JOIN core.conversation_element_bot_details cebd ON cebd.element_id = ce.element_id
                    WHERE ce.conversation_id = v_conversation_id AND t.ticket_status = 'active' AND cebd.node_id = v_current_node_id
                    LIMIT 1;

                    IF v_ticket_id IS NOT NULL THEN
                        v_is_ticket := true;
                    ELSE
                        -- if this ticket-op node has already created a ticket in this conversation
                        -- (resolved/deleted now), do not reopen ticket; advance traversal instead.
                        SELECT EXISTS (
                            SELECT 1
                            FROM core.conversation_element_ticket_details cet
                            INNER JOIN core.conversation_elements ce ON ce.element_id = cet.element_id
                            INNER JOIN core.conversation_element_bot_details cebd ON cebd.element_id = ce.element_id
                            WHERE ce.conversation_id = v_conversation_id AND cebd.node_id = v_current_node_id
                        )
                        INTO v_has_ticket_history_for_current_node;

                        IF v_has_ticket_history_for_current_node THEN
                            v_is_ticket := false;
                            v_is_new_ticket := false;
                        ELSE
                            -- current node itself is ticket operation and no active ticket exists:
                            -- create ticket now and keep state locked on this node.
                            SELECT bo.operation
                            INTO v_operation_value
                            FROM core.bot_operations bo
                            WHERE bo.node_id = v_current_node_id AND bo.operation_type = 'ticket';

                            IF NOT a_is_trial THEN
                                SELECT whatsapp.func_create_and_assign_ticket(
                                    v_surrogate_phone_id,
                                    v_conversation_id,
                                    v_operation_value->>'assignment_criteria',
                                    v_operation_value->>'assignment_message',
                                    true,
                                    NULLIF(v_operation_value->>'team_id', '')::UUID
                                ) INTO v_ticket_id;

                                INSERT INTO core.ticket_bot_details(ticket_id, node_id)
                                VALUES (v_ticket_id, v_current_node_id);
                            END IF;

                            v_is_new_ticket := true;
                            v_is_ticket := true;

                            UPDATE core.bot_conversation_states_user
                            SET node_id = v_current_node_id, updated_at = NOW()
                            WHERE user_id = v_user_id AND bot_id = v_bot_id AND is_active = true;

                            IF NOT a_is_trial THEN
                                INSERT INTO core.conversation_elements(conversation_id, element_type, is_bot, is_ticket)
                                VALUES (v_conversation_id, 'outgoing', true, true)
                                RETURNING element_id
                                INTO v_element_id;

                                INSERT INTO core.conversation_element_bot_details(element_id, node_id)
                                VALUES (v_element_id, v_current_node_id);

                                IF v_ticket_id IS NOT NULL THEN
                                    INSERT INTO core.conversation_element_ticket_details(element_id, ticket_id)
                                    VALUES (v_element_id, v_ticket_id);
                                END IF;
                            ELSE
                                v_element_id := uuidv7();
                            END IF;

                            IF NOT EXISTS (
                                SELECT 1
                                FROM jsonb_array_elements(v_result) AS elem
                                WHERE
                                    elem->>'message_type' = 'text' AND
                                    elem #>> '{message,text,body}' = v_operation_value->>'assignment_message'
                            ) THEN
                                v_result := v_result || jsonb_build_array(
                                    whatsapp.func_build_text_bot_payload(
                                        v_element_id,
                                        a_user_phone,
                                        v_operation_value->>'assignment_message'
                                    )
                                );
                            END IF;
                        END IF;
                    END IF;
                END IF;
            END IF; -- trial / non-trial branch for current ticket op node
        END IF; -- if current state points to a ticket operation node, verify if ticket is still active

        IF NOT v_is_ticket THEN
            -- generic graph traversal: conditions -> operations -> messages
            -- loop exits when next executable message node is resolved (or ticket op locks the flow)
            v_walk_node_id := v_current_node_id;
            v_skip_state_update := false;
            v_is_ticket_operation := false;

            ----------------------------------------------------------
            -- TRAVERSAL LOOP: CONDITIONS -> OPERATIONS -> MESSAGES --
            ----------------------------------------------------------
            <<traverse_loop>>
            LOOP
                -- get children of current node grouped by type
                -- exclude trigger-only condition nodes (is_trigger=true): they are entry points
                -- fired by webhook (trigger_type, event_key), not evaluated by user-input flow.
                SELECT
                    ARRAY_AGG(bn.node_id) FILTER (
                        WHERE bn.node_type = 'condition'
                        AND NOT EXISTS (
                            SELECT 1 FROM core.bot_node_triggers bnt
                            WHERE bnt.node_id = bn.node_id AND bnt.is_active = true
                        )
                    ),
                    ARRAY_AGG(bn.node_id) FILTER (WHERE bn.node_type IN ('operation', 'connector')),
                    ARRAY_AGG(bn.node_id) FILTER (WHERE bn.node_type = 'message')
                INTO v_condition_nodes, v_operation_nodes, v_message_nodes
                FROM core.bot_node_edges bne
                JOIN core.bot_nodes bn ON bn.node_id = bne.child_node_id
                WHERE bne.parent_node_id = v_walk_node_id;

                v_has_conditions := (v_condition_nodes IS NOT NULL AND array_length(v_condition_nodes, 1) > 0);
                v_has_operations := (v_operation_nodes IS NOT NULL AND array_length(v_operation_nodes, 1) > 0);
                v_has_messages := (v_message_nodes IS NOT NULL AND array_length(v_message_nodes, 1) > 0);

                ----------------------------------------
                -- CASE A: CHILD NODES ARE CONDITIONS --
                ----------------------------------------
                IF v_has_conditions THEN
                    -- siblings are OR-branches; each sequential chain inside a sibling is AND
                    v_matched_condition_node_id := NULL;

                    -- try each condition sibling (OR); each may have a sequential chain (AND)
                    FOREACH v_first_condition_node_id IN ARRAY v_condition_nodes
                    LOOP
                        v_all_conditions_passed := true;

                        -- walk sequential condition chain from this sibling
                        WITH RECURSIVE condition_chain AS MATERIALIZED (
                            SELECT bn.node_id, bn.is_sequential
                            FROM core.bot_nodes bn
                            WHERE bn.node_id = v_first_condition_node_id

                            UNION ALL

                            SELECT bn.node_id, bn.is_sequential
                            FROM core.bot_node_edges bne
                            JOIN core.bot_nodes bn ON bn.node_id = bne.child_node_id
                            JOIN condition_chain cc ON bne.parent_node_id = cc.node_id
                            WHERE cc.is_sequential = true AND bn.node_type = 'condition'
                        )
                        SELECT ARRAY_AGG(condition_chain.node_id)
                        INTO v_array_sequential_condition_node_ids
                        FROM condition_chain;

                        IF COALESCE(array_length(v_array_sequential_condition_node_ids, 1), 0) = 0 THEN
                            v_array_sequential_condition_node_ids := ARRAY[v_first_condition_node_id];
                        END IF;

                        -- evaluate each condition in the chain
                        FOREACH v_condition_node_id_item IN ARRAY v_array_sequential_condition_node_ids
                        LOOP
                            SELECT bc.condition_type, bc.condition, bc.condition #>> '{}'
                            INTO v_condition_type, v_condition_json, v_condition_value
                            FROM core.bot_conditions bc
                            WHERE bc.node_id = v_condition_node_id_item;

                            IF v_condition_type IS NULL THEN
                                RAISE EXCEPTION USING
                                    ERRCODE = 'DB001',
                                    MESSAGE = 'condition not found for node',
                                    DETAIL  = format('node_id=%s', v_condition_node_id_item);
                            END IF;

                            v_condition_passed := false;

                            IF v_condition_type = 'type_check' THEN
                                -- compares incoming channel type, e.g. text/image/interactive
                                v_condition_passed := (a_message_type = v_condition_value);
                            ELSIF v_condition_type = 'exact_text_match' THEN
                                -- normalizes both values before compare to reduce user-input variance
                                v_condition_passed := (LOWER(TRIM(a_message_text)) = LOWER(TRIM(v_condition_value)));
                            ELSIF v_condition_type = 'boolean' THEN
                                -- generic boolean node behavior:
                                -- condition value is "true" or "false", and runtime value is read
                                -- from store.condition_result (boolean). this avoids connector-specific
                                -- hardcoding in the condition engine.
                                v_condition_expected_boolean := (LOWER(TRIM(v_condition_value)) = 'true');

                                SELECT
                                    bcsu.store #> '{condition_result}'
                                INTO v_condition_store_value
                                FROM core.bot_conversation_states_user bcsu
                                WHERE
                                    bcsu.user_id = v_user_id AND
                                    bcsu.bot_id = v_bot_id AND
                                    bcsu.is_active = true
                                ORDER BY bcsu.updated_at DESC NULLS LAST, bcsu.created_at DESC
                                LIMIT 1;

                                IF v_condition_expected_boolean THEN
                                    v_condition_passed := (
                                        v_condition_store_value IS NOT NULL AND
                                        v_condition_store_value <> 'null'::jsonb AND
                                        v_condition_store_value <> 'false'::jsonb
                                    );
                                ELSE
                                    v_condition_passed := (
                                        v_condition_store_value IS NULL OR
                                        v_condition_store_value = 'null'::jsonb OR
                                        v_condition_store_value = 'false'::jsonb
                                    );
                                END IF;
                            ELSIF v_condition_type = 'trigger' THEN
                                -- defensive guard: a trigger condition node was reached via the
                                -- user-input AND-chain. this should not happen because the child
                                -- fetch in this traverse_loop already excludes condition nodes that
                                -- have an active core.bot_node_triggers entry. if it does happen
                                -- (e.g. misconfigured chain), treat it as non-matching so the flow
                                -- takes the fallback path instead of raising "unsupported condition".
                                v_condition_passed := false;
                            ELSE
                                RAISE EXCEPTION USING
                                    ERRCODE = 'DB001',
                                    MESSAGE = 'unsupported condition type',
                                    DETAIL  = format('condition_type=%s', v_condition_type);
                            END IF;

                            IF NOT v_condition_passed THEN
                                v_all_conditions_passed := false;
                                EXIT; -- exit inner condition chain loop
                            END IF;

                            v_matched_condition_node_id := v_condition_node_id_item;
                        END LOOP;

                        -- if this sibling chain passed, stop trying other siblings
                        IF v_all_conditions_passed THEN
                            EXIT; -- exit sibling loop
                        END IF;
                    END LOOP;

                    -- no sibling matched: resolve fallback reply node
                    IF NOT v_all_conditions_passed THEN
                        -- first: explicit fallback edge from the current parent
                        SELECT bn.node_id
                        INTO v_invalid_reply_node_id
                        FROM core.bot_node_edges bne
                        JOIN core.bot_nodes bn ON bn.node_id = bne.child_node_id
                        WHERE
                            bne.parent_node_id = v_walk_node_id AND
                            bn.node_type = 'message' AND
                            COALESCE(bne.is_fallback, false) = true
                        LIMIT 1;

                        -- second: explicit fallback edge from first condition branch
                        IF v_invalid_reply_node_id IS NULL THEN
                            SELECT bn.node_id
                            INTO v_invalid_reply_node_id
                            FROM core.bot_node_edges bne
                            JOIN core.bot_nodes bn ON bn.node_id = bne.child_node_id
                            WHERE
                                bne.parent_node_id = v_condition_nodes[1] AND
                                bn.node_type = 'message' AND
                                COALESCE(bne.is_fallback, false) = true
                            LIMIT 1;
                        END IF; -- if no invalid reply node found for node: v_walk_node_id

                        IF v_invalid_reply_node_id IS NULL THEN
                            IF NOT a_is_trial THEN
                                INSERT INTO core.conversation_elements(conversation_id, element_type, is_bot, is_ticket)
                                VALUES (v_conversation_id, 'outgoing', true, false)
                                RETURNING element_id
                                INTO v_element_id;

                                INSERT INTO core.conversation_element_bot_details(element_id, node_id)
                                VALUES (v_element_id, v_walk_node_id);
                            ELSE
                                v_element_id := uuidv7();
                            END IF;

                            v_result := v_result || jsonb_build_array(
                                whatsapp.func_build_text_bot_payload(
                                    v_element_id,
                                    a_user_phone,
                                    'Invalid user input, please try again.'
                                )
                            );

                            v_skip_state_update := true;
                            v_is_ticket_operation := true;
                            EXIT traverse_loop;
                        END IF;

                        v_next_node_id := v_invalid_reply_node_id;
                        v_skip_state_update := true;
                        EXIT traverse_loop;
                    END IF; -- if no invalid reply node found for node: v_walk_node_id

                    -- conditions passed: continue traversal from matched condition
                    v_walk_node_id := v_matched_condition_node_id;
                    CONTINUE traverse_loop;

                ----------------------------------------
                -- CASE B: CHILD NODES ARE OPERATIONS/CONNECTORS --
                ----------------------------------------
                ELSIF v_has_operations THEN
                    -- walk sequential operation/connector chain
                    WITH RECURSIVE operation_chain AS MATERIALIZED (
                        SELECT bn.node_id, bn.is_sequential, 1 AS ord
                        FROM core.bot_nodes bn
                        WHERE bn.node_id = v_operation_nodes[1]

                        UNION ALL

                        SELECT bn.node_id, bn.is_sequential, oc.ord + 1
                        FROM core.bot_node_edges bne
                        JOIN core.bot_nodes bn ON bn.node_id = bne.child_node_id
                        JOIN operation_chain oc ON bne.parent_node_id = oc.node_id
                        WHERE oc.is_sequential = true AND bn.node_type IN ('operation', 'connector')
                    )
                    SELECT ARRAY_AGG(operation_chain.node_id ORDER BY operation_chain.ord)
                    INTO v_array_sequential_operation_node_ids
                    FROM operation_chain;

                    IF COALESCE(array_length(v_array_sequential_operation_node_ids, 1), 0) = 0 THEN
                        v_array_sequential_operation_node_ids := ARRAY[v_operation_nodes[1]];
                    END IF;

                    -- execute each operation in the chain
                    FOREACH v_operation_node_id_item IN ARRAY v_array_sequential_operation_node_ids
                    LOOP
                        SELECT
                            bn.node_type::text,
                            bo.operation_type,
                            bo.operation,
                            bnc.connector_type::text,
                            bnc.connector_details
                        INTO
                            v_operation_node_type,
                            v_operation_type,
                            v_operation_value,
                            v_operation_connector_type,
                            v_operation_connector_details
                        FROM core.bot_nodes bn
                        LEFT JOIN core.bot_operations bo ON bo.node_id = bn.node_id
                        LEFT JOIN core.bot_node_connectors bnc ON bnc.node_id = bn.node_id
                        WHERE bn.node_id = v_operation_node_id_item;

                        IF v_operation_node_type = 'connector' THEN
                            v_result := v_result || jsonb_build_array(
                                jsonb_build_object(
                                    'element_id', uuidv7(),
                                    'node_type', 'connector',
                                    'message_type', '',
                                    'connector', v_operation_connector_type,
                                    'connector_details', COALESCE(v_operation_connector_details, '{}'::jsonb),
                                    'store', COALESCE(
                                        (
                                            SELECT bcsu.store
                                            FROM core.bot_conversation_states_user bcsu
                                            WHERE bcsu.user_id = v_user_id AND bcsu.bot_id = v_bot_id AND bcsu.is_active = true
                                            ORDER BY bcsu.updated_at DESC NULLS LAST, bcsu.created_at DESC
                                            LIMIT 1
                                        ),
                                        (SELECT b.default_store FROM core.bots b WHERE b.bot_id = v_bot_id LIMIT 1),
                                        '{}'::jsonb
                                    )
                                )
                            );
                            v_last_operation_node_id := v_operation_node_id_item;
                            CONTINUE;
                        END IF;

                        IF v_operation_type = 'scheduler' THEN
                            IF a_is_trial OR v_is_delay_fire_trigger THEN
                                v_last_operation_node_id := v_operation_node_id_item;
                                CONTINUE;
                            END IF;

                            v_result := v_result || jsonb_build_array(
                                jsonb_build_object(
                                    'element_id', uuidv7(),
                                    'node_id', v_operation_node_id_item,
                                    'node_type', 'operation',
                                    'operation_type', 'scheduler',
                                    'operation', COALESCE(v_operation_value, '{}'::jsonb),
                                    'store', COALESCE(
                                        (
                                            SELECT bcsu.store
                                            FROM core.bot_conversation_states_user bcsu
                                            WHERE bcsu.user_id = v_user_id AND bcsu.bot_id = v_bot_id AND bcsu.is_active = true
                                            ORDER BY bcsu.updated_at DESC NULLS LAST, bcsu.created_at DESC
                                            LIMIT 1
                                        ),
                                        (SELECT b.default_store FROM core.bots b WHERE b.bot_id = v_bot_id LIMIT 1),
                                        '{}'::jsonb
                                    )
                                )
                            );
                            v_is_scheduler_operation := true;
                            v_last_operation_node_id := v_operation_node_id_item;
                            CONTINUE;
                        END IF;

                        IF v_operation_type = 'ticket' THEN
                            IF a_is_trial OR v_is_ticket_resolved_trigger THEN
                                -- trial / ticket_resolved: skip ticket lock/create side effects and continue traversal
                                v_last_operation_node_id := v_operation_node_id_item;
                                CONTINUE;
                            END IF;

                            -- ticket operation "locks" the user at this node until ticket closes
                            -- check for existing active ticket
                            SELECT cet.ticket_id
                            INTO v_ticket_id
                            FROM core.conversation_element_ticket_details cet
                            INNER JOIN core.tickets t ON t.ticket_id = cet.ticket_id
                            INNER JOIN core.conversation_elements ce ON cet.element_id = ce.element_id
                            INNER JOIN core.conversation_element_bot_details cebd ON cebd.element_id = ce.element_id
                            WHERE
                                ce.conversation_id = v_conversation_id AND
                                t.ticket_status = 'active' AND
                                cebd.node_id = v_operation_node_id_item
                            LIMIT 1;

                            IF v_ticket_id IS NULL THEN
                                IF NOT a_is_trial THEN
                                    -- create ticket + assignment using operation payload
                                    SELECT whatsapp.func_create_and_assign_ticket(
                                        v_surrogate_phone_id,
                                        v_conversation_id,
                                        v_operation_value->>'assignment_criteria',
                                        v_operation_value->>'assignment_message',
                                        true,
                                        NULLIF(v_operation_value->>'team_id', '')::UUID
                                    )
                                    INTO v_ticket_id;

                                    INSERT INTO core.ticket_bot_details(ticket_id, node_id)
                                    VALUES (v_ticket_id, v_operation_node_id_item);
                                END IF;

                                v_is_new_ticket := true;
                            END IF; -- if no active ticket found

                            -- send assignment message for new tickets
                            IF v_is_new_ticket THEN
                                IF NOT a_is_trial THEN
                                    INSERT INTO core.conversation_elements(conversation_id, element_type, is_bot, is_ticket)
                                    VALUES (v_conversation_id, 'outgoing', true, true)
                                    RETURNING element_id
                                    INTO v_element_id;

                                    INSERT INTO core.conversation_element_bot_details(element_id, node_id)
                                    VALUES (v_element_id, v_operation_node_id_item);

                                    IF v_ticket_id IS NOT NULL THEN
                                        INSERT INTO core.conversation_element_ticket_details(element_id, ticket_id)
                                        VALUES (v_element_id, v_ticket_id);
                                    END IF;
                                ELSE
                                    v_element_id := uuidv7();
                                END IF;

                                IF NOT EXISTS (
                                    SELECT 1
                                    FROM jsonb_array_elements(v_result) AS elem
                                    WHERE
                                        elem->>'message_type' = 'text' AND
                                        elem #>> '{message,text,body}' = v_operation_value->>'assignment_message'
                                ) THEN
                                    v_result := v_result || jsonb_build_array(
                                        whatsapp.func_build_text_bot_payload(
                                            v_element_id,
                                            a_user_phone,
                                            v_operation_value->>'assignment_message'
                                        )
                                    );
                                END IF;
                            ELSE
                                -- active ticket already exists: do not send user message.
                                -- keep user locked on ticket operation node only.
                            END IF; -- if no active ticket found

                            -- update state to ticket node (user is "stuck" at ticket)
                            -- this prevents bot progression while a human ticket flow is active
                            UPDATE core.bot_conversation_states_user
                            SET node_id = v_operation_node_id_item, updated_at = NOW()
                            WHERE user_id = v_user_id AND bot_id = v_bot_id AND is_active = true;

                            v_is_ticket := true;
                            v_is_ticket_operation := true;
                            EXIT traverse_loop;
                        END IF; -- if ticket operation "locks" the user at this node until ticket closes

                        -- for non-ticket operations, emit operation node so runtime worker executes it.
                        v_result := v_result || jsonb_build_array(
                            jsonb_build_object(
                                'element_id', uuidv7(),
                                'node_id', v_operation_node_id_item,
                                'node_type', 'operation',
                                'operation_type', COALESCE(v_operation_type, ''),
                                'operation', COALESCE(v_operation_value, '{}'::jsonb),
                                'store', COALESCE(
                                    (
                                        SELECT bcsu.store
                                        FROM core.bot_conversation_states_user bcsu
                                        WHERE bcsu.user_id = v_user_id AND bcsu.bot_id = v_bot_id AND bcsu.is_active = true
                                        ORDER BY bcsu.updated_at DESC NULLS LAST, bcsu.created_at DESC
                                        LIMIT 1
                                    ),
                                    (SELECT b.default_store FROM core.bots b WHERE b.bot_id = v_bot_id LIMIT 1),
                                    '{}'::jsonb
                                )
                            )
                        );
                        v_last_operation_node_id := v_operation_node_id_item;
                    END LOOP;

                    IF v_is_scheduler_operation THEN
                        UPDATE core.bot_conversation_states_user
                        SET node_id = v_last_operation_node_id, updated_at = NOW()
                        WHERE user_id = v_user_id AND bot_id = v_bot_id AND is_active = true;
                        EXIT traverse_loop;
                    END IF;

                    -- when the last emitted node is a connector or Go-executed operation whose
                    -- immediate children are conditions, park state and let workflow_continue
                    -- re-enter. connectors (e.g. zoho find_lead) and store_action operations
                    -- write condition_result in the worker; evaluating boolean branches here
                    -- would read stale store values.
                    IF v_operation_node_type IN ('connector', 'operation') AND EXISTS (
                        SELECT 1
                        FROM core.bot_node_edges bne
                        JOIN core.bot_nodes bn ON bn.node_id = bne.child_node_id
                        WHERE bne.parent_node_id = v_last_operation_node_id
                          AND bn.node_type = 'condition'
                    ) THEN
                        UPDATE core.bot_conversation_states_user
                        SET node_id = v_last_operation_node_id, updated_at = NOW()
                        WHERE user_id = v_user_id AND bot_id = v_bot_id AND is_active = true;
                        EXIT traverse_loop;
                    END IF;

                    -- non-ticket operations: continue traversal from last operation
                    v_walk_node_id := v_last_operation_node_id;
                    CONTINUE traverse_loop;

                --------------------------------------
                -- CASE C: CHILD NODES ARE MESSAGES --
                --------------------------------------
                ELSIF v_has_messages THEN
                    v_next_node_id := v_message_nodes[1];
                    EXIT traverse_loop;

                ELSE
                    -- terminal node reached: stop traversal gracefully.
                    -- do not raise DB001, otherwise upstream retries can replay from root.
                    v_next_node_id := NULL;
                    EXIT traverse_loop;
                END IF;
            END LOOP;

            -----------------------------------------------
            -- STEP 2.2: COLLECT AND SEND BOT MESSAGES   --
            -----------------------------------------------
            IF NOT v_is_ticket_operation AND v_next_node_id IS NOT NULL THEN
                -- walk sequential chain from next node
                WITH RECURSIVE node_chain AS MATERIALIZED (
                    SELECT bn.node_id, bn.is_sequential, 1 AS ord
                    FROM core.bot_nodes bn
                    WHERE bn.node_id = v_next_node_id AND bn.is_sequential = true

                    UNION ALL

                    SELECT bn.node_id, bn.is_sequential, nc.ord + 1
                    FROM core.bot_node_edges bne
                    JOIN core.bot_nodes bn ON bn.node_id = bne.child_node_id
                    JOIN node_chain nc ON bne.parent_node_id = nc.node_id
                    WHERE nc.is_sequential = true
                )
                SELECT ARRAY_AGG(node_chain.node_id ORDER BY node_chain.ord)
                INTO v_array_executable_node_ids
                FROM node_chain;

                -- if next node is not sequential, add it directly
                IF COALESCE(array_length(v_array_executable_node_ids, 1), 0) = 0 THEN
                    v_array_executable_node_ids := array_append(v_array_executable_node_ids, v_next_node_id);
                END IF;

                -- if immediate next child is ticket operation, execute it in the same run
                -- (no extra user input needed).
                -- BUT on ticket_resolved trigger, do not inline another ticket operation:
                -- we must move past the ticket-op and continue regular flow.
                v_inline_ticket_operation_node_id := NULL;
                IF NOT v_is_ticket_resolved_trigger THEN
                    SELECT bn.node_id
                    INTO v_inline_ticket_operation_node_id
                    FROM core.bot_node_edges bne
                    JOIN core.bot_nodes bn ON bn.node_id = bne.child_node_id
                    JOIN core.bot_operations bo ON bo.node_id = bn.node_id
                    WHERE
                        bne.parent_node_id = v_array_executable_node_ids[array_length(v_array_executable_node_ids, 1)] AND
                        bn.node_type = 'operation' AND
                        bo.operation_type = 'ticket'
                    LIMIT 1;

                    IF
                        v_inline_ticket_operation_node_id IS NOT NULL AND
                        array_position(v_array_executable_node_ids, v_inline_ticket_operation_node_id) IS NULL
                    THEN
                        v_array_executable_node_ids := array_append(v_array_executable_node_ids, v_inline_ticket_operation_node_id);
                    END IF;
                END IF;

                -- trial mode: also inline the immediate message node after ticket operation
                -- so state advances beyond ticket op in the same run.
                IF a_is_trial AND v_inline_ticket_operation_node_id IS NOT NULL THEN
                    SELECT bn.node_id
                    INTO v_next_node_id
                    FROM core.bot_node_edges bne
                    JOIN core.bot_nodes bn ON bn.node_id = bne.child_node_id
                    WHERE bne.parent_node_id = v_inline_ticket_operation_node_id AND bn.node_type = 'message'
                    ORDER BY bn.created_at ASC
                    LIMIT 1;

                    IF
                        v_next_node_id IS NOT NULL AND
                        array_position(v_array_executable_node_ids, v_next_node_id) IS NULL
                    THEN
                        v_array_executable_node_ids := array_append(v_array_executable_node_ids, v_next_node_id);
                    END IF;
                END IF;

                -- stop sequential chains at scheduler (nodes after it run on delay_fire)
                IF NOT a_is_trial THEN
                    SELECT ordered.node_id
                    INTO v_operation_node_id_item
                    FROM UNNEST(v_array_executable_node_ids) WITH ORDINALITY AS ordered(node_id, ord)
                    INNER JOIN core.bot_operations bo ON bo.node_id = ordered.node_id AND bo.operation_type = 'scheduler'
                    ORDER BY ordered.ord
                    LIMIT 1;

                    IF v_operation_node_id_item IS NOT NULL THEN
                        v_array_executable_node_ids := v_array_executable_node_ids[
                            1:array_position(v_array_executable_node_ids, v_operation_node_id_item)
                        ];
                        v_is_scheduler_operation := true;
                    END IF;
                END IF;

                -- determine new state node (last in chain)
                v_new_state_node_id := v_array_executable_node_ids[array_length(v_array_executable_node_ids, 1)];

                -- check if the last node is a terminal node (no children)
                SELECT NOT EXISTS (
                    SELECT 1
                    FROM core.bot_node_edges
                    WHERE parent_node_id = v_new_state_node_id
                )
                INTO v_is_last_node_executing;

                -- update state (skip for invalid reply so user can retry)
                -- on fallback/invalid-reply we keep current state unchanged intentionally
                IF NOT v_skip_state_update THEN
                    SELECT bo.operation_type
                    INTO v_new_state_operation_type
                    FROM core.bot_operations bo
                    WHERE bo.node_id = v_new_state_node_id;

                    -- terminal nodes clear state (NULL semantics via inactive row)
                    IF v_is_last_node_executing THEN
                        IF v_new_state_operation_type = 'ticket' THEN
                            -- Trial mode assumes ticket is resolved; terminate state like a terminal message node.
                            IF a_is_trial THEN
                                UPDATE core.bot_conversation_states_user
                                SET is_active = false, updated_at = NOW()
                                WHERE user_id = v_user_id AND bot_id = v_bot_id AND is_active = true;
                            ELSE
                                -- When terminal node is `ticket`, keep state locked until the resolved trigger.
                                -- (DB checks here are unreliable when the ticket operation is inlined in the same run.)
                                IF v_is_ticket_resolved_trigger THEN
                                    UPDATE core.bot_conversation_states_user
                                    SET is_active = false, updated_at = NOW()
                                    WHERE user_id = v_user_id AND bot_id = v_bot_id AND is_active = true;
                                ELSE
                                    UPDATE core.bot_conversation_states_user
                                    SET
                                        node_id = v_new_state_node_id,
                                        is_active = true,
                                        updated_at = NOW()
                                    WHERE user_id = v_user_id AND bot_id = v_bot_id AND is_active = true;
                                END IF;
                            END IF;
                        ELSE
                            UPDATE core.bot_conversation_states_user
                            SET is_active = false, updated_at = NOW()
                            WHERE user_id = v_user_id AND bot_id = v_bot_id AND is_active = true;
                        END IF;
                    ELSE
                        UPDATE core.bot_conversation_states_user
                        SET node_id = v_new_state_node_id, updated_at = NOW()
                        WHERE user_id = v_user_id AND bot_id = v_bot_id AND is_active = true;
                    END IF;
                END IF; -- update state (skip for invalid reply so user can retry)

                -- build outgoing bot response elements
                -- prefetch node metadata once for this chain to avoid repeated per-node lookups
                FOR
                    v_node_id,
                    v_executable_node_type,
                    v_operation_type,
                    v_operation_value,
                    v_prefetched_message_type,
                    v_prefetched_message_object
                IN
                    SELECT
                        bn.node_id,
                        bn.node_type::text,
                        bo.operation_type,
                        bo.operation,
                        wbn.message_type,
                        wbn.message_object
                    FROM UNNEST(v_array_executable_node_ids) WITH ORDINALITY AS ordered(node_id, ord)
                    JOIN core.bot_nodes bn ON bn.node_id = ordered.node_id
                    LEFT JOIN core.bot_operations bo ON bo.node_id = bn.node_id
                    LEFT JOIN whatsapp.bot_nodes wbn ON wbn.node_id = bn.node_id
                    ORDER BY ordered.ord
                LOOP

                    -- execute operation nodes inline (do not wait for next user message)
                    IF v_executable_node_type = 'operation' THEN
                        IF v_operation_type = 'scheduler' AND (a_is_trial OR v_is_delay_fire_trigger) THEN
                            EXIT;
                        END IF;

                        v_result := v_result || jsonb_build_array(
                            jsonb_build_object(
                                'element_id', uuidv7(),
                                'node_id', v_node_id,
                                'node_type', 'operation',
                                'operation_type', COALESCE(v_operation_type, ''),
                                'operation', COALESCE(v_operation_value, '{}'::jsonb),
                                'store', COALESCE(
                                    (
                                        SELECT bcsu.store
                                        FROM core.bot_conversation_states_user bcsu
                                        WHERE bcsu.user_id = v_user_id AND bcsu.bot_id = v_bot_id AND bcsu.is_active = true
                                        ORDER BY bcsu.updated_at DESC NULLS LAST, bcsu.created_at DESC
                                        LIMIT 1
                                    ),
                                    (SELECT b.default_store FROM core.bots b WHERE b.bot_id = v_bot_id LIMIT 1),
                                    '{}'::jsonb
                                )
                            )
                        );
                        IF v_operation_type = 'ticket' AND NOT a_is_trial THEN
                            IF v_is_ticket_resolved_trigger THEN
                                -- on ticket-resolved continuation, do not open/reopen ticket immediately.
                                NULL;
                            ELSE
                                SELECT cet.ticket_id
                                INTO v_ticket_id
                                FROM core.conversation_element_ticket_details cet
                                INNER JOIN core.tickets t ON t.ticket_id = cet.ticket_id
                                INNER JOIN core.conversation_elements ce ON cet.element_id = ce.element_id
                                INNER JOIN core.conversation_element_bot_details cebd ON cebd.element_id = ce.element_id
                                WHERE
                                    ce.conversation_id = v_conversation_id AND
                                    t.ticket_status = 'active' AND
                                    cebd.node_id = v_node_id
                                LIMIT 1;

                                IF v_ticket_id IS NULL THEN
                                    SELECT whatsapp.func_create_and_assign_ticket(
                                        v_surrogate_phone_id,
                                        v_conversation_id,
                                        v_operation_value->>'assignment_criteria',
                                        v_operation_value->>'assignment_message',
                                        true,
                                        NULLIF(v_operation_value->>'team_id', '')::UUID
                                    ) INTO v_ticket_id;

                                    INSERT INTO core.ticket_bot_details(ticket_id, node_id)
                                    VALUES (v_ticket_id, v_node_id);

                                    INSERT INTO core.conversation_elements(conversation_id, element_type, is_bot, is_ticket)
                                    VALUES (v_conversation_id, 'outgoing', true, true)
                                    RETURNING element_id
                                    INTO v_element_id;

                                    INSERT INTO core.conversation_element_bot_details(element_id, node_id)
                                    VALUES (v_element_id, v_node_id);

                                    INSERT INTO core.conversation_element_ticket_details(element_id, ticket_id)
                                    VALUES (v_element_id, v_ticket_id);

                                    IF NOT EXISTS (
                                        SELECT 1
                                        FROM jsonb_array_elements(v_result) AS elem
                                        WHERE
                                            elem->>'message_type' = 'text' AND
                                            elem #>> '{message,text,body}' = v_operation_value->>'assignment_message'
                                    ) THEN
                                        v_result := v_result || jsonb_build_array(
                                            whatsapp.func_build_text_bot_payload(
                                                v_element_id,
                                                a_user_phone,
                                                v_operation_value->>'assignment_message'
                                            )
                                        );
                                    END IF;
                                END IF;
                            END IF;
                        END IF;
                        CONTINUE;
                    END IF;

                    IF NOT a_is_trial THEN
                        INSERT INTO core.conversation_elements(conversation_id, element_type, is_bot, is_ticket)
                        VALUES (v_conversation_id, 'outgoing', true, false)
                        RETURNING element_id
                        INTO v_element_id;

                        INSERT INTO core.conversation_element_bot_details(element_id, node_id)
                        VALUES (v_element_id, v_node_id);
                    ELSE
                        v_element_id := uuidv7();
                    END IF; -- if not trial flow

                    IF v_prefetched_message_object IS NOT NULL THEN
                        v_message_object := jsonb_build_object(
                            'element_id', v_element_id,
                            'node_id', v_node_id,
                            'node_type', 'message',
                            'message_type', v_prefetched_message_type,
                            -- template nodes: keep stored 'to' when set; all others use inbound user phone
                            'message', CASE
                                WHEN v_prefetched_message_object->>'type' = 'template' AND COALESCE(v_prefetched_message_object->>'to', '') <> ''
                                THEN jsonb_set(v_prefetched_message_object, '{to}', to_jsonb(v_prefetched_message_object->>'to'))
                                ELSE jsonb_set(v_prefetched_message_object, '{to}', to_jsonb(a_user_phone::TEXT))
                            END,
                            'store', COALESCE(
                                (
                                    SELECT bcsu.store
                                    FROM core.bot_conversation_states_user bcsu
                                    WHERE bcsu.user_id = v_user_id AND bcsu.bot_id = v_bot_id AND bcsu.is_active = true
                                    ORDER BY bcsu.updated_at DESC NULLS LAST, bcsu.created_at DESC
                                    LIMIT 1
                                ),
                                (SELECT b.default_store FROM core.bots b WHERE b.bot_id = v_bot_id LIMIT 1),
                                '{}'::jsonb
                            )
                        );
                    ELSE
                        v_message_object := NULL;
                    END IF;

                    IF v_message_object IS NOT NULL THEN
                        v_result := v_result || jsonb_build_array(v_message_object);
                    END IF;
                END LOOP;

                v_is_ticket := false;
            END IF;
        ELSE
            -- ticket is ongoing and current state is the ticket operation node:
            -- keep user locked at current node and do not advance traversal/state.
            UPDATE core.bot_conversation_states_user
            SET node_id = v_current_node_id, updated_at = NOW()
            WHERE user_id = v_user_id AND bot_id = v_bot_id AND is_active = true;

            IF NOT v_is_new_ticket THEN
                -- ticket is ongoing at current ticket node: do not send user message.
                -- state remains locked on the ticket node until ticket resolves.
            END IF;
        END IF; -- NOT v_is_ticket (active ticket check)

    -----------------------------------------------------------------------
    -- STEP 4: BOT ON PHONE AND NO ACTIVE STATE (OR DIFFERENT BOT STATE) --
    -----------------------------------------------------------------------
    ELSIF v_bot_id IS NOT NULL AND (v_state_bot_id IS NULL OR v_bot_id != v_state_bot_id) THEN

        -- deactivate old state if it exists for a different bot
        IF NOT a_is_trial AND v_state_bot_id IS NOT NULL AND v_bot_id != v_state_bot_id THEN
            UPDATE core.bot_conversation_states_user
            SET is_active = false, updated_at = NOW()
            WHERE user_id = v_user_id AND is_active = true;
        END IF;

        -- node-scoped trigger: if a trigger_node_id was passed in and that node belongs to
        -- the resolved bot, start the sequential walk from that node instead of the bot's
        -- parent-less root. this lets one bot expose multiple entry points (one per trigger).
        IF v_forced_trigger_node_id IS NOT NULL THEN
            SELECT bn.node_id
            INTO v_root_node_id
            FROM core.bot_nodes bn
            WHERE bn.node_id = v_forced_trigger_node_id AND bn.bot_id = v_bot_id
            LIMIT 1;
        END IF;

        -- fallback: find root node of the active bot (node with no parent edge; exclude webhook trigger nodes)
        IF v_root_node_id IS NULL THEN
            SELECT bn.node_id
            INTO v_root_node_id
            FROM core.bot_nodes bn
            WHERE bn.bot_id = v_bot_id
                AND NOT EXISTS (
                    SELECT 1
                    FROM core.bot_node_edges bne
                    WHERE bne.child_node_id = bn.node_id
                )
                AND NOT EXISTS (
                    SELECT 1
                    FROM core.bot_node_triggers bnt
                    WHERE bnt.node_id = bn.node_id AND bnt.is_active = true
                )
            ORDER BY bn.created_at ASC
            LIMIT 1;
        END IF;

        IF v_root_node_id IS NULL THEN
            RAISE EXCEPTION USING
                ERRCODE = 'DB001',
                MESSAGE = 'root node not found for bot',
                DETAIL  = format('bot_id=%s', v_bot_id);
        END IF;

        -- walk sequential chain from the root node
        WITH RECURSIVE node_chain AS MATERIALIZED (
            SELECT bn.node_id, bn.is_sequential, 1 AS ord
            FROM core.bot_nodes bn
            WHERE bn.node_id = v_root_node_id AND bn.is_sequential = true

            UNION ALL

            SELECT bn.node_id, bn.is_sequential, nc.ord + 1
            FROM core.bot_node_edges bne
            JOIN core.bot_nodes bn ON bn.node_id = bne.child_node_id
            JOIN node_chain nc ON bne.parent_node_id = nc.node_id
            WHERE nc.is_sequential = true
        )
        SELECT ARRAY_AGG(node_chain.node_id ORDER BY node_chain.ord)
        INTO v_array_executable_node_ids
        FROM node_chain;

        -- if root node is not sequential, add it directly
        IF COALESCE(array_length(v_array_executable_node_ids, 1), 0) = 0 THEN
            v_array_executable_node_ids := array_append(v_array_executable_node_ids, v_root_node_id);
        END IF;

        -- if immediate next child is ticket operation, execute it in the same run
        -- (no extra user input needed).
        -- on ticket_resolved trigger, never inline ticket operation nodes.
        v_inline_ticket_operation_node_id := NULL;
        IF NOT v_is_ticket_resolved_trigger THEN
            SELECT bn.node_id
            INTO v_inline_ticket_operation_node_id
            FROM core.bot_node_edges bne
            JOIN core.bot_nodes bn ON bn.node_id = bne.child_node_id
            JOIN core.bot_operations bo ON bo.node_id = bn.node_id
            WHERE
                bne.parent_node_id = v_array_executable_node_ids[array_length(v_array_executable_node_ids, 1)] AND
                bn.node_type = 'operation' AND
                bo.operation_type = 'ticket'
            LIMIT 1;

            IF
                v_inline_ticket_operation_node_id IS NOT NULL AND
                array_position(v_array_executable_node_ids, v_inline_ticket_operation_node_id) IS NULL
            THEN
                v_array_executable_node_ids := array_append(v_array_executable_node_ids, v_inline_ticket_operation_node_id);
            END IF;
        END IF;

        -- trial mode: also inline the immediate message node after ticket operation
        -- so state advances beyond ticket op in the same run.
        IF a_is_trial AND v_inline_ticket_operation_node_id IS NOT NULL THEN
            SELECT bn.node_id
            INTO v_next_node_id
            FROM core.bot_node_edges bne
            JOIN core.bot_nodes bn ON bn.node_id = bne.child_node_id
            WHERE bne.parent_node_id = v_inline_ticket_operation_node_id AND bn.node_type = 'message'
            ORDER BY bn.created_at ASC
            LIMIT 1;

            IF
                v_next_node_id IS NOT NULL AND
                array_position(v_array_executable_node_ids, v_next_node_id) IS NULL
            THEN
                v_array_executable_node_ids := array_append(v_array_executable_node_ids, v_next_node_id);
            END IF;
        END IF;

        -- stop sequential chains at scheduler (nodes after it run on delay_fire)
        IF NOT a_is_trial THEN
            SELECT ordered.node_id
            INTO v_operation_node_id_item
            FROM UNNEST(v_array_executable_node_ids) WITH ORDINALITY AS ordered(node_id, ord)
            INNER JOIN core.bot_operations bo ON bo.node_id = ordered.node_id AND bo.operation_type = 'scheduler'
            ORDER BY ordered.ord
            LIMIT 1;

            IF v_operation_node_id_item IS NOT NULL THEN
                v_array_executable_node_ids := v_array_executable_node_ids[
                    1:array_position(v_array_executable_node_ids, v_operation_node_id_item)
                ];
                v_is_scheduler_operation := true;
            END IF;
        END IF;

        -- new state points to last node in chain
        v_new_state_node_id := v_array_executable_node_ids[array_length(v_array_executable_node_ids, 1)];

        -- if initial chain ends at terminal, clear state unless terminal node is ticket-op
        SELECT NOT EXISTS (
            SELECT 1
            FROM core.bot_node_edges
            WHERE parent_node_id = v_new_state_node_id
        )
        INTO v_is_last_node_executing;

        SELECT bo.operation_type
        INTO v_new_state_operation_type
        FROM core.bot_operations bo
        WHERE bo.node_id = v_new_state_node_id;

        IF v_is_last_node_executing THEN
            -- do not clear state when terminal node is a ticket operation and we are not on the
            -- ticket-resolved trigger; user must stay locked while ticket is open.
            IF v_new_state_operation_type = 'ticket' THEN
                IF a_is_trial THEN
                    UPDATE core.bot_conversation_states_user
                    SET is_active = false, updated_at = NOW()
                    WHERE user_id = v_user_id AND bot_id = v_bot_id AND is_active = true;
                ELSE
                    IF v_is_ticket_resolved_trigger THEN
                        UPDATE core.bot_conversation_states_user
                        SET is_active = false, updated_at = NOW()
                        WHERE user_id = v_user_id AND bot_id = v_bot_id AND is_active = true;
                    ELSE
                        INSERT INTO core.bot_conversation_states_user(bot_id, node_id, user_id, store, is_active)
                        VALUES (
                            v_bot_id,
                            v_new_state_node_id,
                            v_user_id,
                            COALESCE(
                                (SELECT b.default_store FROM core.bots b WHERE b.bot_id = v_bot_id LIMIT 1),
                                '{}'::jsonb
                            ),
                            true
                        )
                        ON CONFLICT (bot_id, user_id)
                        WHERE is_active = true
                        DO UPDATE
                        SET
                            node_id = EXCLUDED.node_id,
                            store = COALESCE(core.bot_conversation_states_user.store, EXCLUDED.store),
                            updated_at = NOW();
                    END IF;
                END IF;
            ELSE
                UPDATE core.bot_conversation_states_user
                SET is_active = false, updated_at = NOW()
                WHERE user_id = v_user_id AND bot_id = v_bot_id AND is_active = true;
            END IF;
        ELSE
            -- create/update conversation state entry for non-terminal wait points
            INSERT INTO core.bot_conversation_states_user(bot_id, node_id, user_id, store, is_active)
            VALUES (
                v_bot_id,
                v_new_state_node_id,
                v_user_id,
                COALESCE(
                    (SELECT b.default_store FROM core.bots b WHERE b.bot_id = v_bot_id LIMIT 1),
                    '{}'::jsonb
                ),
                true
            )
            ON CONFLICT (bot_id, user_id)
            WHERE is_active = true
            DO UPDATE
            SET
                node_id = EXCLUDED.node_id,
                store = COALESCE(core.bot_conversation_states_user.store, EXCLUDED.store),
                updated_at = NOW();
        END IF;

        -- build outgoing bot response elements
        -- prefetch node metadata once for this chain to avoid repeated per-node lookups
        FOR
            v_node_id,
            v_executable_node_type,
            v_operation_type,
            v_operation_value,
            v_prefetched_message_type,
            v_prefetched_message_object,
            v_prefetched_connector_type,
            v_prefetched_connector_details
        IN
            SELECT
                bn.node_id,
                bn.node_type::text,
                bo.operation_type,
                bo.operation,
                wbn.message_type,
                wbn.message_object,
                bnc.connector_type::text,
                bnc.connector_details
            FROM UNNEST(v_array_executable_node_ids) WITH ORDINALITY AS ordered(node_id, ord)
            JOIN core.bot_nodes bn ON bn.node_id = ordered.node_id
            LEFT JOIN core.bot_operations bo ON bo.node_id = bn.node_id
            LEFT JOIN whatsapp.bot_nodes wbn ON wbn.node_id = bn.node_id
            LEFT JOIN core.bot_node_connectors bnc ON bnc.node_id = bn.node_id
            ORDER BY ordered.ord
        LOOP

            -- execute operation nodes inline (do not wait for next user message)
            IF v_executable_node_type = 'operation' THEN
                IF v_operation_type = 'scheduler' AND (a_is_trial OR v_is_delay_fire_trigger) THEN
                    EXIT;
                END IF;

                v_result := v_result || jsonb_build_array(
                    jsonb_build_object(
                        'element_id', uuidv7(),
                        'node_id', v_node_id,
                        'node_type', 'operation',
                        'operation_type', COALESCE(v_operation_type, ''),
                        'operation', COALESCE(v_operation_value, '{}'::jsonb),
                        'store', COALESCE(
                            (
                                SELECT bcsu.store
                                FROM core.bot_conversation_states_user bcsu
                                WHERE bcsu.user_id = v_user_id AND bcsu.bot_id = v_bot_id AND bcsu.is_active = true
                                ORDER BY bcsu.updated_at DESC NULLS LAST, bcsu.created_at DESC
                                LIMIT 1
                            ),
                            (SELECT b.default_store FROM core.bots b WHERE b.bot_id = v_bot_id LIMIT 1),
                            '{}'::jsonb
                        )
                    )
                );
                IF v_operation_type = 'ticket' AND NOT a_is_trial THEN
                    IF v_is_ticket_resolved_trigger THEN
                        -- on ticket-resolved continuation, do not open/reopen ticket immediately.
                        NULL;
                    ELSE
                        SELECT cet.ticket_id
                        INTO v_ticket_id
                        FROM core.conversation_element_ticket_details cet
                        INNER JOIN core.tickets t ON t.ticket_id = cet.ticket_id
                        INNER JOIN core.conversation_elements ce ON cet.element_id = ce.element_id
                        INNER JOIN core.conversation_element_bot_details cebd ON cebd.element_id = ce.element_id
                        WHERE
                            ce.conversation_id = v_conversation_id AND
                            t.ticket_status = 'active' AND
                            cebd.node_id = v_node_id
                        LIMIT 1;

                        IF v_ticket_id IS NULL THEN
                            SELECT whatsapp.func_create_and_assign_ticket(
                                v_surrogate_phone_id,
                                v_conversation_id,
                                v_operation_value->>'assignment_criteria',
                                v_operation_value->>'assignment_message',
                                true,
                                NULLIF(v_operation_value->>'team_id', '')::UUID
                            ) INTO v_ticket_id;

                            INSERT INTO core.ticket_bot_details(ticket_id, node_id)
                            VALUES (v_ticket_id, v_node_id);

                            INSERT INTO core.conversation_elements(conversation_id, element_type, is_bot, is_ticket)
                            VALUES (v_conversation_id, 'outgoing', true, true)
                            RETURNING element_id
                            INTO v_element_id;

                            INSERT INTO core.conversation_element_bot_details(element_id, node_id)
                            VALUES (v_element_id, v_node_id);

                            INSERT INTO core.conversation_element_ticket_details(element_id, ticket_id)
                            VALUES (v_element_id, v_ticket_id);

                            IF NOT EXISTS (
                                SELECT 1
                                FROM jsonb_array_elements(v_result) AS elem
                                WHERE
                                    elem->>'message_type' = 'text' AND
                                    elem #>> '{message,text,body}' = v_operation_value->>'assignment_message'
                            ) THEN
                                v_result := v_result || jsonb_build_array(
                                    whatsapp.func_build_text_bot_payload(
                                        v_element_id,
                                        a_user_phone,
                                        v_operation_value->>'assignment_message'
                                    )
                                );
                            END IF;
                        END IF;
                    END IF;
                END IF;
                CONTINUE;
            END IF;

            IF v_executable_node_type = 'connector' THEN
                v_element_id := uuidv7();
                v_result := v_result || jsonb_build_array(
                    jsonb_build_object(
                        'element_id', v_element_id,
                        'node_type', 'connector',
                        'connector', v_prefetched_connector_type,
                        'connector_details', COALESCE(v_prefetched_connector_details, '{}'::jsonb),
                        'store', COALESCE(
                            (
                                SELECT bcsu.store
                                FROM core.bot_conversation_states_user bcsu
                                WHERE bcsu.user_id = v_user_id AND bcsu.bot_id = v_bot_id AND bcsu.is_active = true
                                ORDER BY bcsu.updated_at DESC NULLS LAST, bcsu.created_at DESC
                                LIMIT 1
                            ),
                            (SELECT b.default_store FROM core.bots b WHERE b.bot_id = v_bot_id LIMIT 1),
                            '{}'::jsonb
                        )
                    )
                );
                CONTINUE;
            END IF;

            -- condition nodes in the executable chain are trigger-entry passthroughs
            -- (they have no message body and no bot_conditions row); skip without emitting
            -- a conversation_element so the trigger node leaves no dangling artifact.
            IF v_executable_node_type = 'condition' THEN
                CONTINUE;
            END IF;

            IF NOT a_is_trial THEN
                INSERT INTO core.conversation_elements(conversation_id, element_type, is_bot, is_ticket)
                VALUES (v_conversation_id, 'outgoing', true, false)
                RETURNING element_id
                INTO v_element_id;

                INSERT INTO core.conversation_element_bot_details(element_id, node_id)
                VALUES (v_element_id, v_node_id);
            ELSE
                v_element_id := uuidv7();
            END IF;

            IF v_prefetched_message_object IS NOT NULL THEN
                v_message_object := jsonb_build_object(
                    'element_id', v_element_id,
                    'node_id', v_node_id,
                    'node_type', 'message',
                    'message_type', v_prefetched_message_type,
                    -- template nodes: keep stored 'to' when set; all others use inbound user phone
                    'message', CASE
                        WHEN v_prefetched_message_object->>'type' = 'template' AND COALESCE(v_prefetched_message_object->>'to', '') <> ''
                        THEN jsonb_set(v_prefetched_message_object, '{to}', to_jsonb(v_prefetched_message_object->>'to'))
                        ELSE jsonb_set(v_prefetched_message_object, '{to}', to_jsonb(a_user_phone::TEXT))
                    END,
                    'store', COALESCE(
                        (
                            SELECT bcsu.store
                            FROM core.bot_conversation_states_user bcsu
                            WHERE bcsu.user_id = v_user_id AND bcsu.bot_id = v_bot_id AND bcsu.is_active = true
                            ORDER BY bcsu.updated_at DESC NULLS LAST, bcsu.created_at DESC
                            LIMIT 1
                        ),
                        (SELECT b.default_store FROM core.bots b WHERE b.bot_id = v_bot_id LIMIT 1),
                        '{}'::jsonb
                    )
                );
            ELSE
                v_message_object := NULL;
            END IF;

            IF v_message_object IS NOT NULL THEN
                v_result := v_result || jsonb_build_array(v_message_object);
            END IF;
        END LOOP;

        v_is_ticket := false;

    ---------------------------------------------------
    -- STEP 5: NO BOT ON PHONE, ACTIVE TICKET EXISTS --
    ---------------------------------------------------
    ELSIF v_bot_id IS NULL THEN

        -- look up active ticket for this user
        SELECT t.ticket_id
        INTO v_ticket_id
        FROM core.ticket_participant_singles tps
        JOIN core.tickets t ON t.ticket_id = tps.ticket_id
        WHERE
            tps.user_id = v_user_id AND
            t.ticket_status = 'active' AND
            t.platform = 'whatsapp'::core.platform AND
            t.organization_id = v_organization_id
        ORDER BY t.created_at DESC
        LIMIT 1;

        IF v_ticket_id IS NOT NULL THEN
            -- BRANCH C: active ticket found
            v_is_ticket := true;
        ELSE
            -- BRANCH D: no bot, no ticket
            v_is_ticket := false;
        END IF;

    END IF; -- if no bot on phone, active ticket found

    --------------------------
    -- STEP 6: FINAL RETURN --
    --------------------------
    RETURN JSONB_STRIP_NULLS(v_result);
END;
$$
LANGUAGE plpgsql;
-- +goose StatementEnd


-- +goose Down
DROP FUNCTION IF EXISTS whatsapp.func_whatsapp_process_message;
DROP FUNCTION IF EXISTS whatsapp.func_build_text_bot_payload;
DROP FUNCTION IF EXISTS whatsapp.func_create_and_assign_ticket;
DROP FUNCTION IF EXISTS whatsapp.func_reassign_ticket;
DROP FUNCTION IF EXISTS whatsapp.func_upsert_whatsapp_user;