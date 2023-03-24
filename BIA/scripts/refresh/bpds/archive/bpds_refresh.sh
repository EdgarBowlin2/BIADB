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
#
#
################################################################################

########################################
#init scripts
########################################

. ~/.bash_profile > /dev/null
. ~/scripts/functions/functionsJR.sh > /dev/null

########################################
#constants
########################################

export basedir=/home/oracle/scripts/refresh/bpds
export email=do_not_reply@va.gov
export refreshdb=bpds-prodtest
export stackname=bpds-prodtest-orcl-replica
export instancename=bpds-prodtest
export refreshlog=$basedir/logs/refresh.log

#Vault
export VAULT_ADDR="https://vault.prod8.bip.va.gov/"
export OEMServer=project-bip-dba-oem; OEMPort=3872

########################################
#parameters
########################################
#$export basedir=$1
#$export refreshdb=$2
#$export stackname=$3
#$export instancename=$4
#$export email=do_not_reply@va.gov
#$export refreshlog=$basedir/logs/refresh.log


########################################
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

#Check database status
export DBSTATUS=`sqlplus -s /@${refreshdb}<<EOF
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
    sqlplus -s /@${refreshdb} << EOF
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
$basedir/db_refresh.sh ${stackname} ${instancename} ${refreshdb} >> ${refreshlog}
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
    sqlplus -s /@${refreshdb} << EOF
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
SysmanPassword=$(vault kv get -field=sysman secret/platform/prodops-dba/bip-oem)

#get endpoint Address
rdsendpoint_Address=$(sudo aws rds describe-db-instances --query 'DBInstances[*].[Endpoint.Address]' --filters Name=db-instance-id,Values=$instancename --output text)

echo $rdsendpoint_Address

#resyncAgent agent on OMS Server
/home/oracle/emcli/emcli login -user=sysman -pass="${SysmanPassword}"
/home/oracle/emcli/emcli resyncAgent -agent=$rdsendpoint_Address:$OEMPort
#ssh oracle@$OEMServer " . oem13c.env; emcli login -user=sysman -pass="${SysmanPassword}"; emcli resyncAgent -agent=$rdsendpoint_Address:$OEMPort"
exit 0
