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

TEAMDBARN=($(aws rds describe-db-instances | jq -r --arg TEAM "$TEAM" '.DBInstances[] | select( .TagList[] | select(.Key=="ProductLine") | select(.Value==$TEAM)) | .DBInstanceArn'))
CERTDBARN=($(aws rds describe-pending-maintenance-actions | jq -r ' .PendingMaintenanceActions[] | select ( .PendingMaintenanceActionDetails[] | .Action=="ca-certificate-rotation" ) | .ResourceIdentifier'))

UPGRADELIST=($(comm --check-order -12 <(printf '%s\n' "${TEAMDBARN[@]}" | sort) <(printf '%s\n' "${CERTDBARN[@]}" | sort)))

# get metadata for all databases
RDSINFO=$(aws rds describe-db-instances)

echo "The following databases will undergo a ca-certificate-rotation during their next maintenance window:"
echo ''

for dbarn in "${UPGRADELIST[@]}"; do
    echo $RDSINFO | jq -r --arg dbarn "$dbarn" ' .DBInstances[] | select(.DBInstanceArn==$dbarn) | .DBInstanceIdentifier'
done

echo ''
while true; do
    read -p "Schedule these upgrades? (y/n) " yn
    case $yn in
        [Yy]*)
            echo "Scheduling upgrades..."
            break
            ;;
        [Nn]*)
            echo "Exiting without changes..."
            exit
            ;;
        *) echo "Invalid response." ;;
    esac
done

for dbarn in "${UPGRADELIST[@]}"; do
    aws rds apply-pending-maintenance-action --resource-identifier $dbarn --apply-action ca-certificate-rotation --opt-in-type next-maintenance
done

