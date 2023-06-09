CREATE USER "&1" IDENTIFIED BY "&2"
    DEFAULT TABLESPACE USERS
    TEMPORARY TABLESPACE TEMP
    PROFILE USER_PROFILE
    ACCOUNT UNLOCK;

GRANT CONNECT TO "&1";
GRANT SELECT ANY TABLE TO "&1";
ALTER USER "&1" DEFAULT ROLE ALL;

COMMIT;
