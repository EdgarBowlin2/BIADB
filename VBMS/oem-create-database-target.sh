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

SYSMAN_PASSWORD=$(vault kv get -field=sysman secret/platform/candp-dbas/oem)

DBSNMP_PASSWORD=$(vault kv get -field=DBSNMP secret/platform/candp-dbas/$DATABASE)
if [[ $? -ne 0 ]]; then
    exit 1
fi

HOST=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Address)
PORT=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Port)
SID=$(echo $RDSINFO | jq -r .DBInstances[].DBName)

$EMCLI_HOME/emcli login -username=sysman -password=$SYSMAN_PASSWORD >/dev/null 2>&1
$EMCLI_HOME/emcli sync >/dev/null 2>&1

$EMCLI_HOME/emcli add_target \
    -name="${DATABASE}" \
    -type="oracle_database" \
    -host="${HOST}" \
    -credentials="UserName:DBSNMP;password:${DBSNMP_PASSWORD};Role:Normal" \
    -properties="SID:"${SID}";Port:"${PORT}";OracleHome:/oracle;MachineName:${HOST}"
