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

# BEGIN
RDSINFO=$(get_database_metadata "$DATABASE")

if [[ $? -ne 0 ]]; then
    echo "aws rds describe-db-instances failed for $DATABASE"
    exit 1
fi

# get replica parameters from source
SOURCEARN=$(echo $RDSINFO | jq -r '.DBInstances[] | .DBInstanceArn')
SOURCEENCRYPTED=$(echo $RDSINFO | jq -r '.DBInstances[] | .StorageEncrypted')
SOURCENAME=$DATABASE

STORAGETYPE=$(echo $RDSINFO | jq -r '.DBInstances[] | .StorageType')
STORAGETYPEIO1IOPS=1000
if [[ "$STORAGETYPE" == "io1" ]]; then
    STORAGETYPEIO1IOPS=$(echo $RDSINFO | jq -r '.DBInstances[] | .Iops')
fi

TAGS=$(echo $RDSINFO | jq '[.DBInstances[] | .TagList[] | select( .Key == ("ApplicationID", "DBAenv", "Portfolio", "Product", "ProductLine", "Tenant"))]')

TENANT=${SOURCENAME%-*}
VPCID=$(echo $RDSINFO | jq -r '.DBInstances[] | .DBSubnetGroup | .VpcId')

if [[ "$VPCID" == "vpc-af38e7cb" ]]; then
    VPC="dev"
elif [[ "$VPCID" == "vpc-bb3de2df" ]]; then
    VPC="stage"
elif [[ "$VPCID" == "vpc-5e3ae53a" ]]; then
    VPC="prod"
else
    echo "error: database VPC could not be determined."
    exit 1
fi

# switch region to us-gov-east
export AWS_DEFAULT_REGION=us-gov-east-1

aws cloudformation create-stack \
    --stack-name ${SOURCENAME}-DR-replica-orcl \
    --tags "$TAGS" \
    --template-body file:///$GITROOT/aws/cft/cft-rds-oracle-replica.yaml \
    --parameters \
    ParameterKey=SourceARN,ParameterValue=$SOURCEARN \
    ParameterKey=SourceEncrypted,ParameterValue=$SOURCEENCRYPTED \
    ParameterKey=SourceName,ParameterValue=$SOURCENAME \
    ParameterKey=StorageType,ParameterValue=$STORAGETYPE \
    ParameterKey=StorageTypeio1Iops,ParameterValue=$STORAGETYPEIO1IOPS \
    ParameterKey=VPC,ParameterValue=$VPC
