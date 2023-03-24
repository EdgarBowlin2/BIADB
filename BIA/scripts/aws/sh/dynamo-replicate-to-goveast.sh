#!/bin/bash
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/env

# parse command line
usage() {
    echo "usage: $0 [ -d DYNAMO-TABLE-NAME ]" 1>&2
    exit 1
}

while getopts ":d:" options; do
    case "${options}" in
        d)
            T=${OPTARG}
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

if [[ -z "$T" ]]; then
    echo "ERROR: -d is a mandatory parameter."
    usage
fi

TABLEJSON=$(aws dynamodb describe-table --table-name $T)
TABLEISREPLICATED=$(echo $TABLEJSON | jq -e -r 'any( .Table.Replicas[] ; .RegionName == "us-gov-east-1")?')
if [ $? -ne 0 ]; then
    TABLEISREPLICATED="true"
fi

if [ "$TABLEISREPLICATED" != "true" ]; then
    TABLEISPPR=$(echo $TABLEJSON | jq -e -r '.Table.BillingModeSummary.BillingMode?')
    if [ $? -ne 0 ]; then
        TABLEISPPR="false"
    fi

    if [ "$TABLEISPPR" != "PAY_PER_REQUEST" ]; then
        AUTOSCALEJSON=$(aws application-autoscaling describe-scalable-targets --service-namespace dynamodb --resource-id "table/$T")
        TABLEWSCALABLE=$(echo $AUTOSCALEJSON | jq -e -r 'any( .ScalableTargets[]; .ScalableDimension == "dynamodb:table:WriteCapacityUnits")?')
        if [ $? -ne 0 ]; then
            TABLEWSCALABLE="false"
        fi

        if [ "$TABLEWSCALABLE" != "true" ]; then
            echo Attempting to enable WriteCapacity Auto-Scaling for $T.
            aws application-autoscaling register-scalable-target \
                --service-namespace dynamodb \
                --resource-id "table/$T" \
                --scalable-dimension "dynamodb:table:WriteCapacityUnits" \
                --min-capacity 5 \
                --max-capacity 40000
        else
            echo $T already has WriteCapacity in Auto-Scaling mode.
        fi

        TABLERSCALABLE=$(echo $AUTOSCALEJSON | jq -e -r 'any( .ScalableTargets[]; .ScalableDimension == "dynamodb:table:ReadCapacityUnits")?')
        if [ $? -ne 0 ]; then
            TABLERSCALABLE="false"
        fi

        if [ "$TABLERSCALABLE" != "true" ]; then
            echo Attempting to enable ReadCapacity Auto-Scaling for $T.
            aws application-autoscaling register-scalable-target \
                --service-namespace dynamodb \
                --resource-id "table/$T" \
                --scalable-dimension "dynamodb:table:ReadCapacityUnits" \
                --min-capacity 5 \
                --max-capacity 40000
        else
            echo $T already has ReadCapacity in Auto-Scaling mode.
        fi

        POLICYJSON=$(aws application-autoscaling describe-scaling-policies --service-namespace dynamodb --resource-id "table/$T")
        TABLEHASWPOLICY=$(echo $POLICYJSON | jq -e -r 'any( .ScalingPolicies[]; .ScalableDimension == "dynamodb:table:WriteCapacityUnits")?')
        if [ $? -ne 0 ]; then
            TABLEHASWPOLICY="false"
        fi

        if [ "$TABLEHASWPOLICY" != "true" ]; then
            echo Attempting to add WriteCapacity Auto-Scaling policies for $T.
            echo '
{
"PredefinedMetricSpecification": {
"PredefinedMetricType": "DynamoDBWriteCapacityUtilization"
},
"TargetValue": 70.0
}' >writepolicy.json

            aws application-autoscaling put-scaling-policy \
                --service-namespace dynamodb \
                --resource-id "table/$T" \
                --scalable-dimension "dynamodb:table:WriteCapacityUnits" \
                --policy-name "DynamoDBWriteCapacityUtilization:table/$T" \
                --policy-type "TargetTrackingScaling" \
                --target-tracking-scaling-policy-configuration file://writepolicy.json
        else
            echo $T already has WriteCapacity Auto-Scaling policies.
        fi

        TABLEHASRPOLICY=$(echo $POLICYJSON | jq -e -r 'any( .ScalingPolicies[]; .ScalableDimension == "dynamodb:table:ReadCapacityUnits")?')
        if [ $? -ne 0 ]; then
            TABLEHASRPOLICY="false"
        fi

        if [ "$TABLEHASRPOLICY" != "true" ]; then
            echo Attempting to add ReadCapacity Auto-Scaling policies for $T.
            echo '
{
"PredefinedMetricSpecification": {
"PredefinedMetricType": "DynamoDBReadCapacityUtilization"
},
"TargetValue": 70.0
}' >readpolicy.json

            aws application-autoscaling put-scaling-policy \
                --service-namespace dynamodb \
                --resource-id "table/$T" \
                --scalable-dimension "dynamodb:table:ReadCapacityUnits" \
                --policy-name "DynamoDBReadCapacityUtilization:table/$T" \
                --policy-type "TargetTrackingScaling" \
                --target-tracking-scaling-policy-configuration file://readpolicy.json
        else
            echo $T already has ReadCapacity Auto-Scaling policies.
        fi

        GSILIST=$(echo $TABLEJSON | jq -r '.Table.GlobalSecondaryIndexes[].IndexName?')
        if [ $? -eq 0 ]; then
            GSILIST=($GSILIST)
            for GSI in "${GSILIST[@]}"; do
                GSIAUTOSCALEJSON=$(aws application-autoscaling describe-scalable-targets --service-namespace dynamodb --resource-id "table/$T/index/$GSI")
                INDEXWSCALABLE=$(echo $GSIAUTOSCALEJSON | jq -e -r 'any( .ScalableTargets[]; .ScalableDimension == "dynamodb:index:WriteCapacityUnits")?')
                if [ $? -ne 0 ]; then
                    INDEXWSCALABLE="false"
                fi

                if [ "$INDEXWSCALABLE" != "true" ]; then
                    echo Attempting to enable WriteCapacity Auto-Scaling for GSI $GSI.
                    aws application-autoscaling register-scalable-target \
                        --service-namespace dynamodb \
                        --resource-id "table/$T/index/$GSI" \
                        --scalable-dimension "dynamodb:index:WriteCapacityUnits" \
                        --min-capacity 5 \
                        --max-capacity 40000
                else
                    echo GSI $GSI already has WriteCapacity in Auto-Scaling mode.
                fi

                INDEXRSCALABLE=$(echo $GSIAUTOSCALEJSON | jq -e -r 'any( .ScalableTargets[]; .ScalableDimension == "dynamodb:index:ReadCapacityUnits")?')
                if [ $? -ne 0 ]; then
                    INDEXRSCALABLE="false"
                fi

                if [ "$INDEXRSCALABLE" != "true" ]; then
                    echo Attempting to enable ReadCapacity Auto-Scaling for GSI $GSI.
                    aws application-autoscaling register-scalable-target \
                        --service-namespace dynamodb \
                        --resource-id "table/$T/index/$GSI" \
                        --scalable-dimension "dynamodb:index:ReadCapacityUnits" \
                        --min-capacity 5 \
                        --max-capacity 40000
                else
                    echo GSI $GSI already has ReadCapacity in Auto-Scaling mode.
                fi

                GSIPOLICYJSON=$(aws application-autoscaling describe-scaling-policies --service-namespace dynamodb --resource-id "table/$T/index/$GSI")
                INDEXHASWPOLICY=$(echo $GSIPOLICYJSON | jq -e -r 'any( .ScalingPolicies[]; .ScalableDimension == "dynamodb:index:WriteCapacityUnits")?')
                if [ $? -ne 0 ]; then
                    INDEXHASWPOLICY="false"
                fi

                if [ "$INDEXHASWPOLICY" != "true" ]; then
                    echo Attempting to add WriteCapacity Auto-Scaling policies for $GSI.
                    echo '
{
"PredefinedMetricSpecification": {
"PredefinedMetricType": "DynamoDBWriteCapacityUtilization"
},
"TargetValue": 70.0
}' >writepolicy.json

                    aws application-autoscaling put-scaling-policy \
                        --service-namespace dynamodb \
                        --resource-id "table/$T/index/$GSI" \
                        --scalable-dimension "dynamodb:index:WriteCapacityUnits" \
                        --policy-name "DynamoDBWriteCapacityUtilization:table/$T/index/$GSI" \
                        --policy-type "TargetTrackingScaling" \
                        --target-tracking-scaling-policy-configuration file://writepolicy.json
                else
                    echo $GSI already has WriteCapacity Auto-Scaling policies.
                fi

                INDEXHASRPOLICY=$(echo $GSIPOLICYJSON | jq -e -r 'any( .ScalingPolicies[]; .ScalableDimension == "dynamodb:index:ReadCapacityUnits")?')
                if [ $? -ne 0 ]; then
                    INDEXHASRPOLICY="false"
                fi

                if [ "$INDEXHASRPOLICY" != "true" ]; then
                    echo Attempting to add WriteCapacity Auto-Scaling policies for $GSI.
                    echo '
{
"PredefinedMetricSpecification": {
"PredefinedMetricType": "DynamoDBReadCapacityUtilization"
},
"TargetValue": 70.0
}' >readpolicy.json

                    aws application-autoscaling put-scaling-policy \
                        --service-namespace dynamodb \
                        --resource-id "table/$T/index/$GSI" \
                        --scalable-dimension "dynamodb:index:ReadCapacityUnits" \
                        --policy-name "DynamoDBReadCapacityUtilization:table/$T/index/$GSI" \
                        --policy-type "TargetTrackingScaling" \
                        --target-tracking-scaling-policy-configuration file://readpolicy.json
                else
                    echo $GSI already has ReadCapacity Auto-Scaling policies.
                fi
            done
        else
            echo $T does not have a Global Secondary Index.
        fi

    else
        echo $T already has WriteCapacity in PAY_PER_REQUEST mode. Skipping Auto-Scaling.
    fi

    echo Attempting to replicate $T to us-gov-east-1.
    aws dynamodb update-table --region us-gov-west-1 --table-name $T --replica-updates {\"Create\":{\"RegionName\":\"us-gov-east-1\"}}
else
    echo $T already replicated to us-gov-east-1.
fi
