#!/bin/bash
#-----------------------------------------------------------------------------
# Functions Library			       	Matt Brady     10-02-2013    -
#-----------------------------------------------------------------------------
# Purpose 
#-----------------------------------------------------------------------------
#-  Functions Library that can be sourced and called by shell scripts.
#-----------------------------------------------------------------------------
# Input 
#-----------------------------------------------------------------------------
# None 
#-----------------------------------------------------------------------------
# Revision History
#-----------------------------------------------------------------------------
#  JRussell - 15-May-2014 
#  Adjust 'here documents' to ensure EOF is at column 1 and closing ) 
#  is on the next line
#
#  EBowlin - 10-FEB-2023 
#  Added comments and additional functions from env files to have all BIA 
#  functions for script usage in a central functions library.
#-----------------------------------------------------------------------------

#-----------------------------------
#           FUNCTIONS
#-----------------------------------
export EMCLI_HOME=$HOME/software/emcli

#-----------------------------------------------------------------------------
#- set_vault_environment ()
#-----------------------------------------------------------------------------
#- Purpose       
#-----------------------------------------------------------------------------
#- Set Vault environment based on the domain (Dev, Stage, or Prod). This 
#- allows us to "token authenticate" and execute vault command line commands. 
#-----------------------------------------------------------------------------
set_vault_environment () {
        MACADDR=$( curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs )
        VPCID=$( curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/${MACADDR}/vpc-id )

        if [[ "$VPCID" == "vpc-af38e7cb" ]]; then
                export VAULT_ADDR='https://vault.dev8.bip.va.gov'
                export VAULT_SECRET='dev8-vault'
                export OEM_PATH='secret/platform/database-admin/bip-dev-oem'
                TOKENSECRET=$( aws secretsmanager get-secret-value --secret-id $VAULT_SECRET | jq --raw-output '.SecretString' | jq -r .token)
        elif [[ "$VPCID" == "vpc-bb3de2df" ]]; then
                export VAULT_ADDR='https://vault.stage8.bip.va.gov'
                export VAULT_SECRET='stage8-vault'
                export OEM_PATH='secret/platform/database-admin/bip-stage-oem'
                TOKENSECRET=$( aws secretsmanager get-secret-value --secret-id $VAULT_SECRET | jq --raw-output '.SecretString' | jq -r .token)
        elif [[ "$VPCID" == "vpc-5e3ae53a" ]]; then
                export VAULT_ADDR='https://vault.prod8.bip.va.gov'
                export VAULT_SECRET='bia-dbas-vault'
                export OEM_PATH='secret/platform/prodops-dba/bip-oem'
                TOKENSECRET=$( aws secretsmanager get-secret-value --secret-id $VAULT_SECRET | jq --raw-output '.SecretString')
        else
                echo "error: VPC could not be determined."
        fi

        export VAULT_TOKEN=$( echo ${TOKENSECRET##* } )
}

#-----------------------------------------------------------------------------
#- dbstatus ()
#-----------------------------------------------------------------------------
#- Purpose       
#-----------------------------------------------------------------------------
#- Check if database status (up, down, restricted, etc.).  If the database is
#- not up, exit the calling script.
#-----------------------------------------------------------------------------

function dbstatus () {
DB_STATUS=$(sqlplus -silent  /@$1 << EOF
    set heading off feedback off verify off pagesize 0
    whenever oserror exit 1;
    whenever sqlerror exit 2;
    select status from v\$instance;
    exit;
EOF
)

  DB_STATUS=`echo $DB_STATUS | /bin/grep -v ERROR`

  if [ -z "$DB_STATUS" ]
  then
      DB_STATUS="DOWN"
      echo "***WARNING*** Database Status:  " $DB_STATUS
      echo "***WARNING*** Exiting Script."
      exit 1;
  else
      echo "***INFO*** Database $ORACLE_SID is open"
  fi
}

#-----------------------------------------------------------------------------
#- is_cluster ()
#-----------------------------------------------------------------------------
#- Purpose
#-----------------------------------------------------------------------------
#- Checks if database is a cluster database.  Returns TRUE or FALSE.
#-----------------------------------------------------------------------------

function is_cluster () {
  IS_CLUSTER=$(sqlplus -silent  / as sysdba << EOF
    set heading off feedback off verify off pagesize 0
    whenever oserror exit 1;
    whenever sqlerror exit 2;
    select value from v\$parameter where name = 'cluster_database';
    exit;
EOF
)

  echo $IS_CLUSTER
}

#-----------------------------------------------------------------------------
#- get_timestamp ()
#-----------------------------------------------------------------------------
#- Purpose
#-----------------------------------------------------------------------------
#- Return the current server time formatted as DD-MON-YYYY HH24:MI:SS.
#-----------------------------------------------------------------------------

function get_timestamp () {
#TIMESTAMP=$(sqlplus -silent  / as sysdba << EOF
#    set heading off feedback off verify off pagesize 0
#    whenever oserror exit 1;
#    whenever sqlerror exit 2;
#    select to_char(current_timestamp, 'DD-MON-YYYY HH24:MI:SS')
#    from dual;
#    exit;
#  EOF)
#  echo $TIMESTAMP
  echo `date +"%d-%b-%Y %H:%M:%S"`
}

#-----------------------------------------------------------------------------
# run_it_db_log ()
#-----------------------------------------------------------------------------
#- Purpose
#-----------------------------------------------------------------------------
#- Insert a row into the vbms_dba.scheduled_job_log to record the status 
#- of a cron script execution.
#-----------------------------------------------------------------------------

function run_it_db_log () {
#    . ~/.bash_profile > /dev/null
ORACLE_SID=`ps -ef | /bin/grep pmon | /bin/grep -vE /bin/grep | /bin/grep -vE ASM | cut -d_ -f3`
# echo Getting Password from $ORACLE_SID
    VBMSPWD=`sqlplus -s / as sysdba << EOF
      set heading off feedback off verify off pagesize 0
      whenever oserror exit 1;
      whenever sqlerror exit 2;
      select schemapass from vbms_dba.DB_APP_SCHEMAS where schema='VBMS_DBA';
      exit;
EOF
`

    echo "THIS FUNCTION IS INSERTING A ROW TO TRACKING TABLE" > /home/oracle/troubleshooting.txt
    SERVER_NAME=`hostname | tr [a-z] [A-Z]`
    SERVER_ENVIRONMENT=`echo $HOST | cut -f2 -d. | tr [a-z] [A-Z]`
#   ORACLE_SID=`awk -F: '/^[^#]/ {printf "%s",$1}' /etc/oratab`
    END_TIME=$(get_timestamp)
    LOGFILE=`basename $EXEC_LOG`
    RETURNED_MESSAGE="Not Used"
    echo server name is $SERVER_NAME >> /home/oracle/troubleshooting.txt
    echo server environment is $SERVER_ENVIRONMENT >> /home/oracle/troubleshooting.txt
    echo oracle SID is $ORACLE_SID >> /home/oracle/troubleshooting.txt
    echo job category is $JOB_CATEGORY >> /home/oracle/troubleshooting.txt
    echo start time is $start_time >> /home/oracle/troubleshooting.txt
    echo end time is $end_time >> /home/oracle/troubleshooting.txt
    echo logfile is $LOGFILE >> /home/oracle/troubleshooting.txt
    echo logfile is $LOGFILE >> /home/oracle/troubleshooting.txt
    echo returned status is $RETURNED_STATUS >> /home/oracle/troubleshooting.txt
    echo returned message is $RETURNED_MESSAGE >> /home/oracle/troubleshooting.txt
    echo command name is $COMMAND_NAME >> /home/oracle/troubleshooting.txt

#   echo "insert into vbms_dba.all_scheduled_job_log@OEMDB001.PRD.VBMS.VBA.VA.GOV (                \
#              server_name, server_environment, database_sid,              \
#              job_category, start_time, end_time,                         \
#              run_it_log_file_name, returned_status, returned_message,    \
#              command_name                                                \
#            )                                                             \
#            values(                                                       \
#              '${SERVER_NAME}', '${SERVER_ENVIRONMENT}', '${ORACLE_SID}', \
#              '${JOB_CATEGORY}',                                          \
#              to_timestamp('${start_time}', 'DD-Mon-YYYY HH24:MI:SS'),    \
#              to_timestamp('${end_time}',   'DD-Mon-YYYY HH24:MI:SS'),    \
#              '${LOGFILE}', '${RETURNED_STATUS}', '${RETURNED_MESSAGE}',  \
#              '${COMMAND_NAME}'                                           \
#        );"
#   echo "================================================================================================"
    insert_row=$(sqlplus -silent  vbms_dba/$VBMSPWD  << EOF
        set heading off feedback off verify off pagesize 0
        whenever oserror exit 1;
        whenever sqlerror exit 2;
        insert into vbms_dba.all_scheduled_job_log@OEMDB001.PRD.VBMS.VBA.VA.GOV (
              server_name, server_environment, database_sid,
              job_category, important, start_time, end_time,
              run_it_log_file_name, returned_status, returned_message,
              command_name
            )
            values(
              '${SERVER_NAME}', '${SERVER_ENVIRONMENT}', '${ORACLE_SID}',
              '${JOB_CATEGORY}',
              '${IMPORTANT}',
              to_timestamp('${start_time}', 'DD-Mon-YYYY HH24:MI:SS'),
              to_timestamp('${end_time}',   'DD-Mon-YYYY HH24:MI:SS'),
              '${LOGFILE}', '${RETURNED_STATUS}', '${RETURNED_MESSAGE}',
              '${COMMAND_NAME}'
        );
        commit;
        exit;
EOF
)
}

#-----------------------------------------------------------------------------
# get_database_metadata ()
#-----------------------------------------------------------------------------
#- Purpose
#-----------------------------------------------------------------------------
#- Retrieve database parameters from AWS RDS. 
#-----------------------------------------------------------------------------
get_database_metadata() {
    lRETURNVAL=1
    lRETURNTRY=0
    lMAXRETRIES=3
    lDATABASE=$1

    while [[ $lRETURNVAL -gt 0 ]] && [[ $lRETURNTRY -lt $lMAXRETRIES ]]; do
        lRDSINFO=$(aws rds describe-db-instances --db-instance-identifier $lDATABASE 2>&1)
        lRETURNVAL=$?
        if [[ $lRETURNVAL -ne 0 ]]; then
            lRETURNTRY=$(($lRETURNTRY + 1))
        fi

        if [[ $lRETURNTRY -eq $lMAXRETRIES ]]; then
            return 1
        fi
    done

    echo "$lRDSINFO"
    return 0
}

#-----------------------------------------------------------------------------
# generate_password ()
#-----------------------------------------------------------------------------
#- Purpose
#-----------------------------------------------------------------------------
#- Generate database/application password using random generation functions. 
#-----------------------------------------------------------------------------
generate_password() {
    while true; do

        local PASSWORDLENGTH=18
        local TRIMLENGTH=$(($PASSWORDLENGTH - 1))

        local PASSWORD=$(echo $(tr </dev/urandom -dc A-Za-z0-9 | head -c1)$(tr </dev/urandom -dc 'a-zA-Z0-9!#%^*()_+<>=' | head -c$TRIMLENGTH))

        local UPPERCOUNT=$(grep -o '[[:upper:]]' <<<$PASSWORD | wc -l)
        local LOWERCOUNT=$(grep -o '[[:lower:]]' <<<$PASSWORD | wc -l)
        local DIGITCOUNT=$(grep -o '[0-9]' <<<$PASSWORD | wc -l)
        local SPECCOUNT=$(($PASSWORDLENGTH - $UPPERCOUNT - $LOWERCOUNT - $DIGITCOUNT))
        if ! [ $UPPERCOUNT -lt 2 ] && ! [ $LOWERCOUNT -lt 2 ] && ! [ $DIGITCOUNT -lt 2 ] && ! [ $SPECCOUNT -lt 2 ]; then
            break
        fi

    done
    echo "$PASSWORD"
}

#-----------------------------------------------------------------------------
# generate_database_list ()
#-----------------------------------------------------------------------------
#- Purpose
#-----------------------------------------------------------------------------
#- Generate list of aws rds databases using rds describe-db-instances.  
#-----------------------------------------------------------------------------
generate_database_list() {
    local DATABASE_LIST=$(aws rds describe-db-instances | jq -r --arg TEAM "$1" '.DBInstances[] | select( .TagList[] | select(.Key=="ProductLine") | select(.Value==$TEAM)) | .DBInstanceIdentifier')
    echo "$DATABASE_LIST"
}

#-----------------------------------------------------------------------------
# set_vault_environment ()
#-----------------------------------------------------------------------------
#- Purpose
#-----------------------------------------------------------------------------
#- Based on MACADDR and VPCID values, set and export environment variables
#- for the desired Vault domain (DEV, STAGE, PROD). This allows Vault 
#- command line commands to be executed to retrieve key/value pairs for the 
#- specified domain. 
#-----------------------------------------------------------------------------

set_vault_environment () {
        MACADDR=$( curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs )
        VPCID=$( curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/${MACADDR}/vpc-id )

        if [[ "$VPCID" == "vpc-af38e7cb" ]]; then
                export VAULT_ADDR='https://vault.dev8.bip.va.gov'
                export VAULT_SECRET='dev8-vault'
                export OEM_PATH='secret/platform/database-admin/bip-dev-oem'
                TOKENSECRET=$( aws secretsmanager get-secret-value --secret-id $VAULT_SECRET | jq --raw-output '.SecretString' | jq -r .token)
        elif [[ "$VPCID" == "vpc-bb3de2df" ]]; then
                export VAULT_ADDR='https://vault.stage8.bip.va.gov'
                export VAULT_SECRET='stage8-vault'
                export OEM_PATH='secret/platform/database-admin/bip-stage-oem'
                TOKENSECRET=$( aws secretsmanager get-secret-value --secret-id $VAULT_SECRET | jq --raw-output '.SecretString' | jq -r .token)
        elif [[ "$VPCID" == "vpc-5e3ae53a" ]]; then
                export VAULT_ADDR='https://vault.prod8.bip.va.gov'
                export VAULT_SECRET='bia-dbas-vault'
                export OEM_PATH='secret/platform/prodops-dba/bip-oem'
                TOKENSECRET=$( aws secretsmanager get-secret-value --secret-id $VAULT_SECRET | jq --raw-output '.SecretString')
        else
                echo "error: VPC could not be determined."
        fi

        export VAULT_TOKEN=$( echo ${TOKENSECRET##* } )
}

