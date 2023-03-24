#!/bin/bash
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/env

# parse command line
usage() {
    echo "usage: $0 [ -r REPLICATION-INSTANCE-IDENTIFIER ] [ -s SNS TOPIC NAME ] [ -f force ]" 1>&2
    exit 1
}

while getopts ":r:s:f" options; do
    case "${options}" in
        r)
            INSTANCE=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
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

if [[ -z "$INSTANCE" ]]; then
    echo "ERROR: -r is a mandatory parameter."
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
    CPUUtilization,85,GreaterThanOrEqualToThreshold
    FreeableMemory,268435456,LessThanOrEqualToThreshold
    FreeStorageSpace,5368709120,LessThanOrEqualToThreshold
    ReadLatency,100,GreaterThanOrEqualToThreshold
    WriteLatency,100,GreaterThanOrEqualToThreshold
)

for METRIC in "${METRICS[@]}"; do

    METRICNAME=$(echo $METRIC | cut -d, -f1)
    THRESHOLD=$(echo $METRIC | cut -d, -f2)
    COMPARISON=$(echo $METRIC | cut -d, -f3)

    if [[ FORCE -ne 1 ]]; then
        ALARM_CHECK=$(aws cloudwatch describe-alarms-for-metric --namespace AWS/DMS --metric-name $METRICNAME --dimensions Name=ReplicationInstanceIdentifier,Value=$INSTANCE | jq -r '.MetricAlarms[] | .AlarmName')

        if [[ ! -z "$ALARM_CHECK" ]]; then
            echo "Alarm for $METRICNAME already exists."
            continue
        fi
    fi

    echo "Creating alarm for $METRICNAME..."

    aws cloudwatch put-metric-alarm \
        --alarm-name DMS_${METRICNAME}_${INSTANCE} \
        --namespace AWS/DMS \
        --metric-name $METRICNAME \
        --dimensions Name=ReplicationInstanceIdentifier,Value=$INSTANCE \
        --statistic Average \
        --period 300 \
        --evaluation-periods 3 \
        --datapoints-to-alarm 3 \
        --threshold $THRESHOLD \
        --comparison-operator $COMPARISON \
        --treat-missing-data missing \
        --alarm-actions $SNSARN:$SNSTOPIC

done
