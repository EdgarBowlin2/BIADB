#!/bin/bash
# set environment
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/env

# begin
TEAM="CandP"
DBARRAY=($(generate_database_list "$TEAM"))
if [ "${#DBARRAY[@]}" -eq 0 ]; then
    echo "ERROR: -t ${TEAM} returned with zero objects."
    exit 1
fi

for DATABASE in "${DBARRAY[@]}"; do
    echo "Deleting Cloudwatch alarms for $DATABASE..."
    $GITROOT/aws/danger-zone/cloudwatch-delete-instance-alarms.sh -d $DATABASE
done
