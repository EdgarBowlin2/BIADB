#!/bin/bash
################################################################################
#
#   Name:       refresh.sh
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
#
#   Change: 10/19/22 Changed emcli to run locally and point to new RHEL8 OEM - PEL 
#   Change: 03/08/23 Updated to source github environment files. EMCLI location updated - PEL
#
################################################################################

########################################
#init scripts
########################################
 . ~/.bash_profile
cd ~/scripts
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/env
. $GITROOT/BIA/env
########################################
#constants
########################################
export basedir=$GITROOT/BIA/refresh/bpds
export email=do_not_reply@va.gov
export refreshdb=bpds-preprod
export stackname=bpds-preprod-orcl-replica
export instancename=bpds-preprod
export refreshlog=$basedir/logs/preprod_refresh.log

#Vault
set_vault_environment
VAULT_PATH=secret/platform/bia-dbas/$refreshdb
#variables
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
HOST=$(vault kv get -field=endpoint $VAULT_PATH)
PORT=$(vault kv get -field=port  $VAULT_PATH)
SID=$(vault kv get -field=sid  $VAULT_PATH)
BIP_DBA=$(vault kv get -field=BIP_DBA  $VAULT_PATH)

echo connecting with sqlplus -s BIP_DBA/"$BIP_DBA"@$HOST:$PORT/$SID
#Check database status
export DBSTATUS=`sqlplus -s BIP_DBA/"$BIP_DBA"@$HOST:$PORT/$SID<<EOF
set echo off
set feedback off
set termout off
set pages 0
select open_mode from v\\$database;
exit
EOF`

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
    sqlplus -s BIP_DBA/"$BIP_DBA"@$HOST:$PORT/$SID << EOF
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
$basedir/db_refresh_preprod.sh ${stackname} ${instancename} ${refreshdb} >> ${refreshlog}
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
    sqlplus -s BIP_DBA/"$BIP_DBA"@$HOST:$PORT/$SID<<EOF
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
#    exit 0

fi


echo "Pushing OEM Agent to Resync..." | tee -a ${refreshlog}
#login to HarshiCorp vault
vault login $VAULT_TOKEN
SysmanPassword=$(vault kv get -field=sysman secret/platform/bia-dbas/oem)
OEMPort=$(vault kv get -field=oem_port secret/platform/bia-dbas/oem)
#get endpoint Address
rdsendpoint_Address=$(aws rds describe-db-instances --query 'DBInstances[*].[Endpoint.Address]' --filters Name=db-instance-id,Values=$instancename --output text)

echo $rdsendpoint_Address

#resyncAgent agent on OMS Server
emcli login -user=sysman -pass="${SysmanPassword}"
emcli resyncAgent -agent=$rdsendpoint_Address:$OEMPort
exit 0
