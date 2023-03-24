#!/bin/bash
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/env

# parse command line
usage() {
    echo "usage: $0 [ -d DB-INSTANCE-IDENTIFIER ] [ -s SNS TOPIC NAME ] [ -f force ]" 1>&2
    exit 1
}

while getopts ":d:s:f" options; do
    case "${options}" in
        d)
            DATABASE=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
            ;;
        f)
            FORCE=1
            ;;
        s)
            SNSTOPIC=${OPTARG}
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

if [[ -z "$SNSTOPIC" ]]; then
    echo "ERROR: -s is a mandatory parameter."
    usage
fi

if [[ -z "$DATABASE" ]]; then
    echo "ERROR: -d is a mandatory parameter."
    usage
fi

if [[ $FORCE -eq 1 ]]; then
    echo "FORCE option chosen.  Existing alarms will be updated."
fi

# begin

# VALID COMPARISON OPERATORS
# GreaterThanOrEqualToThreshold
# GreaterThanThreshold
# GreaterThanUpperThreshold
# LessThanLowerOrGreaterThanUpperThreshold
# LessThanLowerThreshold
# LessThanOrEqualToThreshold
# LessThanThreshold

# metric-name,threshold,comparison-operator
METRICS=(
    BurstBalance,25,LessThanOrEqualToThreshold
    CPUUtilization,85,GreaterThanOrEqualToThreshold
    FreeableMemory,268435456,LessThanOrEqualToThreshold
    FreeStorageSpace,5368709120,LessThanOrEqualToThreshold
)

RDSINFO=$(get_database_metadata "$DATABASE")

if [[ $? -ne 0 ]]; then
    echo "aws rds describe-db-instances failed for $DATABASE"
    exit 1
fi

STORAGETYPE=$(echo $RDSINFO | jq -r '.DBInstances[] | .StorageType')

for METRIC in "${METRICS[@]}"; do

    METRICNAME=$(echo $METRIC | cut -d, -f1)
    THRESHOLD=$(echo $METRIC | cut -d, -f2)
    COMPARISON=$(echo $METRIC | cut -d, -f3)

    if [[ "$STORAGETYPE" == "io1" ]] && [[ "$METRICNAME" == "BurstBalance" ]]; then
        continue
    fi

    if [[ FORCE -ne 1 ]]; then
        ALARM_CHECK=$(aws cloudwatch describe-alarms-for-metric --namespace AWS/RDS --metric-name $METRICNAME --dimensions Name=DBInstanceIdentifier,Value=$DATABASE | jq -r '.MetricAlarms[] | .AlarmName')

        if [[ ! -z "$ALARM_CHECK" ]]; then
            echo "Alarm for $METRICNAME already exists."
            continue
        fi
    fi

    echo "Creating alarm for $METRICNAME..."

    aws cloudwatch put-metric-alarm \
        --alarm-name RDS_${METRICNAME}_${DATABASE} \
        --namespace AWS/RDS \
        --metric-name $METRICNAME \
        --dimensions Name=DBInstanceIdentifier,Value=$DATABASE \
        --statistic Average \
        --period 300 \
        --evaluation-periods 3 \
        --datapoints-to-alarm 3 \
        --threshold $THRESHOLD \
        --comparison-operator $COMPARISON \
        --treat-missing-data missing \
        --alarm-actions $SNSARN:$SNSTOPIC

done
