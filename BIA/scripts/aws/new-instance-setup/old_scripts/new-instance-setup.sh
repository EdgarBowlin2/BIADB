#!/bin/bash
# set environment
# 7/8/22 Modifying Script for BIA use - PEL
GITROOT=$( git rev-parse --show-toplevel )
. $GITROOT/VBMS/local/env

# parse command line
usage () { 
	echo "usage: $0 [ -d DB-INSTANCE-IDENTIFIER ]" 1>&2
	exit 1
}

while getopts ":d:" options; do  
	case "${options}" in
		d)
    		DATABASE=`echo "${OPTARG}" | tr '[:upper:]' '[:lower:]'`
      		;;
    	:)
      		echo "ERROR: -${OPTARG} requires an argument."
      		usage
      		;;
    	*)
      		usage
      		;;
  	esac
done

if [[ -z "$DATABASE" ]]; then
	echo "ERROR: -d is a mandatory parameter."
	usage
fi

#begin
set_vault_environment

AWSRDS=$( aws rds describe-db-instances --db-instance-identifier $DATABASE )
STATUS=$( echo $AWSRDS | jq -r .DBInstances[].DBInstanceStatus )

if [[ "$STATUS" != "available" ]]
then
	echo "Database is not in an available state."
	return 1 2>/dev/null || exit 1
fi

DBADMIN_PASSWORD="$(generate_password)"

echo "Updating DBADMIN password in database and Vault."

aws rds modify-db-instance --db-instance-identifier $DATABASE --master-user-password $DBADMIN_PASSWORD

echo "Waiting for AWS to complete DBADMIN password change."

DBADMIN_RESET_START=0
while [ $DBADMIN_RESET_START -ne 1 ]
do
	AWSRDS=$( aws rds describe-db-instances --db-instance-identifier $DATABASE )
	PENDING=$( echo $AWSRDS | jq -r .DBInstances[].PendingModifiedValues )
	STATUS=$( echo $AWSRDS | jq -r .DBInstances[].DBInstanceStatus )
	if [[ "$STATUS" == "available" ]] && [[ "$PENDING" == "{}" ]]
	then
		DBADMIN_RESET_START=1
	fi
	sleep 5
done

echo "Executing baseline script."

DBSNMP_PASSWORD="$(generate_password)"
BIPDBA_PASSWORD="$(generate_password)"
LIQUID_PASSWORD="$(generate_password)"
VASCAN_PASSWORD="$(generate_password)"

AWSRDS=$( aws rds describe-db-instances --db-instance-identifier $DATABASE )
HOST=$( echo $AWSRDS | jq -r .DBInstances[].Endpoint.Address )
PORT=$( echo $AWSRDS | jq -r .DBInstances[].Endpoint.Port )
SID=$( echo $AWSRDS | jq -r .DBInstances[].DBName )

sqlplus dbadmin/"$DBADMIN_PASSWORD"@$HOST:$PORT/$SID <<EOF
start new-instance-setup $BIPDBA_PASSWORD $DBSNMP_PASSWORD $LIQUID_PASSWORD $VASCAN_PASSWORD
exit
EOF

echo "Adding secrets to vault."

vault kv put secret/platform/candp-dbas/$DATABASE dbadmin=$DBADMIN_PASSWORD dbsnmp=$DBSNMP_PASSWORD bip_dba=$BIPDBA_PASSWORD liquibase_admin=$LIQUID_PASSWORD

### 12/01/2021 - Adding tenant secrets blocked by permissions of VBMSDBA vault account

# TENANT=${DATABASE%-*}
# ENVIRONMENT=${DATABASE##*-}
# TENANT_PATH=$( vault kv get -format=json secret/platform/candp-dbas/tenant-secret-path | jq --arg TENANT "$TENANT" -r '.data.data | .[$TENANT]')

# vault kv put $TENANT_PATH/database/$ENVIRONMENT endpoint=$HOST port=$PORT sid=$SID liquibase_admin=$LIQUID_PASSWORD
