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

# get newest Oracle 19 engine version
NEWENGINE=$(aws rds describe-db-engine-versions --engine oracle-ee | jq -r '.[] | .[] | select(.EngineVersion | startswith("19")) | select ( .ValidUpgradeTarget == [] ) | .EngineVersion')

# get list of Oracle 19 databases for TEAM not on newest engine version
# AND without modifications waiting for the next maintenance window.
UPGRADELIST=($(aws rds describe-db-instances | jq -r --arg NEWENGINE "$NEWENGINE" --arg TEAM "$TEAM" '.[] | .[] | select( .engine = "oracle-ee" ) | select ( .EngineVersion | startswith("19")) | select ( .EngineVersion | contains($NEWENGINE) | not ) | select( .TagList[] | select(.Key=="ProductLine") | select(.Value==$TEAM)) | select ( .PendingModifiedValues == {} ) | .DBInstanceIdentifier'))

echo "The following databases will upgrade to engine $NEWENGINE during their next maintenance window:"
echo ''

for db in "${UPGRADELIST[@]}"; do
    echo $db
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

for db in "${UPGRADELIST[@]}"; do
    aws rds modify-db-instance --db-instance-identifier $db --engine-version $NEWENGINE --no-apply-immediately
done
