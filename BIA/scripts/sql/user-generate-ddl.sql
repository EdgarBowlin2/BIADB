SET LONGCHUNKSIZE 20000 PAGESIZE 0 FEEDBACK OFF VERIFY OFF TRIMSPOOL ON

COLUMN extracted_ddl FORMAT a1000

EXEC dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'PRETTY', true);

EXEC dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR', true);

UNDEFINE user_in_uppercase;

SET LINESIZE 1000

SET LONG 2000000000

SELECT
    (
        CASE
            WHEN ( (
                SELECT
                    COUNT(*)
                FROM
                    dba_users
                WHERE
                        username = '&&User_in_Uppercase'
                    AND profile <> 'DEFAULT'
            ) > 0 ) THEN
                CHR(10)
                || ' -- Note: Profile'
                || (
                    SELECT
                        dbms_metadata.get_ddl('PROFILE', u.profile) AS ddl
                    FROM
                        dba_users u
                    WHERE
                        u.username = '&User_in_Uppercase'
                )
            ELSE
                to_clob(CHR(10)
                        || ' -- Note: Default profile, no need to create!')
        END
    )
FROM
    dual
UNION ALL
SELECT
    (
        CASE
            WHEN ( (
                SELECT
                    COUNT(*)
                FROM
                    dba_users
                WHERE
                    username = '&User_in_Uppercase'
            ) > 0 ) THEN
                ' -- Note: Create user statement'
                || dbms_metadata.get_ddl('USER', '&User_in_Uppercase')
            ELSE
                to_clob(CHR(10)
                        || ' -- Note: User not found!')
        END
    ) extracted_ddl
FROM
    dual
UNION ALL
SELECT
    (
        CASE
            WHEN ( (
                SELECT
                    COUNT(*)
                FROM
                    dba_ts_quotas
                WHERE
                    username = '&User_in_Uppercase'
            ) > 0 ) THEN
                ' -- Note: TBS quota'
                || dbms_metadata.get_granted_ddl('TABLESPACE_QUOTA', '&User_in_Uppercase')
            ELSE
                to_clob(CHR(10)
                        || ' -- Note: No TS Quotas found!')
        END
    )
FROM
    dual
UNION ALL
SELECT
    (
        CASE
            WHEN ( (
                SELECT
                    COUNT(*)
                FROM
                    dba_role_privs
                WHERE
                    grantee = '&User_in_Uppercase'
            ) > 0 ) THEN
                ' -- Note: Roles'
                || dbms_metadata.get_granted_ddl('ROLE_GRANT', '&User_in_Uppercase')
            ELSE
                to_clob(CHR(10)
                        || ' -- Note: No granted Roles found!')
        END
    )
FROM
    dual
UNION ALL
SELECT
    (
        CASE
            WHEN ( (
                SELECT
                    COUNT(*)
                FROM
                    v$pwfile_users
                WHERE
                        username = '&User_in_Uppercase'
                    AND sysdba = 'TRUE'
            ) > 0 ) THEN
                ' -- Note: sysdba'
                || CHR(10)
                || to_clob(' GRANT SYSDBA TO '
                           || '"'
                           || '&User_in_Uppercase'
                           || '"'
                           || ';')
            ELSE
                to_clob(CHR(10)
                        || ' -- Note: No sysdba administrative Privilege found!')
        END
    )
FROM
    dual
UNION ALL
SELECT
    (
        CASE
            WHEN ( (
                SELECT
                    COUNT(*)
                FROM
                    dba_sys_privs
                WHERE
                    grantee = '&User_in_Uppercase'
            ) > 0 ) THEN
                ' -- Note: System Privileges'
                || dbms_metadata.get_granted_ddl('SYSTEM_GRANT', '&User_in_Uppercase')
            ELSE
                to_clob(CHR(10)
                        || ' -- Note: No System Privileges found!')
        END
    )
FROM
    dual
UNION ALL
SELECT
    (
        CASE
            WHEN ( (
                SELECT
                    COUNT(*)
                FROM
                    dba_tab_privs
                WHERE
                    grantee = '&User_in_Uppercase'
            ) > 0 ) THEN
                ' -- Note: Object Privileges'
                || dbms_metadata.get_granted_ddl('OBJECT_GRANT', '&User_in_Uppercase')
            ELSE
                to_clob(CHR(10)
                        || ' -- Note: No Object Privileges found!')
        END
    )
FROM
    dual
/