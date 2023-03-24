#!/bin/bash
# set environment
#7/8/22 Updated for BIA use - PEL
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/BIA/env
. $GITROOT/env

# parse command line
usage() {
    echo "usage: $0 [ -d DB-INSTANCE-IDENTIFIER ]" 1>&2
    exit 1
}

while getopts ":d:" options; do
    case "${options}" in
        d)
            DATABASE=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
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

RDSINFO=$(get_database_metadata "$DATABASE")

if [[ $? -ne 0 ]]; then
    echo "aws rds describe-db-instances failed for $DATABASE"
    exit 1
fi

STATUS=$(echo $RDSINFO | jq -r .DBInstances[].DBInstanceStatus)

if [[ "$STATUS" != "available" ]]; then
    echo "Database is not in an available state."
    return 1 2>/dev/null || exit 1
fi

MASTER_PASSWORD="$(generate_password)"

aws rds modify-db-instance --db-instance-identifier $DATABASE --master-user-password $MASTER_PASSWORD

echo "Waiting for AWS to complete DBADMIN password change."

DBADMIN_RESET_START=0
while [ $DBADMIN_RESET_START -ne 1 ]; do

    RDSINFO=$(get_database_metadata "$DATABASE")

    if [[ $? -ne 0 ]]; then
        echo "aws rds describe-db-instances failed for $DATABASE"
    fi

    PENDING=$(echo $RDSINFO | jq -r .DBInstances[].PendingModifiedValues)
    STATUS=$(echo $RDSINFO | jq -r .DBInstances[].DBInstanceStatus)
    if [[ "$STATUS" == "available" ]] && [[ "$PENDING" == "{}" ]]; then
        DBADMIN_RESET_START=1
    fi
    sleep 5

done

echo "DBADMIN password change complete.  Executing baseline script."

DBSNMP_PASSWORD="$(generate_password)"
BIPDBA_PASSWORD="$(generate_password)"
LIQUID_PASSWORD="$(generate_password)"
VASCAN_PASSWORD="$(generate_password)"

RDSINFO=$(get_database_metadata "$DATABASE")

if [[ $? -ne 0 ]]; then
    echo "aws rds describe-db-instances failed for $DATABASE"
    exit 1
fi

HOST=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Address)
PORT=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Port)
SID=$(echo $RDSINFO | jq -r .DBInstances[].DBName)
MASTER=$(echo $RDSINFO | jq -r .DBInstances[].MasterUsername)

sqlplus $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
start new-instance-setup $BIPDBA_PASSWORD $DBSNMP_PASSWORD $LIQUID_PASSWORD $VASCAN_PASSWORD
exit
EOF

vault kv put secret/platform/bia-dbas/$DATABASE endpoint=$HOST port=$PORT sid=$SID master-password=$MASTER_PASSWORD master-user=$MASTER DBSNMP=$DBSNMP_PASSWORD BIP_DBA=$BIPDBA_PASSWORD LIQUIBASE_ADMIN=$LIQUID_PASSWORD VANSOCSCAN=$VASCAN_PASSWORD

    TENANT=${DATABASE%-*}
    ENVIRONMENT=${DATABASE##*-}
    TENANT_PATH=$(vault kv get -field=$TENANT secret/platform/bia-dbas/tenant-secret-path)

    echo Tenant path is $TENANT_PATH
    if [[ ! -z "$TENANT_PATH" ]]; then
	echo  vault kv put $TENANT_PATH/database/$ENVIRONMENT endpoint=$HOST port=$PORT sid=$SID
        vault kv put $TENANT_PATH/database/$ENVIRONMENT endpoint=$HOST port=$PORT sid=$SID

        if [[ "$AWSACCOUNT" == "D" ]]; then
            vault kv patch $TENANT_PATH/database/$ENVIRONMENT LIQUIBASE_ADMIN=$LIQUID_PASSWORD
        fi
    else
        echo tenant-secret-path for $TENANT is not present in Vault.
    fi
