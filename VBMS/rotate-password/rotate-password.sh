#!/bin/bash
# set environment
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/VBMS/local/env

# parse command line
usage() {
    echo "usage: $0 [ -u USERNAME ] [ -d db-instance-identifier ] [ -t ]" 1>&2
    exit 1
}

while getopts ":u:d:t" options; do
    case "${options}" in
        d)
            DATABASE=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
            ;;
        t)
            TEAM=1
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

if [[ -z "$DATABASE" ]] && [[ -z "$TEAM" ]]; then
    echo "ERROR: one of -d or -t must be specified."
    usage
fi

if ! [[ -z "$DATABASE" ]] && ! [[ -z "$TEAM" ]]; then
    echo "ERROR: only one of -d and -t must be specified."
    usage
fi

if [[ -z "$USERNAME" ]]; then
    echo "ERROR: -u is a mandatory parameter."
    usage
fi

# begin
set_vault_environment

if [[ $TEAM -eq 1 ]]; then
    while true; do
        read -p "This will update the password for $USERNAME in ALL databases.  Continue? (y/n) " yn
        case $yn in
            [Yy]*)
                echo "Updating passwords..."
                break
                ;;
            [Nn]*)
                echo "Exiting without changes..."
                exit
                ;;
            *) echo "Invalid response." ;;
        esac
    done
fi

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
        break
    fi

    PASSWORD="$(generate_password)"

    HOST=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Address)
    PORT=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Port)
    SID=$(echo $RDSINFO | jq -r .DBInstances[].DBName)
    MASTER=$(echo $RDSINFO | jq -r .DBInstances[].MasterUsername)
    MASTER_PASSWORD=$(vault kv get -field=master-password secret/platform/candp-dbas/$DATABASE)

    echo "Updating password for $USERNAME in $DATABASE."

    CHANGE_STATUS=`sqlplus $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
start rotate-password $USERNAME $PASSWORD
exit
EOF
`

    if [[ $? -ne 0 ]]; then
        echo "rotate-password failed for $DATABASE."
        if [[ $TEAM -eq 1 ]]; then
            continue
        else
            break
        fi
    fi

    # Check for user does not exist error
    if ! [[ "$CHANGE_STATUS" =~ ORA-01918 ]]; then

        # Update DBA vault area except if username = CP_ASA
        if [[ "$AWSACCOUNT" != "P" ]] && [[ "$USERNAME" = "CP_ASA" ]]; then
            vault kv patch secret/platform/candp-asa/$DATABASE CP_ASA=$PASSWORD
        else
            vault kv patch secret/platform/candp-dbas/$DATABASE $USERNAME=$PASSWORD
        fi

    else
        echo User $USERNAME does not exist in database $DATABASE.
    fi

done
