-- +goose Up
-- create schemas for different platforms
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS auth; -- OAuth database schema
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS facebook;
CREATE SCHEMA IF NOT EXISTS whatsapp;
CREATE SCHEMA IF NOT EXISTS wamd; -- whatsapp multi-device
CREATE SCHEMA IF NOT EXISTS instagram;
CREATE SCHEMA IF NOT EXISTS partman; -- pg_partman partition management
CREATE SCHEMA IF NOT EXISTS connectors;
CRESTE SCHEMA IF NOT EXISTS crm; -- CRM database schema


-- +goose Down
DROP SCHEMA IF EXISTS crm;
DROP SCHEMA IF EXISTS connectors;
DROP SCHEMA IF EXISTS partman;
DROP SCHEMA IF EXISTS instagram;
DROP SCHEMA IF EXISTS wamd;
DROP SCHEMA IF EXISTS whatsapp;
DROP SCHEMA IF EXISTS facebook;
DROP SCHEMA IF EXISTS core;
DROP SCHEMA IF EXISTS auth;
DROP SCHEMA IF EXISTS extensions;