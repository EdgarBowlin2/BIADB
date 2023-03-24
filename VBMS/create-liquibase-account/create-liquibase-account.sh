#!/bin/bash
# set environment
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/VBMS/local/env

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

LIQUID_PASSWORD="$(generate_password)"

RDSINFO=$(get_database_metadata "$DATABASE")

if [[ $? -ne 0 ]]; then
    echo "aws rds describe-db-instances failed for $DATABASE"
    exit 1
fi

HOST=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Address)
PORT=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Port)
SID=$(echo $RDSINFO | jq -r .DBInstances[].DBName)
MASTER=$(echo $RDSINFO | jq -r .DBInstances[].MasterUsername)
MASTER_PASSWORD=$(vault kv get -field=master-password secret/platform/candp-dbas/$DATABASE)

sqlplus $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
start create-liquibase-account $LIQUID_PASSWORD
exit
EOF

echo "Adding secrets to vault."

vault kv patch secret/platform/candp-dbas/$DATABASE LIQUIBASE_ADMIN=$LIQUID_PASSWORD

if [[ "$AWSACCOUNT" == "D" ]]; then
    TENANT=${DATABASE%-*}
    ENVIRONMENT=${DATABASE##*-}
    TENANT_PATH=$(vault kv get -field=$TENANT secret/platform/candp-dbas/tenant-secret-path)

    if [[ ! -z "$TENANT_PATH" ]]; then
        vault kv patch $TENANT_PATH/database/$ENVIRONMENT LIQUIBASE_ADMIN=$LIQUID_PASSWORD
    else
        echo tenant-secret-path for $TENANT is not present in Vault.
    fi
fi
