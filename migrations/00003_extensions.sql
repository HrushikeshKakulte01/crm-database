-- +goose Up
-- case insensitive character string type
-- used to store emails, user attributes, template language codes, etc
CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA extensions;

-- pg_partman for automatic partition management
CREATE EXTENSION IF NOT EXISTS pg_partman WITH SCHEMA partman;


-- +goose Down
DROP EXTENSION IF EXISTS pg_partman;
DROP EXTENSION IF EXISTS citext;