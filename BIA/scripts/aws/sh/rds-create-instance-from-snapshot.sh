#!/bin/bash
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/env

# parse command line
usage() {
    echo "usage: $0 [ -d DB-INSTANCE-IDENTIFIER ] [ -t TEMPLATE DB-INSTANCE-IDENTIFIER ] [ -s SNAPSHOT NAME ]" 1>&2
    exit 1
}

while getopts ":d:t:s:" options; do
    case "${options}" in
        d)
            DATABASE=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
            ;;
        t)
            TEMPLATE_DATABASE=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
            ;;
        s)
            SNAPSHOT=${OPTARG}
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

if [[ -z "$TEMPLATE_DATABASE" ]]; then
    echo "ERROR: -t is a mandatory parameter."
    usage
fi

if [[ -z "$SNAPSHOT" ]]; then
    echo "ERROR: -s is a mandatory parameter."
    usage
fi

# BEGIN
RDSINFO=$(get_database_metadata "$TEMPLATE_DATABASE")

if [[ $? -ne 0 ]]; then
    echo "aws rds describe-db-instances failed for $TEMPLATE_DATABASE"
    exit 1
fi

STATUS=$(echo $RDSINFO | jq -r .DBInstances[].DBInstanceStatus)
if [[ "$STATUS" != "available" ]]; then
    echo "Template database is not in an available state.  Exiting..."
    return 1 2>/dev/null || exit 1
fi

# rename existing instance if -d and -t switches are the same
if [[ "$DATABASE" == "$TEMPLATE_DATABASE" ]]; then

    DATESTAMP=$(date +%m%d%y)

    echo ''
    while true; do
        echo You have chosen the same db-instance-identifier for the new database and the template database.
        echo The existing database, $DATABASE, will be renamed to $DATABASE-$DATESTAMP.
        echo The database restored from snapshot $SNAPSHOT will become the new $DATABASE database.
        read -p "Rename existing database and restore snapshot? (y/n) " yn
        case $yn in
            [Yy]*)
                echo "Renaming database..."
                break
                ;;
            [Nn]*)
                echo "Exiting without changes..."
                exit
                ;;
            *) echo "Invalid response." ;;
        esac
    done

    aws rds modify-db-instance \
        --db-instance-identifier $DATABASE \
        --new-db-instance-identifier $DATABASE-$DATESTAMP \
        --apply-immediately

    RENAME_COMPLETE=0
    while [ $RENAME_COMPLETE -ne 1 ]; do
        echo "..."
        sleep 60

        RDSINFO=$(get_database_metadata "$DATABASE-$DATESTAMP")

        if [[ $? -ne 0 ]]; then
            echo "aws rds describe-db-instances failed for $DATABASE-$DATESTAMP"
        else
            PENDING=$(echo $RDSINFO | jq -r .DBInstances[].PendingModifiedValues)
            STATUS=$(echo $RDSINFO | jq -r .DBInstances[].DBInstanceStatus)
            if [[ "$STATUS" == "available" ]] && [[ "$PENDING" == "{}" ]]; then
                RENAME_COMPLETE=1
            fi
        fi

    done

    echo Database rename complete. Disabling deletion protection on $DATABASE-$DATESTAMP.

    aws rds modify-db-instance \
        --db-instance-identifier $DATABASE-$DATESTAMP \
        --no-deletion-protection \
        --apply-immediately

fi

# get parameters from template database
CLOUDWATCH=$(echo $RDSINFO | jq -j '.DBInstances[] | .EnabledCloudwatchLogsExports | join(" ")')
MULTIAZ=$(echo $RDSINFO | jq -r '.DBInstances[] | .MultiAZ')

if [[ "$MULTIAZ" == "true" ]]; then
    MULTIAZOPTION="--multi-az"
else
    MULTIAZOPTION="--no-multi-az"
fi

INSTANCECLASS=$(echo $RDSINFO | jq -r '.DBInstances[] | .DBInstanceClass')
OPTIONGROUP=$(echo $RDSINFO | jq -r '.DBInstances[] | .OptionGroupMemberships[] | .OptionGroupName')
PARAMETERGROUP=$(echo $RDSINFO | jq -r '.DBInstances[] | .DBParameterGroups[] | .DBParameterGroupName')
SECURITYGROUPS=$(echo $RDSINFO | jq -r '[.DBInstances[] | .VpcSecurityGroups[] | .VpcSecurityGroupId] | join(" ")')
SID=$(echo $RDSINFO | jq -r '.DBInstances[] | .DBName')
STORAGETYPE=$(echo $RDSINFO | jq -r '.DBInstances[] | .StorageType')

if [[ "$STORAGETYPE" == "io1" ]]; then
    STORAGETYPEIO1IOPS=$(echo $RDSINFO | jq -r '.DBInstances[] | .Iops')
    STORAGETYPE="$STORAGETYPE --iops $STORAGETYPEIO1IOPS"
fi

SUBNETGROUP=$(echo $RDSINFO | jq -r '.DBInstances[] | .DBSubnetGroup.DBSubnetGroupName')
TAGS=$(echo $RDSINFO | jq '[.DBInstances[] | .TagList[] | select( .Key == ("ApplicationID", "DBAenv", "Portfolio", "Product", "ProductLine", "Tenant"))]')

# create new database
aws rds restore-db-instance-from-db-snapshot \
    --db-instance-identifier $DATABASE \
    --db-snapshot-identifier $SNAPSHOT \
    --db-subnet-group-name $SUBNETGROUP \
    --vpc-security-group-ids $SECURITYGROUPS \
    --storage-type $STORAGETYPE \
    --db-instance-class $INSTANCECLASS \
    --db-name $SID \
    --option-group-name $OPTIONGROUP \
    --db-parameter-group-name $PARAMETERGROUP \
    --enable-cloudwatch-logs-exports $CLOUDWATCH \
    --no-auto-minor-version-upgrade \
    --deletion-protection \
    $MULTIAZOPTION \
    --tags "$TAGS" \
    --copy-tags-to-snapshot
