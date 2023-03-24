#!/bin/bash
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/env

# parse command line
usage() {
    echo "usage: $0 [ -d DB-INSTANCE-IDENTIFIER ]" 1>&2
    exit 1
}

while getopts ":d:" options; do
    case "${options}" in
        d)
            DATABASE=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
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

if [[ -z "$DATABASE" ]]; then
    echo "ERROR: -d is a mandatory parameter."
    usage
fi

#begin
RDSINFO=$(get_database_metadata "$DATABASE")

if [[ $? -ne 0 ]]; then
    echo "aws rds describe-db-instances failed for $DATABASE"
    exit 1
fi

STATUS=$(echo $RDSINFO | jq -r .DBInstances[].DBInstanceStatus)

if [[ "$STATUS" != "available" ]]; then
    echo "Database is not in an available state."
    return 1 2>/dev/null || exit 1
fi

METRICS=(
    BurstBalance
    CPUUtilization
    DatabaseConnections
    DiskQueueDepth
    FreeableMemory
    FreeStorageSpace
    ReadIOPS
    ReplicaLag
    WriteIOPS
)

declare -A ALARM_NAME

for i in "${!METRICS[@]}"; do
    ALARM_NAME[$i]=$(aws cloudwatch describe-alarms-for-metric --namespace AWS/RDS --metric-name ${METRICS[$i]} --dimensions Name=DBInstanceIdentifier,Value=$DATABASE | jq -r '.MetricAlarms[] | .AlarmName')
done

for ALARM in "${ALARM_NAME[@]}"; do
    if [[ ! -z "$ALARM" ]]; then
        echo "$ALARM is being deleted."
        aws cloudwatch delete-alarms --alarm-name ${ALARM}
    fi
done
