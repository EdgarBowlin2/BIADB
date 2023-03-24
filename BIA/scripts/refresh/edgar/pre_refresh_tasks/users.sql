
set long 30000;
set pages 0;
set lines 400;
set feedback off;
set echo off;
set longchunksize 5000;
set trimspool on;
spool /home/oracle/bia-devel/BIA/scripts/refresh/post_refresh_tasks/add_users.sql
select 'set echo on;' from dual;
select 'set feedback on;' from dual;
select 'spool /home/oracle/scripts/refresh/logs/users.log' from dual;


--Wide Open Profile
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


select 'alter user ' || username || ' PROFILE WIDE_OPEN;'
from DBA_USERS
where profile = 'APP_PROFILE'
and default_tablespace not in ('SYSTEM','SYSAUX')
and username not in ('DIP','GSMCATUSER','GSMUSER','RDSADMIN','AUDSYS','BIP_DBA',
'VBMS_DBA','REMOTE_SCHEDULER_AGENT','GG');

select 'alter user ' || username || ' PROFILE WIDE_OPEN;'
from DBA_USERS
where username = 'DBADMIN';

--App_Profiles
select REPLACE(dbms_metadata.get_ddl('USER',username),'CREATE','ALTER')||';'
from dba_users
where default_tablespace not in ('SYSTEM','SYSAUX')
and username not in ('DIP','GSMCATUSER','GSMUSER','RDSADMIN','AUDSYS','BIP_DBA',
'VBMS_DBA','REMOTE_SCHEDULER_AGENT','GG')
and profile='APP_PROFILE';

--DBADMIN
select REPLACE(dbms_metadata.get_ddl('USER',username),'CREATE','ALTER')||';'
from dba_users
where username = 'DBADMIN';

--User_Profiles

select 'drop user '||username||';' from dba_users where default_tablespace  not in ('SYSTEM','SYSAUX') and username not in ('DIP','GSMCATUSER','GSMUSER','RDSADMIN','AUDSYS','BIP_DBA','DBADMIN') and profile = 'USER_PROFILE';

select dbms_metadata.get_ddl('USER',username)||';' from dba_users where default_tablespace  not in ('SYSTEM','SYSAUX') and username not in ('DIP','GSMCATUSER','GSMUSER','RDSADMIN','AUDSYS','BIP_DBA','DBADMIN')and profile = 'USER_PROFILE';

--select 'grant BIP_PRODOPS_READONLY_ROLE to '||username||';' from dba_users where default_tablespace  not in ('SYSTEM','SYSAUX') and username not in ('DIP','GSMCATUSER','GSMUSER','RDSADMIN','AUDSYS','BIP_DBA','DBADMIN') and profile = 'USER_PROFILE';

--select 'alter user '||username||' account unlock;' from dba_users where default_tablespace  not in ('SYSTEM','SYSAUX') and username not in ('DIP','GSMCATUSER','GSMUSER','RDSADMIN','AUDSYS','BIP_DBA','DBADMIN') and profile = 'USER_PROFILE';

--Roles for User_Profiles
select 'grant '||GRANTED_ROLE||' to '||username||';'
from dba_users a join dba_role_privs b on (a.username=b.grantee)
where profile='USER_PROFILE';

--Wide to App Profile
select 'alter user ' || username || ' PROFILE APP_PROFILE;'
from DBA_USERS
where PROFILE = 'WIDE_OPEN';

--Unlock
select 'alter user ' || username || ' account unlock;'
from DBA_USERS
where default_tablespace not in ('SYSTEM','SYSAUX') and
username not in ('DIP','GSMCATUSER','GSMUSER','RDSADMIN','AUDSYS','BIP_DBA','VBMS_DBA','REMOTE_SCHEDULER_AGENT','GG') and profile='APP_PROFILE'
or
profile = 'USER_PROFILE';

--Drop Wide Open Profile
select 'DROP PROFILE WIDE_OPEN CASCADE;' from dual;

select 'spool off' from dual;

