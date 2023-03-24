#!/bin/bash
# set environment
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

DBARRAY=($(generate_database_list "$TEAM"))
if [ "${#DBARRAY[@]}" -eq 0 ]; then
    echo "ERROR: -t ${TEAM} returned with zero objects."
    exit 1
fi

# begin
RDSINFO=$(aws rds describe-db-instances)

# instance availability
CHK_AVAILABILITY=$(echo $RDSINFO | jq -r '.DBInstances | map([.DBInstanceIdentifier, .DBInstanceStatus] | join (",")) | join("\n")')
ACK_AVAILABILITY=()
RPT_AVAILABILITY=""

for d in $CHK_AVAILABILITY; do
    INSTANCE=$(echo $d | cut -d"," -f1)
    AVAILABILITY=$(echo $d | cut -d"," -f2)

    if ! [[ " ${ACK_AVAILABILITY[*]} " =~ " $INSTANCE " ]] && [[ " ${DBARRAY[*]} " =~ " $INSTANCE " ]]; then
        if [ "$AVAILABILITY" != "available" ]; then
            RPT_AVAILABILITY="${RPT_AVAILABILITY}${INSTANCE}\n"
        fi
    fi
done

if [ ! -z "$RPT_AVAILABILITY" ]; then
    echo "The following instances are not in an 'available' state."
    echo -e $RPT_AVAILABILITY
fi

# termination protection
CHK_TERMPROT=$(echo $RDSINFO | jq -r '.DBInstances | map([.DBInstanceIdentifier, .DeletionProtection] | join (",")) | join("\n")')
ACK_TERMPROT=()
RPT_TERMPROT=""

for d in $CHK_TERMPROT; do
    INSTANCE=$(echo $d | cut -d"," -f1)
    TERMPROT=$(echo $d | cut -d"," -f2)

    if ! [[ " ${ACK_TERMPROT[*]} " =~ " $INSTANCE " ]] && [[ " ${DBARRAY[*]} " =~ " $INSTANCE " ]]; then
        if [ "$TERMPROT" == "false" ]; then
            RPT_TERMPROT="${RPT_TERMPROT}${INSTANCE}\n"
        fi
    fi
done

if [ ! -z "$RPT_TERMPROT" ]; then
    echo "The following instances do not have termination protection."
    echo -e $RPT_TERMPROT
fi

# replication status
CHK_REPLICA=$(echo $RDSINFO | jq -r '.DBInstances | map([.DBInstanceIdentifier, .ReadReplicaDBInstanceIdentifiers[]] | join (",")) | join("\n")')
ACK_REPLICA=()
RPT_REPLICA=""

for d in $CHK_REPLICA; do
    INSTANCE=$(echo $d | cut -d"," -f1)
    REPLICA=$(echo $d | cut -d"," -f2)

    if ! [[ " ${ACK_REPLICA[*]} " =~ " $INSTANCE " ]] && [[ " ${DBARRAY[*]} " =~ " $INSTANCE " ]]; then
        if [[ ! "$REPLICA" =~ ^arn ]]; then
            RPT_REPLICA="${RPT_REPLICA}${INSTANCE}\n"
        fi
    fi
done

if [ ! -z "$RPT_REPLICA" ]; then
    echo "The following instances do not have a replica in us-gov-east."
    echo -e $RPT_REPLICA
fi

# minor version upgrade
CHK_MINORUPGRADE=$(echo $RDSINFO | jq -r '.DBInstances | map([.DBInstanceIdentifier, .AutoMinorVersionUpgrade] | join (",")) | join("\n")')
ACK_MINORUPGRADE=()
RPT_MINORUPGRADE=""

for d in $CHK_MINORUPGRADE; do
    INSTANCE=$(echo $d | cut -d"," -f1)
    MINORUPGRADE=$(echo $d | cut -d"," -f2)

    if ! [[ " ${ACK_MINORUPGRADE[*]} " =~ " $INSTANCE " ]] && [[ " ${DBARRAY[*]} " =~ " $INSTANCE " ]]; then
        if [ "$MINORUPGRADE" == "true" ]; then
            RPT_MINORUPGRADE="${RPT_MINORUPGRADE}${INSTANCE}\n"
        fi
    fi
done

if [ ! -z "$RPT_MINORUPGRADE" ]; then
    echo "The following instances will automatically apply minor upgrades."
    echo -e $RPT_MINORUPGRADE
fi

# unpatched instances
NEWENGINE=$(aws rds describe-db-engine-versions --engine oracle-ee | jq -r '.[] | .[] | select(.EngineVersion | startswith("19")) | select ( .ValidUpgradeTarget == [] ) | .EngineVersion')
CHK_VERSION=$(echo $RDSINFO | jq -r --arg NEWENGINE "$NEWENGINE" '.[] | .[] | select( .engine = "oracle-ee" ) | select ( .EngineVersion | startswith("19")) | select ( .EngineVersion | contains($NEWENGINE) | not ) | .DBInstanceIdentifier')
ACK_VERSION=()
RPT_VERSION=""

for d in $CHK_VERSION; do
    INSTANCE=$(echo $d)

    if ! [[ " ${ACK_VERSION[*]} " =~ " $INSTANCE " ]] && [[ " ${DBARRAY[*]} " =~ " $INSTANCE " ]]; then
        RPT_VERSION="${RPT_VERSION}${INSTANCE}\n"
    fi
done

if [ ! -z "$RPT_VERSION" ]; then
    echo "The following instances have not been updated to version $NEWENGINE:"
    echo -e $RPT_VERSION
fi

# backup retention
CHK_BACKUPRET=$(echo $RDSINFO | jq -r '.DBInstances | map([.DBInstanceIdentifier, .BackupRetentionPeriod] | join (",")) | join("\n")')
ACK_BACKUPRET=()
RPT_BACKUPRET=""

for d in $CHK_BACKUPRET; do
    INSTANCE=$(echo $d | cut -d"," -f1)
    BACKUPRET=$(echo $d | cut -d"," -f2)

    if ! [[ " ${ACK_BACKUPRET[*]} " =~ " $INSTANCE " ]] && [[ " ${DBARRAY[*]} " =~ " $INSTANCE " ]]; then
        if [ "$BACKUPRET" -lt 14 ]; then
            RPT_BACKUPRET="${RPT_BACKUPRET}${INSTANCE}\n"
        fi
    fi
done

if [ ! -z "$RPT_BACKUPRET" ]; then
    echo "The following instances have a backup retention less than 2 weeks."
    echo -e $RPT_BACKUPRET
fi

# instance restorability
CHK_RESTORE=$(echo $RDSINFO | jq -r '.DBInstances | map([.DBInstanceIdentifier, .LatestRestorableTime] | join (",")) | join("\n")')
ACK_RESTORE=()
RPT_RESTORE=""

for d in $CHK_RESTORE; do
    INSTANCE=$(echo $d | cut -d"," -f1)
    RESTORE=$(echo $d | cut -d"," -f2)

    if ! [[ " ${ACK_RESTORE[*]} " =~ " $INSTANCE " ]] && [[ " ${DBARRAY[*]} " =~ " $INSTANCE " ]]; then
        if [[ -z "$RESTORE" ]]; then
            RESTORE=0
        fi

        SECONDS_AGO="$(($(date +%s) - $(date -d ${RESTORE} +%s)))"
        if [ "$SECONDS_AGO" -gt "3600" ]; then
            RPT_RESTORE="${RPT_RESTORE}${INSTANCE}\n"
        fi
    fi
done

if [ ! -z "$RPT_RESTORE" ]; then
    echo "The following instances cannot be restored to a time within the last hour."
    echo -e $RPT_RESTORE
fi

# auto-scaling storage
CHK_AUTOSCALING=$(echo $RDSINFO | jq -r '.DBInstances[] | select( has("MaxAllocatedStorage") ) | .DBInstanceIdentifier')
ACK_AUTOSCALING=()
RPT_AUTOSCALING=""

for d in $CHK_AUTOSCALING; do
    INSTANCE=$(echo $d)

    if ! [[ " ${ACK_AVAILABILITY[*]} " =~ " $INSTANCE " ]] && [[ " ${DBARRAY[*]} " =~ " $INSTANCE " ]]; then
        RPT_AUTOSCALING="${RPT_AUTOSCALING}${INSTANCE}\n"
    fi
done

if [ ! -z "$RPT_AUTOSCALING" ]; then
    echo "The following instances have storage auto scaling enabled."
    echo -e $RPT_AUTOSCALING
fi

# missing tags
CHK_TAG_DBAENV=$(echo $RDSINFO | jq -r '.DBInstances[] | select( contains({TagList: [{Key: "DBAenv"} ]}) | not ) | .DBInstanceIdentifier')
ACK_TAG_DBAENV=()
RPT_TAG_DBAENV=""

for d in $CHK_TAG_DBAENV; do
    INSTANCE=$(echo $d)

    if ! [[ " ${ACK_TAG_DBAENV[*]} " =~ " $INSTANCE " ]] && [[ " ${DBARRAY[*]} " =~ " $INSTANCE " ]]; then
        RPT_TAG_DBAENV="${RPT_TAG_DBAENV}${INSTANCE}\n"
    fi
done

if [ ! -z "$RPT_TAG_DBAENV" ]; then
    echo "The following instances do not have a 'DBAenv' tag."
    echo -e $RPT_TAG_DBAENV
fi

