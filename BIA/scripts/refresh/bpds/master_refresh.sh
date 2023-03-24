#!/bin/bash
#------------------------------------------------------------------------------
#
#   Name:       master_refresh.sh
#   Create:     22-SEP-2020
#   Author:     Matt Brady
#   Platform:   Linux
#   Purpose:    Refresh RDS instance
#
#   Parameters:
#
#   Prereqs:    -
#               -
#               -
#------------------------------------------------------------------------------
#  Revision History
#------------------------------------------------------------------------------
#
#  16-JUN-2022 Edgar Bowlin
#              Modified Matt's original script to execute on our dev toolbox
#              server against a test database. After successfully testing  
#              on the test server and DB, the script will be copied to our
#              production toolbox server and executed against the prod DB, 
#              bpds-prodtest.  This will complete the migration of refresh
#              for bpds-prodtest from its original server to the BIP DBA Team
#              server, project-bia-dba-toolbox, where our team can more 
#              readily manage the script(s) and database. 
#
#------------------------------------------------------------------------------
#
# 21-JUL-2022 Edgar Bowlin
# 	      Due to issues in BIP Dev environment, PROD environment was used
#             to debug and revise master_refresh.sh and db_refresh.sh scripts
#             to successfully execute in the BIP PROD AWS environment. Only
#             minor syntax corrections have been made, and one additional 
#             variable is being passed from master_refresh.sh to db_refresh.sh.
#             This database refresh process in now working in the BIP Prod
#             Environment and may be duplicated for additional databases
#             as needed.
#             Revisions
#             Name changed from bpds_refresh.sh to master_refresh.sh
#             BIP_DBA variable passed to db_refresh as passwd variable. 
#             Additional echo statements added, and all echo statements 
#             revised to provide as much information as possible. New
#             Oracle oem cli commands are used on current server, replacing
#             previous commands requiring secure shell to oem server to
#             resync replica database to oem agent. 
# 
#------------------------------------------------------------------------------

########################################
#  Set environment
########################################
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/BIA/env
. $GITROOT/env

#--------------------------------------
#- Include global functions library.
#--------------------------------------
. $SCRIPT_DIR/functions/functions.sh


########################################
# constants
########################################

# export basedir=/home/oracle/scripts/refresh/bpds
# export email=do_not_reply@va.gov
# export refreshdb=bpds-prodtest
# export stackname=bpds-prodtest-orcl-replica
# export instancename=bpds-prodtest
# export refreshlog=$basedir/logs/refresh.log

export basedir=/home/oracle/bia-devel/BIA/scripts/refresh/bpds
export email=do_not_reply@va.gov
export refreshdb=patrick-replica
export stackname=patrick-stack
#export instancename=ORCL
export instancename=patrick-replica
export refreshlog=$basedir/logs/refresh.log

#Vault
#----------------------------------------------------
#  Need syntax for dev environment - prod env vault
#  commands won't execute.  
#----------------------------------------------------
# export VAULT_ADDR="https://vault.prod8.bip.va.gov/"
# export VAULT_TOKEN="s.DhN4Kay0Lj2Pdp9WHxUWYbko"

export connectstr="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=patrick-replica.cetxxdbd6our.us-gov-west-1.rds.amazonaws.com)(PORT=1521))(CONNECT_DATA=(SERVER=DEDICATED)(SID=ORCL)))"
#export OEMServer=project-bip-dba-oem; OEMPort=3872
export OEMServer=project-bia-dba-prod-oem-rhel8; OEMPort=3872
export BIP_DBA=`vault kv get -field=BIP_DBA secret/platform/bia-dbas/patrick-replica`

#######################################
# variables
########################################

#dtStamp=`date +%m%d%y.%H%M`
export dtStamp=`date +%Y-%m-%d`
export day=`date +"%A"`

cd ${basedir}
rm -f ${reportout}
rm -f *.csv

##########################################################
# Run Pre Refresh Steps
##########################################################

#Check database status
# export DBSTATUS=`sqlplus -s /@${refreshdb}<<EOF
# set echo off
# set feedback off
# set termout off
# set pages 0
# select open_mode from v\\$database;
# exit
# EOF`

export DBSTATUS=`sqlplus -s dbadmin/$BIP_DBA@$connectstr<<EOF
set echo off
set feedback off
set termout off
set pages 0
select open_mode from v\\$database;
exit
EOF` 

echo $DBSTATUS

if [[ "$DBSTATUS" != "READ WRITE" ]]; then
    echo "*** Database Status is not open.  Please investigate.  Exiting..."
    exit 1
 else
    echo "Database Status is Open."
fi


#Run SQL to get user info

if [[ -f ${basedir}/pre_refresh_tasks/users.sql ]]; then
    echo "" | tee -a ${refreshlog}
    echo "Running Pre Refresh script..." | tee -a ${refreshlog}
    sqlplus -s dbadmin/$BIP_DBA@$connectstr << EOF
      spool ${refreshlog} append
      @${basedir}/pre_refresh_tasks/users.sql
      spool off
EOF
else
echo "Not Running. Pre Refresh Script not found."
exit 1
fi
SQL_STATUS=$?

if [ $SQL_STATUS -ne 0 ]; then
    echo "*** SQL script reported errors.  Please investigate.  Exiting..."
    exit 1
 else
    echo "SQL script completed"
 fi

##########################################################
# Run Refresh Steps
##########################################################

#Run AWS cli Refresh
$basedir/db_refresh.sh ${stackname} ${instancename} ${refreshdb} ${BIP_DBA}>> ${refreshlog}
CLI_STATUS=$?
if [ $CLI_STATUS -ne 0 ]; then
    echo "*** CLI script reported errors. Please investigate. Exiting..."
    exit 1
  else
    echo "CLI script completed, Refresh Completed Successfully.  Beginning Post Steps."
fi

##########################################################
# Run Post Refresh Steps
##########################################################

if [[ ! -f ${basedir}/post_refresh_tasks/add_users.sql ]]; then
        echo "Error.... File Not Found"
        exit 1
fi

#Run SQL to get update user info
if [[ -f ${basedir}/post_refresh_tasks/add_users.sql ]]; then
    echo "" | tee -a ${refreshlog}
    echo "Running Post Refresh script..." | tee -a ${refreshlog}
    sqlplus -s dbadmin/$BIP_DBA@$connectstr << EOF
      spool ${refreshlog} append
      @${basedir}/post_refresh_tasks/add_users.sql
      spool off
EOF
else
echo "Not Running. Post Refresh Script not found."
exit 1
fi
SQL_STATUS=$?


if [ $SQL_STATUS -ne 0 ]; then
    echo "*** SQL script reported errors.  Please investigate.  Exiting..."
    exit 1
 else
    echo "Refresh Completed Successfully"
    echo "0"
fi

echo "Pushing OEM Agent to Resync..." | tee -a ${refreshlog}
#login to HarshiCorp vault
#export VAULT_TOKEN="s.DhN4Kay0Lj2Pdp9WHxUWYbko"
#vault login $VAULT_TOKEN
#SysmanPassword=$(vault kv get -field=sysman secret/platform/prodops-dba/bip-oem)
SysmanPassword="uaY439u4thtJi8aF7aRj"

#get endpoint Address
rdsendpoint_Address=$(aws rds describe-db-instances --query 'DBInstances[*].[Endpoint.Address]' --filters Name=db-instance-id,Values=$instancename --output text)

echo $rdsendpoint_Address

#resyncAgent agent on OMS Server
#ssh oracle@$OEMServer " . oem13c.env; emcli login -user=sysman -pass="${SysmanPassword}"; emcli resyncAgent -agent=$rdsendpoint_Address:$OEMPort"

$EMCLI_HOME/emcli login -user=sysman -pass="${SysmanPassword}"; 
$EMCLI_HOME/emcli resyncAgent -agent=$rdsendpoint_Address:3872

/usr/sbin/sendmail -v "edgar.bowlin@va.gov, patrick.lynn@va.gov, connor.northrop@va.gov, kingsley.ukiwo@va.gov" -s "Database Refresh for patrick-replica Complete" < /home/oracle/scripts/bia-devel/BIA/scripts/refresh/bpds/logs/refresh.log


echo All Done!
exit 0 
