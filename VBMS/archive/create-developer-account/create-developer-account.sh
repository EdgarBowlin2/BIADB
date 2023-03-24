#!/bin/bash
# set environment
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/VBMS/local/env

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

if [[ "$AWSACCOUNT" != "D" ]]; then
    echo "ERROR: This script is only to be executed in development environments."
    exit 1
fi

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
MASTER_PASSWORD=$(vault kv get -field=master-password secret/platform/candp-dbas/$DATABASE)

sqlplus $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
start create-developer-account $USERNAME $PASSWORD
exit
EOF

echo ""
echo "An account with elevated privileges has been created for you in the $DATABASE database instance."
echo ""
echo "Username: $USERNAME"
echo "Password: $PASSWORD"
echo ""
echo "Database Connection Information:"
echo "Endpoint (Host): $HOST"
echo "Port: $PORT"
echo "SID: $SID"
echo ""
echo "Please tag @cp-dba in Slack for any assistance."
echo ""
