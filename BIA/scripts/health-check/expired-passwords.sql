set head off
set feedback off
set linesize 10000

SELECT LISTAGG(username, ', ') WITHIN GROUP(ORDER BY username)
  FROM dba_users
 WHERE username IN (SELECT username 
                      FROM dba_users 
                     WHERE expiry_date < sysdate + 15
                       AND (username = 'DBSNMP' OR created > (SELECT created FROM dba_users WHERE username = 'RDSADMIN') ) 
                       AND username not in ('RDSADMIN$LIMITED')
                       AND account_status not like '%LOCKED%'
                       AND (username = 'BIP_DBA' OR profile not in ('DBA_PROFILE', 'USER_PROFILE'))
                       );

exit

