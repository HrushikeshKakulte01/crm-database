-- +goose Up
-- agent bridge devices
CREATE TABLE IF NOT EXISTS wamd.agent_bridge_devices(
    agent_id UUID PRIMARY KEY REFERENCES core.agents(agent_id),
    current_whatsapp_jid VARCHAR(255) UNIQUE,
    is_connected BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- +goose StatementBegin
-- handle event when a new whatsapp device is registered for an agent
CREATE OR REPLACE FUNCTION wamd.function_agent_bridge_new_device_registered(
    a_agent_id UUID,
    a_whatsapp_jid VARCHAR(255)
)
RETURNS void AS $$
DECLARE
    v_agent_name VARCHAR(100);
    v_agent_phone VARCHAR(20);
    v_organization_id UUID;
    v_log_message TEXT;
BEGIN
    -- fetch agent details
    SELECT agent_name, phone, organization_id
    INTO v_agent_name, v_agent_phone, v_organization_id
    FROM core.agents
    WHERE agent_id = a_agent_id;

    -- insert device or update on conflict
    -- is_connected = true on conflict too: re-registering (e.g. re-pairing
    -- after a prior logout/ban left is_connected = false) previously left it
    -- stale until a later, separate Connected event corrected it
    INSERT INTO wamd.agent_bridge_devices(agent_id, current_whatsapp_jid)
    VALUES (a_agent_id, a_whatsapp_jid)
    ON CONFLICT (agent_id)
    DO UPDATE
    SET
        current_whatsapp_jid = a_whatsapp_jid,
        is_connected = true,
        updated_at = NOW();

    -- create log message
    v_log_message := 'new whatsapp device registered for agent with name: ' || v_agent_name || ' and phone: ' || v_agent_phone;

    -- insert log for the event
    INSERT INTO wamd.organization_logs(organization_id, agent_id, event_type, event_log)
    VALUES (v_organization_id, a_agent_id, 'agent-device-registered', v_log_message);
END;
$$ LANGUAGE plpgsql;

-- handle event when an agent is connected to the whatsapp server
CREATE OR REPLACE FUNCTION wamd.function_agent_bridge_event_connected(
    a_agent_id UUID,
    a_whatsapp_jid VARCHAR(255)
)
RETURNS void AS $$
DECLARE
    v_agent_name VARCHAR(100);
    v_agent_phone VARCHAR(20);
    v_organization_id UUID;
    v_log_message TEXT;
BEGIN
    -- fetch agent details
    SELECT agent_name, phone, organization_id
    INTO v_agent_name, v_agent_phone, v_organization_id
    FROM core.agents
    WHERE agent_id = a_agent_id;

    -- set log message
    v_log_message := 'whatsapp device connected for agent with name: ' || v_agent_name || ' and phone: ' || v_agent_phone;

    -- insert connection log
    INSERT INTO wamd.organization_logs(organization_id, agent_id, event_type, event_log)
    VALUES (v_organization_id, a_agent_id, 'agent-device-connected', v_log_message);

    -- update the firm connection status
    -- do not update current whatsapp jid as the agent is connecting
    -- not registering a new device
    UPDATE wamd.agent_bridge_devices
    SET
        current_whatsapp_jid = a_whatsapp_jid,
        is_connected = true,
        updated_at = NOW()
    WHERE agent_id = a_agent_id;
END;
$$ LANGUAGE plpgsql;

-- handle event when a qr code is paired with an agent
CREATE OR REPLACE FUNCTION wamd.function_agent_bridge_event_disconnected(
    a_agent_id UUID,
    a_whatsapp_jid VARCHAR(255)
)
RETURNS void AS $$
DECLARE
    v_agent_name VARCHAR(100);
    v_agent_phone VARCHAR(20);
    v_organization_id UUID;
    v_log_message TEXT;
BEGIN
    -- fetch agent details
    SELECT agent_name, phone, organization_id
    INTO v_agent_name, v_agent_phone, v_organization_id
    FROM core.agents
    WHERE agent_id = a_agent_id;

    -- create log message
    v_log_message := 'whatsapp device disconnected for agent with name: ' || v_agent_name
        || ' and phone: ' || v_agent_phone;

    -- insert disconnection log
    INSERT INTO wamd.organization_logs(organization_id, agent_id, event_type, event_log)
    VALUES (v_organization_id, a_agent_id, 'agent-device-disconnected', v_log_message);

    -- update agent connection status (set to disconnected)
    -- do not set current whatsapp jid to NULL
    -- as the agent is disconnected, not logged out
    UPDATE wamd.agent_bridge_devices
    SET
        is_connected = false,
        updated_at = NOW()
    WHERE agent_id = a_agent_id;
END;
$$ LANGUAGE plpgsql;

-- handle event when an agent logs out
CREATE OR REPLACE FUNCTION wamd.function_agent_bridge_event_logout(
    a_agent_id UUID,
    a_whatsapp_jid VARCHAR(255)
)
RETURNS void AS $$
DECLARE
    v_agent_name VARCHAR(100);
    v_agent_phone VARCHAR(20);
    v_organization_id UUID;
    v_log_message TEXT;
BEGIN
    -- fetch agent details
    SELECT agent_name, phone, organization_id
    INTO v_agent_name, v_agent_phone, v_organization_id
    FROM core.agents
    WHERE agent_id = a_agent_id;

    -- create log message
    v_log_message := 'whatsapp device logged out for agent with name: ' || v_agent_name || ' and phone: ' || v_agent_phone;

    -- insert logout log
    INSERT INTO wamd.organization_logs(organization_id, agent_id, event_type, event_log)
    VALUES (v_organization_id, a_agent_id, 'agent-device-logged-out', v_log_message);

    -- update the agent connection status
    -- and set current whatsapp jid to NULL
    UPDATE wamd.agent_bridge_devices
    SET
        is_connected = false,
        current_whatsapp_jid = NULL,
        updated_at = NOW()
    WHERE agent_id = a_agent_id;
END;
$$ LANGUAGE plpgsql;

-- handle event when an agent is temporarily banned
CREATE OR REPLACE FUNCTION wamd.function_agent_bridge_event_temporary_banned(
    a_agent_id UUID,
    a_whatsapp_jid VARCHAR(255)
)
RETURNS void AS $$
DECLARE
    v_agent_name VARCHAR(100);
    v_agent_phone VARCHAR(20);
    v_organization_id UUID;
    v_log_message TEXT;
BEGIN
    -- fetch agent details
    SELECT agent_name, phone, organization_id
    INTO v_agent_name, v_agent_phone, v_organization_id
    FROM core.agents
    WHERE agent_id = a_agent_id;

    -- create log message
    v_log_message := 'device temporarily banned for agent with name: ' || v_agent_name || ' and phone: ' || v_agent_phone;

    -- insert temporary ban log
    INSERT INTO wamd.organization_logs(organization_id, agent_id, event_type, event_log)
    VALUES (v_organization_id, a_agent_id, 'agent-device-temporary-banned', v_log_message);

    -- update the agent connection status
    -- and set current whatsapp jid to NULL
    UPDATE wamd.agent_bridge_devices
    SET
        is_connected = false,
        current_whatsapp_jid = NULL,
        updated_at = NOW()
    WHERE agent_id = a_agent_id;
END;
$$ LANGUAGE plpgsql;
-- +goose StatementEnd


-- +goose Down
DROP FUNCTION IF EXISTS wamd.function_agent_bridge_event_temporary_banned;
DROP FUNCTION IF EXISTS wamd.function_agent_bridge_event_logout;
DROP FUNCTION IF EXISTS wamd.function_agent_bridge_event_disconnected;
DROP FUNCTION IF EXISTS wamd.function_agent_bridge_event_connected;
DROP FUNCTION IF EXISTS wamd.function_agent_bridge_new_device_registered;
DROP TABLE IF EXISTS wamd.agent_bridge_devices;