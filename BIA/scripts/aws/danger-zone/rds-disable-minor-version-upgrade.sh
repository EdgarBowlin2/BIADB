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

# get list of team databases with auto minor version upgrade enabled
DISABLELIST=($(aws rds describe-db-instances | jq -r --arg TEAM "$TEAM" '.[] | .[] | select( .TagList[] | select(.Key=="ProductLine") | select(.Value==$TEAM)) | select ( .AutoMinorVersionUpgrade == true ) | .DBInstanceIdentifier'))

echo "The following databases will have auto minor version upgrade disabled:"
echo ''

for db in "${DISABLELIST[@]}"; do
    echo $db
done

echo ''
while true; do
    read -p "Apply these changes? (y/n) " yn
    case $yn in
        [Yy]*)
            echo "Applying changes..."
            break
            ;;
        [Nn]*)
            echo "Exiting without changes..."
            exit
            ;;
        *) echo "Invalid response." ;;
    esac
done

for db in "${DISABLELIST[@]}"; do
    aws rds modify-db-instance --db-instance-identifier $db --no-auto-minor-version-upgrade --apply-immediately
done
