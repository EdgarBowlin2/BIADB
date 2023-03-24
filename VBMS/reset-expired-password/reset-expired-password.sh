#!/bin/bash
# set environment
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/VBMS/local/env

# parse command line
usage() {
    echo "usage: $0 [ -d db-instance-identifier ] [ -t ]" 1>&2
    exit 1
}

while getopts ":d:t" options; do
    case "${options}" in
        d)
            DATABASE=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
            ;;
        t)
            TEAM=1
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

if [[ -z "$DATABASE" ]] && [[ -z "$TEAM" ]]; then
    echo "ERROR: one of -d or -t must be specified."
    usage
fi

if ! [[ -z "$DATABASE" ]] && ! [[ -z "$TEAM" ]]; then
    echo "ERROR: only one of -d and -t must be specified."
    usage
fi

# begin
set_vault_environment

if [[ $TEAM -eq 1 ]]; then
    TEAM="CandP"
    DBARRAY=($(generate_database_list "$TEAM"))
    if [ "${#DBARRAY[@]}" -eq 0 ]; then
        echo "ERROR: -t ${TEAM} returned with zero objects."
        exit 1
    fi
else
    DBARRAY=($DATABASE)
fi

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

    echo "Executing refresh-password-expiration on $DATABASE."

    sqlplus -s $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
start reset-expired-password
exit
EOF

done
