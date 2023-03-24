#!/bin/bash
################################################################################
#
#   Name:       report_dropin.sh
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
#   Change:
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

export basedir=/home/oracle/scripts/refresh/mbms
export email=do_not_reply@va.gov
export refreshdb=mbms-prodtest-old
export stackname=mbms-prodtest-orcl-replica
export instancename=mbms-prodtest-k8
export refreshlog=$basedir/logs/refresh.log
########################################
#parameters
########################################


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

if [[ -f ${basedir}/pre_refresh_tasks/prodtest_users.sql ]]; then
    echo "" | tee -a ${refreshlog}
    echo "Running Pre Refresh script..." | tee -a ${refreshlog}
    sqlplus -s /@${refreshdb} << EOF
      spool ${refreshlog} append
      @${basedir}/pre_refresh_tasks/prodtest_users.sql
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
$basedir/mbms_prodtest_refresh_new.sh ${stackname} ${instancename} ${refreshdb} >> ${refreshlog}
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

if [[ ! -f ${basedir}/post_refresh_tasks/mbms_add_prodtest_users.sql ]]; then
        echo "Error.... File Not Found"
        exit 1
fi

#Run SQL to get update user info
#UPDATE: HARDCODED refresh db 10/02/2020
#can change to refreshdb after initial run
if [[ -f ${basedir}/post_refresh_tasks/mbms_add_prodtest_users.sql ]]; then
    echo "" | tee -a ${refreshlog}
    echo "Running Post Refresh script..." | tee -a ${refreshlog}
    sqlplus -s /@mbms-prodtest << EOF
      spool ${refreshlog} append
      @${basedir}/post_refresh_tasks/mbms_add_prodtest_users.sql
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
    exit 0
fi

