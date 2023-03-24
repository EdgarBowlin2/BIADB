set echo on;
set feedback on;
spool /home/oracle/scripts/refresh/bpds/logs/users.log
CREATE PROFILE WIDE_OPEN LIMIT
        SESSIONS_PER_USER UNLIMITED
        CPU_PER_SESSION UNLIMITED
        CPU_PER_CALL UNLIMITED
        CONNECT_TIME UNLIMITED
        IDLE_TIME UNLIMITED
        LOGICAL_READS_PER_SESSION UNLIMITED
        LOGICAL_READS_PER_CALL UNLIMITED
        COMPOSITE_LIMIT UNLIMITED
        PRIVATE_SGA UNLIMITED
        FAILED_LOGIN_ATTEMPTS 3
        PASSWORD_LIFE_TIME 365
        PASSWORD_REUSE_TIME UNLIMITED
        PASSWORD_REUSE_MAX UNLIMITED
        PASSWORD_LOCK_TIME UNLIMITED
        PASSWORD_GRACE_TIME 7
        PASSWORD_VERIFY_FUNCTION NULL;

alter user SYSBACKUP PROFILE WIDE_OPEN;
alter user SYSRAC PROFILE WIDE_OPEN;
alter user VANSOCSCAN PROFILE WIDE_OPEN;
alter user SYSKM PROFILE WIDE_OPEN;
alter user SYS$UMF PROFILE WIDE_OPEN;
alter user LIQUIBASE_ADMIN PROFILE WIDE_OPEN;
alter user SYSDG PROFILE WIDE_OPEN;
alter user DBADMIN PROFILE WIDE_OPEN;
ERROR:
ORA-16000: database or pluggable database open for read-only access
ORA-06512: at "SYS.DBMS_METADATA", line 6731
ORA-06512: at "SYS.DBMS_METADATA", line 6516
ORA-06512: at "SYS.DBMS_LOCK", line 378
ORA-06512: at "SYS.DBMS_LOCK", line 411
ORA-06512: at "SYS.KUPU$UTILITIES_INT", line 1738
ORA-06512: at "SYS.DBMS_METADATA", line 1216
ORA-06512: at "SYS.DBMS_METADATA", line 1314
ORA-06512: at "SYS.DBMS_METADATA", line 6439
ORA-06512: at "SYS.DBMS_METADATA", line 6572
ORA-06512: at "SYS.DBMS_METADATA", line 9734
ORA-06512: at line 1


ERROR:
ORA-16000: database or pluggable database open for read-only access
ORA-06512: at "SYS.DBMS_METADATA", line 6731
ORA-06512: at "SYS.DBMS_METADATA", line 6516
ORA-06512: at "SYS.DBMS_LOCK", line 378
ORA-06512: at "SYS.DBMS_LOCK", line 411
ORA-06512: at "SYS.KUPU$UTILITIES_INT", line 1738
ORA-06512: at "SYS.DBMS_METADATA", line 1216
ORA-06512: at "SYS.DBMS_METADATA", line 1314
ORA-06512: at "SYS.DBMS_METADATA", line 6439
ORA-06512: at "SYS.DBMS_METADATA", line 6572
ORA-06512: at "SYS.DBMS_METADATA", line 9734
ORA-06512: at line 1


alter user SYSBACKUP account unlock;
alter user SYSRAC account unlock;
alter user VANSOCSCAN account unlock;
alter user SYSKM account unlock;
alter user SYS$UMF account unlock;
alter user LIQUIBASE_ADMIN account unlock;
alter user SYSDG account unlock;
DROP PROFILE WIDE_OPEN CASCADE;
spool off
