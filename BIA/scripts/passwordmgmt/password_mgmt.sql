/***************************************************************************
*  Export Expired Username List                   Edgar Bowlin 11-22-2021  *
****************************************************************************
*  Query PASSWORD_EXPIRATION_VW View for usernames, email addresses,       *
*  password expiration, and days left (until password expiration).         *
*  store output in a text file - expiring_users.lst.                       *
****************************************************************************/

set feedback off;
set heading off;
set pagesize 0;
set linesize 240;

spool /home/oracle/scripts/passwordmgmt/output/expiringusers.lst;

select trim(pevw.username), ',', trim(ue.va_email_addr), ',', trim(pevw.expiry_date), ',', trim(pevw.days_left) from password_expiration_vw pevw, user_email_addresses ue
where pevw.username = ue.username and ue.va_email_addr is not null order by pevw.username asc;

spool off;
exit;
