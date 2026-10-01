-- +goose Up
--
-- search paths
--
ALTER ROLE bitamin_auth_role    SET search_path TO extensions, auth;
ALTER ROLE bitamin_app_role     SET search_path TO extensions, core, facebook, whatsapp, wamd, instagram;

--
-- revoke public (all users) access
--
REVOKE ALL ON SCHEMA extensions FROM PUBLIC;
REVOKE ALL ON SCHEMA auth       FROM PUBLIC;
REVOKE ALL ON SCHEMA core       FROM PUBLIC;
REVOKE ALL ON SCHEMA facebook   FROM PUBLIC;
REVOKE ALL ON SCHEMA whatsapp   FROM PUBLIC;
REVOKE ALL ON SCHEMA wamd       FROM PUBLIC;
REVOKE ALL ON SCHEMA instagram  FROM PUBLIC;
REVOKE ALL ON SCHEMA connectors FROM PUBLIC;
REVOKE ALL ON SCHEMA extensions FROM PUBLIC;

--
-- grant schema usage
--
-- auth role can use auth schema
GRANT USAGE ON SCHEMA extensions    TO bitamin_auth_role;
GRANT USAGE ON SCHEMA auth          TO bitamin_auth_role;
-- app role can use business schemas
GRANT USAGE ON SCHEMA extensions    TO bitamin_app_role;
GRANT USAGE ON SCHEMA auth          TO bitamin_app_role; -- for verification of agent login flow
GRANT USAGE ON SCHEMA core          TO bitamin_app_role;
GRANT USAGE ON SCHEMA facebook      TO bitamin_app_role;
GRANT USAGE ON SCHEMA whatsapp      TO bitamin_app_role;
GRANT USAGE ON SCHEMA wamd          TO bitamin_app_role;
GRANT USAGE ON SCHEMA instagram     TO bitamin_app_role;
GRANT USAGE ON SCHEMA connectors    TO bitamin_app_role;
GRANT USAGE ON SCHEMA extensions    TO bitamin_app_role;

--
-- default privileges for future objects
-- set before tables are created so all objects inherit these permissions
--
-- extensions schema: auth_role gets full DML
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA extensions    GRANT SELECT, INSERT, UPDATE, DELETE    ON TABLES       TO bitamin_auth_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA extensions    GRANT USAGE, SELECT                     ON SEQUENCES    TO bitamin_auth_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA extensions    GRANT EXECUTE                           ON FUNCTIONS    TO bitamin_auth_role;
-- auth schema: auth_role gets full DML
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA auth          GRANT SELECT, INSERT, UPDATE, DELETE    ON TABLES       TO bitamin_auth_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA auth          GRANT USAGE, SELECT                     ON SEQUENCES    TO bitamin_auth_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA auth          GRANT EXECUTE                           ON FUNCTIONS    TO bitamin_auth_role;
-- extensions schema: app_role gets full DML
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA extensions    GRANT SELECT, INSERT, UPDATE, DELETE    ON TABLES       TO bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA extensions    GRANT USAGE, SELECT                     ON SEQUENCES    TO bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA extensions    GRANT EXECUTE                           ON FUNCTIONS    TO bitamin_app_role;
-- auth schema: app_role gets full DML
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA auth          GRANT SELECT, INSERT, UPDATE, DELETE    ON TABLES       TO bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA auth          GRANT USAGE, SELECT                     ON SEQUENCES    TO bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA auth          GRANT EXECUTE                           ON FUNCTIONS    TO bitamin_app_role;
-- core schema: app_role gets full DML
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA core          GRANT SELECT, INSERT, UPDATE, DELETE    ON TABLES       TO bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA core          GRANT USAGE, SELECT                     ON SEQUENCES    TO bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA core          GRANT EXECUTE                           ON FUNCTIONS    TO bitamin_app_role;
-- facebook schema: app_role gets full DML
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA facebook      GRANT SELECT, INSERT, UPDATE, DELETE    ON TABLES       TO bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA facebook      GRANT USAGE, SELECT                     ON SEQUENCES    TO bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA facebook      GRANT EXECUTE                           ON FUNCTIONS    TO bitamin_app_role;
-- whatsapp schema: app_role gets full DML
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA whatsapp      GRANT SELECT, INSERT, UPDATE, DELETE    ON TABLES       TO bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA whatsapp      GRANT USAGE, SELECT                     ON SEQUENCES    TO bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA whatsapp      GRANT EXECUTE                           ON FUNCTIONS    TO bitamin_app_role;
-- wamd schema: app_role gets full DML
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA wamd          GRANT SELECT, INSERT, UPDATE, DELETE    ON TABLES       TO bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA wamd          GRANT USAGE, SELECT                     ON SEQUENCES    TO bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA wamd          GRANT EXECUTE                           ON FUNCTIONS    TO bitamin_app_role;
-- instagram schema: app_role gets full DML
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA instagram     GRANT SELECT, INSERT, UPDATE, DELETE    ON TABLES       TO bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA instagram     GRANT USAGE, SELECT                     ON SEQUENCES    TO bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA instagram     GRANT EXECUTE                           ON FUNCTIONS    TO bitamin_app_role;
-- connectors schema: app_role gets full DML
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA connectors    GRANT SELECT, INSERT, UPDATE, DELETE    ON TABLES       TO bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA connectors    GRANT USAGE, SELECT                     ON SEQUENCES    TO bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA connectors    GRANT EXECUTE                           ON FUNCTIONS    TO bitamin_app_role;

-- +goose Down
-- revoke default privileges for instagram schema for app role
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA instagram     REVOKE ALL ON FUNCTIONS FROM bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA instagram     REVOKE ALL ON SEQUENCES FROM bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA instagram     REVOKE ALL ON TABLES    FROM bitamin_app_role;
-- revoke default privileges for wamd schema for app role
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA wamd          REVOKE ALL ON FUNCTIONS FROM bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA wamd          REVOKE ALL ON SEQUENCES FROM bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA wamd          REVOKE ALL ON TABLES    FROM bitamin_app_role;
-- revoke default privileges for whatsapp schema for app role
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA whatsapp      REVOKE ALL ON FUNCTIONS FROM bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA whatsapp      REVOKE ALL ON SEQUENCES FROM bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA whatsapp      REVOKE ALL ON TABLES    FROM bitamin_app_role;
-- revoke default privileges for facebook schema for app role
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA facebook      REVOKE ALL ON FUNCTIONS FROM bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA facebook      REVOKE ALL ON SEQUENCES FROM bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA facebook      REVOKE ALL ON TABLES    FROM bitamin_app_role;
-- revoke default privileges for connectors schema for app role
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA connectors    REVOKE ALL ON FUNCTIONS FROM bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA connectors    REVOKE ALL ON SEQUENCES FROM bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA connectors    REVOKE ALL ON TABLES    FROM bitamin_app_role;
-- revoke default privileges for core schema for app role
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA core          REVOKE ALL ON FUNCTIONS FROM bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA core          REVOKE ALL ON SEQUENCES FROM bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA core          REVOKE ALL ON TABLES    FROM bitamin_app_role;
-- revoke default privileges for auth schema for app role
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA auth          REVOKE ALL ON FUNCTIONS FROM bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA auth          REVOKE ALL ON SEQUENCES FROM bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA auth          REVOKE ALL ON TABLES    FROM bitamin_app_role;
-- revoke default privileges for extensions schema for app role
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA extensions    REVOKE ALL ON FUNCTIONS FROM bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA extensions    REVOKE ALL ON SEQUENCES FROM bitamin_app_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA extensions    REVOKE ALL ON TABLES    FROM bitamin_app_role;
-- revoke default privileges for auth schema for auth role
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA auth          REVOKE ALL ON FUNCTIONS FROM bitamin_auth_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA auth          REVOKE ALL ON SEQUENCES FROM bitamin_auth_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA auth          REVOKE ALL ON TABLES    FROM bitamin_auth_role;
-- revoke default privileges for extensions schema for auth role
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA extensions    REVOKE ALL ON FUNCTIONS FROM bitamin_auth_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA extensions    REVOKE ALL ON SEQUENCES FROM bitamin_auth_role;
ALTER DEFAULT PRIVILEGES FOR ROLE bitamin_admin IN SCHEMA extensions    REVOKE ALL ON TABLES    FROM bitamin_auth_role;


-- revoke schema usage
REVOKE USAGE ON SCHEMA instagram    FROM bitamin_app_role;
REVOKE USAGE ON SCHEMA wamd         FROM bitamin_app_role;
REVOKE USAGE ON SCHEMA whatsapp     FROM bitamin_app_role;
REVOKE USAGE ON SCHEMA facebook     FROM bitamin_app_role;
REVOKE USAGE ON SCHEMA core         FROM bitamin_app_role;
REVOKE USAGE ON SCHEMA auth         FROM bitamin_app_role;
REVOKE USAGE ON SCHEMA extensions   FROM bitamin_app_role;
REVOKE USAGE ON SCHEMA connectors   FROM bitamin_app_role;
REVOKE USAGE ON SCHEMA auth         FROM bitamin_auth_role;
REVOKE USAGE ON SCHEMA extensions   FROM bitamin_auth_role;
-- reset search paths
ALTER ROLE bitamin_app_role     RESET search_path;
ALTER ROLE bitamin_auth_role    RESET search_path;