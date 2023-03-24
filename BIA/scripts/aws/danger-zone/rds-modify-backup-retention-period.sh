#!/bin/bash
# set environment
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/env
FORCE=0

# parse command line
usage() {
    echo "usage: $0 [ -t SYSTEM-TEAM-TAG ] [ -v VALUE IN DAYS (14-35) ] [ -f force ]" 1>&2
    exit 1
}

while getopts ":t:v:f" options; do
    case "${options}" in
        t)
            TEAM=${OPTARG}
            ;;
        v)
            VALUE=${OPTARG}

            NUMBER_CHECK='^[0-9]+$'
            if ! [[ $VALUE =~ $NUMBER_CHECK ]]; then
                echo "ERROR: -v is not a number"
                usage
            fi

            if [ $VALUE -lt 14 ] || [ $VALUE -gt 35 ]; then
                echo "ERROR: -v must be between 14 and 35"
                usage
            fi
            ;;
        f)
            FORCE=1
            echo "FORCE option chosen.  Backup retention periods might be lowered."
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

if [[ -z "$TEAM" ]]; then
    echo "ERROR: -t is a mandatory parameter."
    usage
fi

DBARRAY=($(generate_database_list "$TEAM"))
if [ "${#DBARRAY[@]}" -eq 0 ]; then
    echo "ERROR: -t ${TEAM} returned with zero objects."
    exit 1
fi

# begin
for DATABASE in "${DBARRAY[@]}"; do

    RDSINFO=$(get_database_metadata "$DATABASE")

    if [[ $? -ne 0 ]]; then
        echo "aws rds describe-db-instances failed for $DATABASE"
    fi
    
    PENDING=$(echo $RDSINFO | jq -r .DBInstances[].PendingModifiedValues)
    RETENTION=$(echo $RDSINFO | jq -r .DBInstances[].BackupRetentionPeriod)

    if [[ "$PENDING" == "{}" ]]; then
        if [[ $RETENTION -lt $VALUE ]] || [[ $FORCE -eq 1 ]]; then
            echo $DATABASE is being modified to a retention period of $VALUE days.
            aws rds modify-db-instance --db-instance-identifier $DATABASE --backup-retention-period $VALUE --apply-immediately
        else
            echo $DATABASE has a retenion period greater than $VALUE.
        fi
    else
        echo $DATABASE has pending modifications.
    fi

done
