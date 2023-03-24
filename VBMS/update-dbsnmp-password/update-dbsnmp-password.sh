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

# begin
set_vault_environment

SYSMAN_PASSWORD=$(vault kv get -field=sysman secret/platform/candp-dbas/oem)
DBSNMP_PASSWORD="$(generate_password)"
OLD_DBSNMP_PASSWORD=$(vault kv get -field=DBSNMP secret/platform/candp-dbas/$DATABASE)

echo "Updating DBSNMP password in OEM."

$EMCLI_HOME/emcli logout
$EMCLI_HOME/emcli login -username=sysman -password=$SYSMAN_PASSWORD
$EMCLI_HOME/emcli sync
$EMCLI_HOME/emcli update_db_password \
    -target_name="${DATABASE}" \
    -user_name="DBSNMP" \
    -change_at_target="no" \
    -change_all_references="yes" \
    -old_password="${OLD_DBSNMP_PASSWORD}" \
    -new_password="${DBSNMP_PASSWORD}" \
    -retype_new_password="${DBSNMP_PASSWORD}"

echo "Waiting 15 seconds for OEM job to complete."

sleep 15

echo "Updating DBSNMP Passowrd in database."

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
start update-dbsnmp-password $DBSNMP_PASSWORD
exit
EOF

echo "Updating DBSNMP Password in Vault."

vault kv patch secret/platform/candp-dbas/$DATABASE DBSNMP=$DBSNMP_PASSWORD
