-- +goose Up
CREATE SCHEMA IF NOT EXISTS crm;


-- +goose Down
DROP SCHEMA IF EXISTS crm;