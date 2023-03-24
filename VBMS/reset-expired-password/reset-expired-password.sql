SET SERVEROUTPUT ON

DECLARE
    CURSOR curuser IS
    SELECT
        username
    FROM
        dba_users
    WHERE
            profile IN ( 'DEFAULT', 'INSECURE' )
        AND username NOT IN ( 'AUDSYS', 'ORACLE_OCM', 'XDB', 'XS$NULL' );

    vc_username dba_users.username%TYPE;
    objects     INTEGER;
    sessions    INTEGER;
BEGIN
    OPEN curuser;
    LOOP
        FETCH curuser INTO vc_username;
        EXIT WHEN curuser%notfound;
 
        SELECT
            COUNT(*)
        INTO objects
        FROM
            dba_objects
        WHERE
            owner = vc_username;

        SELECT
            COUNT(*)
        INTO sessions
        FROM
            v$session
        WHERE
            username = vc_username;

        IF
            objects = 0
            AND sessions = 0
        THEN
            EXECUTE IMMEDIATE 'ALTER USER '
                              || vc_username
                              || ' PROFILE USER_PROFILE';
        ELSE
            EXECUTE IMMEDIATE 'ALTER USER '
                              || vc_username
                              || ' PROFILE APP_PROFILE';
        END IF;

    END LOOP;

    CLOSE curuser;
EXCEPTION
    WHEN OTHERS THEN
        dbms_output.put_line(sqlerrm);
        IF ( curuser%isopen ) THEN
            CLOSE curuser;
        END IF;
END;
/

CREATE PROFILE "INSECURE" LIMIT
    CPU_PER_SESSION UNLIMITED
    CPU_PER_CALL UNLIMITED
    CONNECT_TIME UNLIMITED
    IDLE_TIME UNLIMITED
    SESSIONS_PER_USER UNLIMITED
    LOGICAL_READS_PER_SESSION UNLIMITED
    LOGICAL_READS_PER_CALL UNLIMITED
    PRIVATE_SGA UNLIMITED
    COMPOSITE_LIMIT UNLIMITED
    PASSWORD_LIFE_TIME UNLIMITED
    PASSWORD_GRACE_TIME UNLIMITED
    PASSWORD_REUSE_MAX UNLIMITED
    PASSWORD_REUSE_TIME UNLIMITED
    PASSWORD_LOCK_TIME UNLIMITED
    FAILED_LOGIN_ATTEMPTS UNLIMITED
    PASSWORD_VERIFY_FUNCTION NULL;

DECLARE
    CURSOR curuser IS
    SELECT
        username,
        profile
    FROM
        dba_users
    WHERE
        username IN (
            SELECT
                username
            FROM
                dba_users
            WHERE
                ( username = 'DBSNMP'
                  OR created > (
                    SELECT
                        created
                    FROM
                        dba_users
                    WHERE
                        username = 'RDSADMIN'
                ) )
                AND expiry_date < sysdate + 7
                AND profile <> 'USER_PROFILE'
        );

    vc_username dba_users.username%TYPE;
    vc_profile  dba_users.profile%TYPE;
    password    VARCHAR2(4000);
BEGIN
    OPEN curuser;
    LOOP
        FETCH curuser INTO
            vc_username,
            vc_profile;
        EXIT WHEN curuser%notfound;
        dbms_output.put_line(vc_username);
        password := regexp_substr(sys.dbms_metadata.get_ddl('USER', vc_username), '''[^'']+''');

        EXECUTE IMMEDIATE 'ALTER USER '
                          || vc_username
                          || ' PROFILE INSECURE';
        EXECUTE IMMEDIATE 'ALTER USER '
                          || vc_username
                          || ' IDENTIFIED BY VALUES '
                          || password
                          || ' ACCOUNT UNLOCK';
        EXECUTE IMMEDIATE 'ALTER USER '
                          || vc_username
                          || ' PROFILE '
                          || vc_profile;
    END LOOP;

    CLOSE curuser;
EXCEPTION
    WHEN OTHERS THEN
        dbms_output.put_line(sqlerrm);
        IF ( curuser%isopen ) THEN
            CLOSE curuser;
        END IF;
END;
/

DROP PROFILE insecure;
