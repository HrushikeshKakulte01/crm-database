-- +goose Up
-- +goose StatementBegin
CREATE TABLE IF NOT EXISTS core.countries(
    country_id INTEGER PRIMARY KEY,
    country_name TEXT NOT NULL
);
-- insert a few countries during migration
INSERT INTO core.countries(country_id, country_name) VALUES
(1, 'India'),
(2, 'US'),
(3, 'UK'),
(4, 'Germany');
-- +goose StatementEnd

-- +goose StatementBegin
-- geographical states of a country
CREATE TABLE IF NOT EXISTS core.states(
    state_id INTEGER PRIMARY KEY,
    country_id INTEGER NOT NULL REFERENCES core.countries(country_id),
    state_name TEXT NOT NULL
);
-- insert states of India during migration
INSERT INTO core.states(state_id, country_id, state_name) VALUES
(1,  1, 'Andhra Pradesh'),
(2,  1, 'Arunachal Pradesh'),
(3,  1, 'Assam'),
(4,  1, 'Bihar'),
(5,  1, 'Chhattisgarh'),
(6,  1, 'Goa'),
(7,  1, 'Gujarat'),
(8,  1, 'Haryana'),
(9,  1, 'Himachal Pradesh'),
(10, 1, 'Jharkhand'),
(11, 1, 'Karnataka'),
(12, 1, 'Kerala'),
(13, 1, 'Madhya Pradesh'),
(14, 1, 'Maharashtra'),
(15, 1, 'Manipur'),
(16, 1, 'Meghalaya'),
(17, 1, 'Mizoram'),
(18, 1, 'Nagaland'),
(19, 1, 'Odisha'),
(20, 1, 'Punjab'),
(21, 1, 'Rajasthan'),
(22, 1, 'Sikkim'),
(23, 1, 'Tamil Nadu'),
(24, 1, 'Telangana'),
(25, 1, 'Tripura'),
(26, 1, 'Uttar Pradesh'),
(27, 1, 'Uttarakhand'),
(28, 1, 'West Bengal'),
(29, 1, 'Andaman and Nicobar Islands'),
(30, 1, 'Chandigarh'),
(31, 1, 'Dadra and Nagar Haveli and Daman and Diu'),
(32, 1, 'Delhi'),
(33, 1, 'Jammu and Kashmir'),
(34, 1, 'Ladakh'),
(35, 1, 'Lakshadweep'),
(36, 1, 'Puducherry');
-- +goose StatementEnd

-- +goose StatementBegin
-- frontend theme colors for the organization
CREATE TABLE IF NOT EXISTS core.frontend_themes(
    theme_id UUID PRIMARY KEY DEFAULT uuidv7(),
    theme_name TEXT NOT NULL UNIQUE,
    theme_object JSONB NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
-- insert initial frontend theme colors during migration
INSERT INTO core.frontend_themes(theme_name, theme_object) VALUES
-- 'default' (blue) colour theme
(
    'default',
    '{
        "web": {
            "primary_1": "#1D4ED8",
            "primary_2": "#93C5FD",
            "primary_3": "#DBEAFE",
            "secondary_1": "#1D4ED8",
            "secondary_2": "#BFDBFE",
            "nav_icons": "#0F172A",
            "primary_button_text": "#FFFFFF",
            "icon_whatsapp_primary": "#0d9488"
        },
        "mobile": {
            "layer_1": "#EFF6FF",
            "layer_2": "#BFDBFF",
            "primary": "#1D4ED8",
            "on_primary": "#FFFFFF",
            "secondary_1": "#1E3A8A",
            "secondary_2": "#2C2C2C"
        }
    }'
),
-- 'red-blue' colour theme
(
    'red-blue',
    '{
        "web": {
            "primary_1": "#2C2C2C",
            "primary_2": "#FB7185",
            "primary_3": "#9F1239",
            "secondary_1": "#1D4ED8",
            "secondary_2": "#E8E8E8",
            "nav_icons": "#FFFFFF",
            "primary_button_text": "#FFFFFF",
            "icon_whatsapp_primary": "#0d9488"
        },
        "mobile": {
            "layer_1": "#FEF2F2",
            "layer_2": "#FCA5A5",
            "primary": "#2C2C2C",
            "on_primary": "#FFFFFF",
            "secondary_1": "#2C2C2C",
            "secondary_2": "#2C2C2C"
        }
    }'
),
-- 'yellow' colour theme
(
    'yellow',
    '{
        "web": {
            "primary_1": "#FACC15",
            "primary_2": "#FDE08A",
            "primary_3": "#FEF9C3",
            "secondary_1": "#713F12",
            "secondary_2": "#FFF2B1",
            "nav_icons": "#713F12",
            "primary_button_text": "#713F12",
            "icon_whatsapp_primary": "#0d9488"
        },
        "mobile": {
            "layer_1": "#FEFCE8",
            "layer_2": "#FDE08A",
            "primary": "#FACC15",
            "on_primary": "#713F12",
            "secondary_1": "#713F12",
            "secondary_2": "#713F12"
        }
    }'
),
-- 'green' colour theme
(
    'green',
    '{
        "web": {
            "primary_1": "#166534",
            "primary_2": "#F0FDF4",
            "primary_3": "#C7EBCE",
            "secondary_1": "#15803D",
            "secondary_2": "#D9F2DC",
            "nav_icons": "#166534",
            "primary_button_text": "#FFFFFF",
            "icon_whatsapp_primary": "#0d9488"
        },
        "mobile": {
            "layer_1": "#F0FDF4",
            "layer_2": "#C7EBCE",
            "primary": "#166534",
            "on_primary": "#FFFFFF",
            "secondary_1": "#166534",
            "secondary_2": "#166534"
        }
    }'
),
-- 'pink' colour theme
(
    'pink',
    '{
        "web": {
            "primary_1": "#E4097F",
            "primary_2": "#FEB1CA",
            "primary_3": "#FFECF1",
            "secondary_1": "#640134",
            "secondary_2": "#FFD9E4",
            "nav_icons": "#4E3844",
            "primary_button_text": "#FFFFFF",
            "icon_whatsapp_primary": "#0d9488"
        },
        "mobile": {
            "layer_1": "#FDF2F8",
            "layer_2": "#FEB1CA",
            "primary": "#E4097F",
            "on_primary": "#FFFFFF",
            "secondary_1": "#4E3844",
            "secondary_2": "#4E3844"
        }
    }'
),
-- 'orange' colour theme
(
    'orange',
    '{
        "web": {
            "primary_1": "#FB923C",
            "primary_2": "#FDBA74",
            "primary_3": "#FFEDD5",
            "secondary_1": "#571E0B",
            "secondary_2": "#FED7AA",
            "nav_icons": "#571E0B",
            "primary_button_text": "#571E0B",
            "icon_whatsapp_primary": "#0d9488"
        },
        "mobile": {
            "layer_1": "#FFF7ED",
            "layer_2": "#FDBA74",
            "primary": "#571E0B",
            "on_primary": "#FFFFFF",
            "secondary_1": "#571E0B",
            "secondary_2": "#571E0B"
        }
    }'
);
-- +goose StatementEnd


-- +goose Down
DROP TABLE IF EXISTS core.frontend_themes;
DROP TABLE IF EXISTS core.states;
DROP TABLE IF EXISTS core.countries;