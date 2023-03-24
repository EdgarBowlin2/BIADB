-- generate script to recreate users and change application user passwords

set long 30000;
set pages 0;
set lines 200;
set feedback off;
set echo off;
set longchunksize 500;
spool /home/oracle/scripts/refresh/mbms/post_refresh_tasks/mbms_add_prodtest_users.sql;

select 'set echo on;' from dual;
select 'set feedback on;' from dual;
select 'spool /home/oracle/scripts/refresh/mbms/logs/mbms_prodtest_users.log' from dual;


-----------------------------------------------------------------------------------------
--CREATE WIDE OPEN PROFILE
-----------------------------------------------------------------------------------------
select
        'CREATE PROFILE WIDE_OPEN LIMIT
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
        PASSWORD_VERIFY_FUNCTION NULL;' from dual;
		
		

-----------------------------------------------------------------------------------------
--ASSIGN WIDE OPEN PROFILE
--grab everything where app profle = app_profile_mbms
-----------------------------------------------------------------------------------------
select 'alter user ' || username || ' PROFILE WIDE_OPEN;'
from DBA_USERS
where profile = 'APP_PROFILE_MBMS';

-----------------------------------------------------------------------------------------
--ALTER USERS TO HAVE PRODTEST PASSWORDS
--capture prodtest application users to change passwords
--not changing sys users
-----------------------------------------------------------------------------------------
select REPLACE(REPLACE(dbms_metadata.get_ddl('USER',username), 'CREATE','ALTER'),'APP_PROFILE','WIDE_OPEN') || case when account_status = 'OPEN' then ' ACCOUNT UNLOCK;' else ';' end
from dba_users
where username not in ('SYS','SYSTEM','SCHED_TEST','AUDSYS','DIP','GSMCATUSER','GSMUSER','XS$NULL','APPQOSSYS','GSMADMIN_INTERNAL','CTXSYS','ANONYMOUS','XDB','DBSNMP','SYSKM','SYSBACKUP','OUTLN','SYSDG');

-----------------------------------------------------------------------------------------
--ASSIGN GRANTS
--grabbing roles that exist in prodtest for non application users
--same list as above
-----------------------------------------------------------------------------------------
select 'grant '||GRANTED_ROLE||' to '||username||';'
from dba_users a join dba_role_privs b on (a.username=b.grantee)where username not in ('SCHED_TEST','SYS','SYSTEM','DBADMIN','RDSADMIN','AUDSYS','DIP','GSMCATUSER','GSMUSER','XS$NULL','APPQOSSYS','GSMADMIN_INTERNAL','CTXSYS','ANONYMOUS','XDB','DBSNMP','SYSKM','SYSBACKUP','OUTLN','SYSDG');



-----------------------------------------------------------------------------------------
--RESETTING PROFILE FOR APPLICATION USERS
-----------------------------------------------------------------------------------------
select 'alter user ' || username || ' PROFILE APP_PROFILE_MBMS;'
from DBA_USERS
where PROFILE = 'WIDE_OPEN';

select 'DROP PROFILE WIDE_OPEN CASCADE;' from dual;

-----------------------------------------------------------------------------------------
--UNLOCK APPLICATION ACCOUNTS
-----------------------------------------------------------------------------------------
select 'alter user MBMS account unlock;' from dual;
select 'alter user MBMS_USER_K8S account unlock;' from dual;
select 'alter user MBMS_AUDIT account unlock;' from dual;
select 'alter user MBMS_USER account unlock;' from dual;
select 'alter user BOSS_LIQ account unlock;' from dual;
select 'alter user BOSS account unlock;' from dual;
select 'alter user LIQUIBASE_ADMIN account unlock;' from dual;
select 'alter user AMASR account unlock;' from dual;
select 'alter user SYS_USER account unlock;' from dual;
select 'alter user BOSS_USR account unlock;' from dual;
select 'alter user BOSSPROD account unlock;' from dual;
select 'alter user PMC_DATA account unlock;' from dual;
select 'alter user DOCUMENT_STORAGE_DATA account unlock;' from dual;
select 'alter user EOAS_DATA account unlock;' from dual;
select 'alter user KSKPROD account unlock;' from dual;
select 'alter user STATPROD account unlock;' from dual;




-----------------------------------------------------------------------------------------
--SPECIAL POST REFRESH STEPS
-----------------------------------------------------------------------------------------
select 'spool off' from dual;
spool off;



