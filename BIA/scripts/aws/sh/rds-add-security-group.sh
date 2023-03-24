#!/bin/bash
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/env

# parse command line
usage() {
    echo "usage: $0 [ -d DB-INSTANCE-IDENTIFIER ] [ -s SECURITY-GROUP ]" 1>&2
    exit 1
}

while getopts ":d:s:" options; do
    case "${options}" in
        d)
            DATABASE=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
            ;;
        s)
            NEW_SG=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
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

if [[ -z "$NEW_SG" ]]; then
    echo "ERROR: -s is a mandatory parameter."
    usage
fi

# check $1
RDSINFO=$(get_database_metadata "$DATABASE")

if [[ $? -ne 0 ]]; then
    echo "aws rds describe-db-instances failed for $DATABASE"
    exit 1
fi

# check $2
NEW_SG_CHECK=$(aws ec2 describe-security-groups --group-ids $NEW_SG | jq -r .SecurityGroups[].GroupId)
if [[ "$NEW_SG" != "$NEW_SG_CHECK" ]]; then
    echo ERROR getting information for new security group $NEW_SG.
    exit
fi

# get current security groups for database
CURRENT_SG=$(echo $RDSINFO | jq -r '[.DBInstances[].VpcSecurityGroups[].VpcSecurityGroupId] | join (" ")')

# check $2 already on $1
if [[ "$CURRENT_SG" == *"$NEW_SG"* ]]; then
    echo ERROR $NEW_SG is already a security group of $DATABASE.
    exit
fi

# add $2 to list of existing security groups
if [[ $CURRENT_SG =~ ^[sg-].* ]]; then
    aws rds modify-db-instance --db-instance-identifier $DATABASE --vpc-security-group-ids $CURRENT_SG $NEW_SG
    echo SUCCESS for database $DATABASE
    echo $CURRENT_SG $NEW_SG
else
    echo ERROR retreiving current security groups for database $DATABASE.
fi
