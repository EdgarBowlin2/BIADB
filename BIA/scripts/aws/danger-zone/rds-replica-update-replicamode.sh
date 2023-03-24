#!/bin/bash
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/env

# parse command line
usage() {
    echo "usage: $0 [ -t SYSTEM-TEAM-TAG ]" 1>&2
    exit 1
}

while getopts ":t:" options; do
    case "${options}" in
        t)
            TEAM=${OPTARG}
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

# get RDS information for us-gov-west-1
export AWS_DEFAULT_REGION=us-gov-west-1
WESTINFO=$(aws rds describe-db-instances)

# get RDS information for us-gov-east-1
export AWS_DEFAULT_REGION=us-gov-east-1
EASTINFO=$(aws rds describe-db-instances)

# for each database
for db in "${DBARRAY[@]}"; do

    # check to see if it has a replica in us-gov-east-1
    REPLICA_ARN=$(echo $WESTINFO | jq --arg db "$db" -r '.DBInstances[] | select(.DBInstanceIdentifier==$db) | .ReadReplicaDBInstanceIdentifiers[]')
    if [[ "$REPLICA_ARN" =~ ^arn ]]; then

        # compare DBInstanceIdentifier
        EASTNAME=$(echo $REPLICA_ARN | awk -F: '{print $NF}')

        # check replica mode
        REPLICAMODE=$(echo $EASTINFO | jq --arg db "$EASTNAME" --arg key "$key" -r '.DBInstances[] | select(.DBInstanceIdentifier==$db) | .ReplicaMode')

        if [[ "$REPLICAMODE" == "open-read-only" ]]; then
            echo The replica database $db is in open-read-only mode and will be modified to mounted mode.
            aws rds modify-db-instance --db-instance-identifier $EASTNAME --replica-mode mounted --apply-immediately
        fi

    fi

done
