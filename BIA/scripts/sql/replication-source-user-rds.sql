EXEC RDSADMIN.RDSADMIN_UTIL.ALTER_SUPPLEMENTAL_LOGGING(P_ACTION => 'ADD');

CREATE ROLE &&ROLENAME NOT IDENTIFIED;
GRANT CREATE SESSION TO &&ROLENAME;
GRANT SELECT ANY TRANSACTION TO &&ROLENAME;
GRANT LOGMINING TO &&ROLENAME; 

EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('ALL_CATALOG', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('ALL_CONS_COLUMNS', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('ALL_CONSTRAINTS', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('ALL_ENCRYPTED_COLUMNS', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('ALL_IND_COLUMNS', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('ALL_INDEXES', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('ALL_LOG_GROUPS', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('ALL_OBJECTS', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('ALL_TAB_COLS', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('ALL_TAB_PARTITIONS', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('ALL_TABLES', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('ALL_USERS', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('ALL_VIEWS', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('DBA_REGISTRY', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('DBA_TABLESPACES', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('DBMS_LOGMNR', '&&ROLENAME', 'EXECUTE');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('ENC$', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('OBJ$', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('REGISTRY$SQLPATCH', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('V_$ARCHIVED_LOG', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('V_$CONTAINERS', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('V_$DATABASE', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('V_$INSTANCE', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('V_$LOG', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('V_$LOGFILE', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('V_$LOGMNR_CONTENTS','&&ROLENAME','SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('V_$LOGMNR_LOGS', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('V_$NLS_PARAMETERS', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('V_$PARAMETER', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('V_$STANDBY_LOG', '&&ROLENAME', 'SELECT'); 
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('V_$THREAD', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('V_$TIMEZONE_NAMES', '&&ROLENAME', 'SELECT');
EXEC RDSADMIN.RDSADMIN_UTIL.GRANT_SYS_OBJECT('V_$TRANSACTION', '&&ROLENAME', 'SELECT');

EXEC RDSADMIN.RDSADMIN_UTIL.SET_CONFIGURATION('ARCHIVELOG RETENTION HOURS', 48);
COMMIT;

EXEC RDSADMIN.RDSADMIN_UTIL.SWITCH_LOGFILE;

CREATE USER "&1" IDENTIFIED BY "&2"
    DEFAULT TABLESPACE USERS
    TEMPORARY TABLESPACE TEMP
    ACCOUNT UNLOCK;

ALTER USER "&1" QUOTA UNLIMITED ON USERS;
GRANT CREATE SESSION TO "&1";
GRANT "&&ROLENAME" TO "&1";

--GRANT SELECT ON &&SOURCE_OWNER.&&SOURCE_TABLE TO &&USERNAME;
--GRANT FLASHBACK ON &&SOURCE_OWNER.&&SOURCE_TABLE TO &&USERNAME;
--ALTER TABLE &&SOURCE_OWNER.&&SOURCE_TABLE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;