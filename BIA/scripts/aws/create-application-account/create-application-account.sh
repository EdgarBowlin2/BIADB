#!/bin/bash
# set environment
GITROOT=$( git rev-parse --show-toplevel )
. $GITROOT/BIA/env
. $GITROOT/env

# parse command line
usage() {
    echo "usage: $0 [ -d DB-INSTANCE-IDENTIFIER ] [ -u USERNAME ]" 1>&2
    exit 1
}

while getopts ":d:u:" options; do
    case "${options}" in
        d)
            DATABASE=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
            ;;
        u)
            USERNAME=$(echo "${OPTARG}" | tr '[:lower:]' '[:upper:]')
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

if [[ -z "$USERNAME" ]]; then
    echo "ERROR: -u is a mandatory parameter."
    usage
fi

#begin
set_vault_environment

TABLESPACE=${USERNAME}_TS
PASSWORD="$(generate_password)"

RDSINFO=$(get_database_metadata "$DATABASE")

if [[ $? -ne 0 ]]; then
    echo "aws rds describe-db-instances failed for $DATABASE"
    exit 1
fi

HOST=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Address)
PORT=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Port)
SID=$(echo $RDSINFO | jq -r .DBInstances[].DBName)
MASTER=$(echo $RDSINFO | jq -r .DBInstances[].MasterUsername)
MASTER_PASSWORD=$(vault kv get -field=master-password secret/platform/bia-dbas/$DATABASE)

echo sqlplus $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID 

sqlplus $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
start create-application-account $USERNAME $PASSWORD $TABLESPACE
exit
EOF

echo "Adding secrets to vault."

vault kv patch -method=rw secret/platform/bia-dbas/$DATABASE $USERNAME=$PASSWORD

if [[ "$AWSACCOUNT" == "D" ]]; then
    TENANT=${DATABASE%-*}
    ENVIRONMENT=${DATABASE##*-}
    TENANT_PATH=$(vault kv get -field=$TENANT secret/platform/bia-dbas/tenant-secret-path)

    if [[ ! -z "$TENANT_PATH" ]]; then
        vault kv patch $TENANT_PATH/database/$ENVIRONMENT $USERNAME=$PASSWORD
    else
        echo tenant-secret-path for $TENANT is not present in Vault.
    fi
fi
