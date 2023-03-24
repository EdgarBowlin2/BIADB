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

if [[ "$AWSACCOUNT" != "D" ]]; then
    echo "ERROR: This script is only to be executed in development environments."
    exit 1
fi

if [[ -z "$DATABASE" ]]; then
    echo "ERROR: -d is a mandatory parameter."
    usage
fi

#begin
TENANT=${DATABASE%-*}
set_vault_environment

# CREATE DEV ACCOUNT
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

LINKS_RO_PASSWORD="$(generate_password)"

sqlplus $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
start create-links-user $LINKS_RO_PASSWORD
GRANT CREATE DATABASE LINK TO LINKS_RO;
exit
EOF

# add secret for LINKS_RO to tenant vault
ENVIRONMENT=${DATABASE##*-}
TENANT_PATH=$(vault kv get -field=$TENANT secret/platform/candp-dbas/tenant-secret-path)

if [[ ! -z "$TENANT_PATH" ]]; then
    vault kv patch $TENANT_PATH/database/$ENVIRONMENT LINKS_RO=$LINKS_RO_PASSWORD
else
    echo tenant-secret-path for $TENANT is not present in Vault.
fi

# CREATE STAGE ACCOUNTS
# set stage vault environment
export VAULT_ADDR='https://vault.stage8.bip.va.gov'
TOKENSECRET=$(aws secretsmanager get-secret-value --secret-id vbmsdba-stage-vault | jq --raw-output '.SecretString' | jq -r .token)
export VAULT_TOKEN=$(echo ${TOKENSECRET##* })

DBARRAY=($(vault kv list secret/platform/candp-dbas | grep $TENANT))

for STAGE_DB in "${DBARRAY[@]}"; do

    STAGE_VAULT_JSON=$(vault kv get -format=json secret/platform/candp-dbas/$STAGE_DB)
    STAGE_LINK_NAME=${STAGE_DB//-/_}
    STAGE_HOST=$(echo $STAGE_VAULT_JSON | jq -r '.data.data | .endpoint')
    STAGE_PORT=$(echo $STAGE_VAULT_JSON | jq -r '.data.data | .port')
    STAGE_SID=$(echo $STAGE_VAULT_JSON | jq -r '.data.data | .sid')
    STAGE_MASTER=$(echo $STAGE_VAULT_JSON | jq -r '.data.data | .["master-user"]')
    STAGE_MASTER_PASSWORD=$(echo $STAGE_VAULT_JSON | jq -r '.data.data | .["master-password"]')
    STAGE_LINKS_RO_PASSWORD="$(generate_password)"

    sqlplus $STAGE_MASTER/"$STAGE_MASTER_PASSWORD"@$STAGE_HOST:$STAGE_PORT/$STAGE_SID <<EOF
start create-links-user $STAGE_LINKS_RO_PASSWORD
exit
EOF

    sqlplus links_ro/"$LINKS_RO_PASSWORD"@$HOST:$PORT/$SID <<EOF
start create-database-link $STAGE_LINK_NAME $STAGE_LINKS_RO_PASSWORD $STAGE_HOST $STAGE_PORT $STAGE_SID
exit
EOF

done

sqlplus $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
REVOKE CREATE DATABASE LINK FROM LINKS_RO;
exit
EOF
