#!/bin/bash
export PATH=/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/home/oracle/.local/bin:/home/oracle/bin
#--------------------------------------------------------------------------------------------------
#-  Password Expiration Notification                                    Edgar Bowlin  11-22-2021  -
#--------------------------------------------------------------------------------------------------
#-  This script monitors the PASSWORD_EXPIRATION_VW and emails each user whose password expires   -
#-  within 7 days or less.  Each user will continue to receive a password expiration email from   -
#-  within 7 days of expiration down to password expiration or password_change_date update in     -
#-  DBA_USERS table.                                                                              -
#--------------------------------------------------------------------------------------------------
#-  INPUT RESOURCES                                                                               -
#--------------------------------------------------------------------------------------------------
#-  Tables :  PASSWORD_MGMT                                                                       -
#-  Views  :  PASSWORD_EXPIRATION_VW  (Query on PASSWORD_MGMT PASSWORD_EXPIRES column <= 7 days)  -
#--------------------------------------------------------------------------------------------------
#-  REVISION HISTORY                                                                              -
#--------------------------------------------------------------------------------------------------
#-  Revision 0.1  - Edgar Bowlin - 11-22-2021 - Script Debug and Development.                     -
#-  Revision 1.0  - Edgar Bowlin - 11-23-2021 - Release after code review by Patrick Lynn         -
#-  Revision 1.1  - Edgar Bowlin - 12-01-2021 - Added Vault Authentication $masterpass            -
#-  Revision 1.2  - Edgar Bowlin - 12-07-2021 - Added Path statement and export $Path variable as -
#-                  Vault password retrieval code will not work without it.                       -
#--------------------------------------------------------------------------------------------------

#-----------------------------------------------------
#- Include global functions library
#-----------------------------------------------------
. $SCRIPT_DIR/functions/functions.sh
set_vault_environment

#-------------------------------------------------------------------------
#- Execution Paths                                                       -
#-------------------------------------------------------------------------

PWPATH=/home/oracle/bia-devel/BIA/scripts/passwordmgmt
PWOUTPUT=/home/oracle/bia-devel/BIA/scripts/passwordmgmt/output

#-------------------------------------------------------------------------
#- Vault Authentication                                                  -
#-------------------------------------------------------------------------
#- Retrieve vault passwords for fraud prevention accounts and parse out  -
#- password for Master User dbadmin account and store in masterpass.     -
#-------------------------------------------------------------------------

export VAULT_ADDR='https://vault.prod8.bip.va.gov'
export VAULT_TOKEN=$(aws secretsmanager get-secret-value --secret-id bia-dbas-vault | jq --raw-output '.SecretString')
masterpass=`vault kv get secret/platform/bia-dbas/fraud-prevention/prod | grep 'Master User Password   ' | awk '{ print $4 }'` 

#-------------------------------------------------------------------------
#- Delete previous expiringusers.lst file.                               -
#-------------------------------------------------------------------------

if [ -f $PWOUTPUT/expiringusers.lst ]; then
   rm $PWOUTPUT/expiringusers.lst
fi

#-------------------------------------------------------------------------
#- Execute SQL query on PASSWORD_EXPIRATION_VW and USER_EMAILS table,    -
#- writing any results to expiringusers.lst output file.                 -
#-------------------------------------------------------------------------

connectstr="dbadmin/"$masterpass"@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=bip-fraud-prev-prod.cetxxdbd6our.us-gov-west-1.rds.amazonaws.com)(PORT=1521))(CONNECT_DATA=(SERVER=DEDICATED)(SID=FPDB))) @$PWPATH/password_mgmt.sql"
sqlplus $connectstr

#-------------------------------------------------------------------------
#- While not EOF, read each line of input file expiringusers.lst  from   -
#- query on PASSWORD_EXPIRATION_VW view.  From each line, user AWK to    -
#- parse each of four variables out of the current line: username,       -
#- va_email, expire_date, and days_left.                                 -
#-------------------------------------------------------------------------

while IFS= read -r line; do
   username=`echo $line | awk -F, '{ print $1 }'`
   va_email=`echo $line | awk -F, '{ print $2 }'`
   expire_date=`echo $line | awk -F, '{ print $3 }'`
   days_left=`echo $line | awk -F, '{ print $4 }'`

   #echo $username " " $va_email " " $expire_date " " $days_left 

#-------------------------------------------------------------------------
#-  Echo subject line, To, From, and Message Body values, appending each -
#-  to message.txt file. User message.txt file as input to sendmail      -
#-  command.  After sendmail, delete message.txt file.                   -
#-------------------------------------------------------------------------
   
   echo "Subject: Fraud Prevention Database Password Expiration" >> $PWOUTPUT/message.txt
   echo "To: " $va_email >> $PWOUTPUT/message.txt 
   echo "From: donotreply@va.gov" >> $PWOUTPUT/message.txt
   echo $username ", Your Fraud Prevention production database password will expire in " $days_left " days. Please change your password as soon as possible." >> $PWOUTPUT/message.txt
   cat $PWOUTPUT/message.txt | sendmail -t
   rm $PWOUTPUT/message.txt
done < $PWOUTPUT/expiringusers.lst

