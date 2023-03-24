#!/bin/bash
# set environment
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/VBMS/local/env

# begin
TEAM="CandP"
DBARRAY=($(generate_database_list "$TEAM"))
if [ "${#DBARRAY[@]}" -eq 0 ]; then
    echo "ERROR: -t ${TEAM} returned with zero objects."
    exit 1
fi

set_vault_environment

for DATABASE in "${DBARRAY[@]}"; do

    RDSINFO=$(get_database_metadata "$DATABASE")

    if [[ $? -ne 0 ]]; then
        echo "aws rds describe-db-instances failed for $DATABASE"
    fi

    HOST=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Address)
    PORT=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Port)
    SID=$(echo $RDSINFO | jq -r .DBInstances[].DBName)
    MASTER=$(echo $RDSINFO | jq -r .DBInstances[].MasterUsername)
    MASTER_PASSWORD=$(vault kv get -field=master-password secret/platform/candp-dbas/$DATABASE)

    echo "Executing BLAST on $DATABASE."

    sqlplus -s $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
start blast
exit
EOF

done
