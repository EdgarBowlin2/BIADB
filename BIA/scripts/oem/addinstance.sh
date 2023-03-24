#!/bin/bash
#------------------------------------------------------------------------------------
#-  EMCLI Add Instance                                                              - 
#------------------------------------------------------------------------------------
#-  Edgar Bowlin							01-20-2023  -
#------------------------------------------------------------------------------------
#-  This function / script utilizes Oracle Enterprise Manager command line          -
#-  application "add_instance" functionality to add a newly created AWS RDS         - 
#-  database instance to the Oracle Enterprise Manager agent such that the          -
#-  database may be monitored via the OEM application.                              -
#------------------------------------------------------------------------------------
#-  Input									    - 
#------------------------------------------------------------------------------------
#-  addinstance.sh (database name) where database name is the AWS RDS DB Identifier - 
#-  or AWS RDS DB Instance ID.                                                      -
#------------------------------------------------------------------------------------
#-  Output									    -
#------------------------------------------------------------------------------------
#-  The input argument AWS RDS database will be added to the appropriate OEM server -
#-  i.e. dev8, stage8, or prod8.                                                    - 
#------------------------------------------------------------------------------------
#-  Revision History                                                                -
#------------------------------------------------------------------------------------
#-  0.1  Edgar Bowlin  01-20-2023  Test version for peer review/approval.           -
#------------------------------------------------------------------------------------

#----------------------------------------------
#- Set Environment Variables, Paths           -
#----------------------------------------------

GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/BIA/env
. $GITROOT/env

#----------------------------------------------
#- Input Argument                             -
#----------------------------------------------

DATABASE=$1

#----------------------------------------------
#- Retrieve All Database Metadata from AWS    -
#----------------------------------------------

RDSINFO=$(get_database_metadata "$DATABASE") 
HOST=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Address)
PORT=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Port)
SID=$(echo $RDSINFO | jq -r .DBInstances[].DBName)

echo "SID: " $SID "HOST: " $HOST "PORT: " $PORT

#---------------------------------------------
#- Set Vault Environment                     - 
#- Retrieve OEM SYSMAN User Password         -
#- Retrieve Input DB Master User Password    -
#---------------------------------------------
set_vault_environment
SYSMAN_PASS=`vault kv get secret/platform/bia-dbas/oem | grep sysman | awk '{ print $2 }'`
VAULT_PATH=secret/platform/bia-dbas/$DATABASE
DBADMIN_PASS=`vault kv get $VAULT_PATH | grep master-password | awk '{ print $2 }'`

#---------------------------------------------
#- Log in to Oracle Enterprise Manager       -
#- Synchronize OEM                           -
#- Using emcli, add target to OEM            -
#---------------------------------------------

emcli login -username=sysman -password=$SYSMAN_PASS 
emcli sync

#-----------------------------------------------------
#- Echo emcli add_target command and all options and - 
#- option values prior to execution.                 -
#-----------------------------------------------------

#- Echo
echo $EMCLI_HOME/emcli add_target \
    -name="${DATABASE}" \
    -type="oracle_database" \
    -host="${HOST}" \
    -credentials="UserName:DBADMIN;password:"${DBADMIN_PASS}";Role:SYSDBA" \
    -properties="SID:"${SID}";Port:"${PORT}";OracleHome:"/oracle";MachineName:"${HOST}"" \
    -force

#- Execute
$EMCLI_HOME/emcli add_target \
    -name="${DATABASE}" \
    -type="oracle_database" \
    -host="${HOST}" \
    -credentials="UserName:DBADMIN;password:"${DBADMIN_PASS}";Role:sysdba" \
    -properties="SID:"${SID}";Port:"${PORT}";OracleHome:"/oracle";MachineName:"${HOST}"" \
    -force

$EMCLI_HOME/emcli logout

