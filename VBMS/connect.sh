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

sqlplus $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID
