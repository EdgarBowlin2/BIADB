#!/bin/bash
. ~/.bash_profile
cd ~/scripts
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/env
. $GITROOT/BIA/env
#Adding AWS Resource key and environment variable to the BIA env file 
. $GITROOT/BIA/health-check/health-check-env

##
## USER DEFINED
##

OMITFROMREPORT="oem"

DMS_LATENCY_THRESHOLD=900
RDS_MULTIAZ_ENVS=(prod)
RDS_REPLICATED_ENVS=(prod)
RDS_REPLICATED_BLACKLIST=(idb-prod)
RDS_STORAGE_THRESHOLD=95
RDS_TERMPROT_ENVS=(prod)

##
## METADATA
##

CRITCSV=""
NL=$'\n'
set_vault_environment
if [[ $? -ne 0 ]]; then
    echo "ERROR: set_vault_environment failed."
    exit 1
fi


# cloudwatch
ALLCWALARMS=$(aws cloudwatch describe-alarms | jq -r ' .MetricAlarms[] | select( .StateValue!="OK" ) ')


# dms
STARTTIME=$(date -Iseconds -d '-1 minute')
ENDTIME=$(date -Iseconds)


TASKJSON=$(get_migration_task_metadata)
if [[ $? -ne 0 ]]; then
#There are no DMS tasks owned by BIA in stage currently 2/16/23
    if [ $AWSACCOUNT == 'S' ] && [ $AWS_RESOURCE_VALUE == 'BIA' ]; then
	echo "BIA has no stage DMS tasks"	
    else	
    	echo "ERROR: get_migration_task_metadata failed."
    	exit 1
    fi
fi

TASKARNS=($(echo $TASKJSON | jq -r ' .ReplicationTaskArn '))

REPLINSTJSON=$(get_replication_instance_metadata)
if [[ $? -ne 0 ]]; then
#There are no DMS tasks owned by BIA in stage currently 2/16/23
    if [ $AWSACCOUNT == 'S' ] && [ $AWS_RESOURCE_VALUE == 'BIA' ]; then
        echo "BIA has no stage DMS instances"
    else
    	echo "ERROR: get_replication_instance_metadata failed."
    	exit 1
    fi
fi

REPLINSTLIST=($(echo $REPLINSTJSON | jq -r ' .ReplicationInstanceIdentifier '))


CWALARMS_DMS=$(echo $ALLCWALARMS | jq -r ' select( .Namespace=="AWS/DMS" ) ')
PENDINGACTIONS_DMS=$(aws dms describe-pending-maintenance-actions | jq -r ' .PendingMaintenanceActions[] ')

# rds
DBLIST=($(get_database_list))
if [[ $? -ne 0 ]]; then
    echo "ERROR: get_database_list returned zero databases."
    exit 1
fi

RDSJSON=$(get_database_metadata_all)
if [[ $? -ne 0 ]]; then
    echo "ERROR: get_database_metadata_all failed."
    exit 1
fi

CWALARMS_RDS=$(echo $ALLCWALARMS | jq -r ' select( .Namespace=="AWS/RDS" ) ')
ENVIRONMENTLIST=($(echo $RDSJSON | jq -r --arg AWSENVIRONK "$AWS_ENVIRONMENT_KEY" ' .TagList[] | select( .Key==$AWSENVIRONK ) | .Value ' | sort -u))
PENDINGACTIONS_RDS=$(aws rds describe-pending-maintenance-actions | jq -r ' .PendingMaintenanceActions[] ')
SNAPSHOTJSON=$(aws rds describe-db-snapshots --snapshot-type automated | jq -r ' .DBSnapshots[] ')

# report
ALLRDSLIST=($(aws rds describe-db-instances | jq -r ' .DBInstances[] | .DBInstanceIdentifier '))
OMITRDS=($(comm --check-order -23 <(printf '%s\n' "${ALLRDSLIST[@]}" | sort) <(printf '%s\n' "${DBLIST[@]}" | sort)))
#What is OMITRDS doing? Takes in 2 sorted lists and gets unique RDS from all that aren't in the list from generate_Database_list 
OMITRDS_PIPED=$(echo "${OMITRDS[*]}" | tr ' ' '|')
OMITFROMREPORT="${OMITRDS_PIPED}|${OMITFROMREPORT}"

##
## MAIN
##

## OEM

get_oem_incident_json() {
    local lOEMJSON="$(
        sqlplus -s SYSMAN/"$SYSMAN_PASSWORD"@$HOST:$PORT/$SID <<EOF
start oem-incidents
exit
EOF
    )"
    echo "$lOEMJSON"
}

# bip
SYSMAN_PASSWORD=$(vault kv get -field=sysman $OEM_PATH)
HOST=$(vault kv get -field=endpoint $OEM_PATH)
PORT=$(vault kv get -field=port $OEM_PATH)
SID=$(vault kv get -field=sid $OEM_PATH)

BIPOEMJSON="$(get_oem_incident_json)"

if [[ $? -ne 0 ]]; then
    CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"health-check\",\"OEM\",\"OEM Incident check failed\")
fi

CRITCSV=${CRITCSV}${NL}$(echo $BIPOEMJSON | sed 's/\\n//g' | jq -r ' select ( .Severity=="Critical" or .Severity=="Fatal" ) | [.Date, .Time, .Type, .Name, .Message] | @csv ')

## RDS

# instance status <> 'available'
UNAVAILABLE=($(echo $RDSJSON | jq -r ' select( .DBInstanceStatus!="available" ) | .DBInstanceIdentifier '))
if [[ ${#UNAVAILABLE[@]} -gt 0 ]]; then
    for DATABASE in "${UNAVAILABLE[@]}"; do
        DBSTATUS=$(echo $RDSJSON | jq -r --arg DATABASE "$DATABASE" ' select( .DBInstanceIdentifier==$DATABASE ) | .DBInstanceStatus ')
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"AWS/RDS\",\"$DATABASE\",\"RDS Instance State: $DBSTATUS\")
    done
fi

# auto upgrade enabled
AUTOUPGRADE=($(echo $RDSJSON | jq -r ' select( .AutoMinorVersionUpgrade==true ) | .DBInstanceIdentifier '))
if [[ ${#AUTOUPGRADE[@]} -gt 0 ]]; then
    for DATABASE in "${AUTOUPGRADE[@]}"; do
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"AWS/RDS\",\"$DATABASE\",\"Auto Minor Version Upgrade is enabled\")
    done
fi

# storage auto scaling enabled
AUTOSCALING=($(echo $RDSJSON | jq -r ' select( has("MaxAllocatedStorage") ) | .DBInstanceIdentifier '))
if [[ ${#AUTOSCALING[@]} -gt 0 ]]; then
    for DATABASE in "${AUTOSCALING[@]}"; do
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"AWS/RDS\",\"$DATABASE\",\"Storage Auto Scaling is enabled\")
    done
fi

# termination protection disabled
for PROTENV in "${RDS_TERMPROT_ENVS[@]}"; do
    NOTPROTECTED=($(echo $RDSJSON | jq -r --arg PROTENV "$PROTENV" --arg AWSENVIRONK "$AWS_ENVIRONMENT_KEY" ' select( .TagList[] | select(.Key==$AWSENVIRONK) | select(.Value==$PROTENV)) | select( .DeletionProtection==false ) | .DBInstanceIdentifier'))

    if [[ ${#NOTPROTECTED[@]} -gt 0 ]]; then
        for DATABASE in "${NOTPROTECTED[@]}"; do
            CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"AWS/RDS\",\"$DATABASE\",\"Termination Protection is disabled\")
        done
    fi
done

# not replicated to us-gov-east-1
for REPLENV in "${RDS_REPLICATED_ENVS[@]}"; do
    NOTREPLICATED=($(echo $RDSJSON | jq -r --arg REPLENV "$REPLENV" --arg AWSENVIRONK "$AWS_ENVIRONMENT_KEY" ' select( .TagList[] | select(.Key==$AWSENVIRONK) | select(.Value==$REPLENV)) | select( .ReadReplicaDBInstanceIdentifiers==[] ) | .DBInstanceIdentifier'))
    NOTREPLICATED+=($(echo $RDSJSON | jq -r --arg REPLENV "$REPLENV" --arg AWSENVIRONK "$AWS_ENVIRONMENT_KEY" ' select( .TagList[] | select(.Key==$AWSENVIRONK) | select(.Value==$REPLENV)) | select( .ReadReplicaDBInstanceIdentifiers[] | contains("us-gov-east-1") | not) | .DBInstanceIdentifier'))

    if [[ ${#NOTREPLICATED[@]} -gt 0 ]]; then
        for DATABASE in "${NOTREPLICATED[@]}"; do
            if ! [[ " ${RDS_REPLICATED_BLACKLIST[*]} " =~ " $DATABASE " ]]; then
                CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"AWS/RDS\",\"$DATABASE\",\"us-gov-east-1 Read Replica not configured\")
            fi
        done
    fi
done

# not multi-az
for MULTIAZENV in "${MULTIAZ_ENVS[@]}"; do
    NOTMULTIAZ=($(echo $RDSJSON | jq -r --arg MULTIAZENV "$MULTIAZENV" --arg AWSENVIRONK "$AWS_ENVIRONMENT_KEY" ' select( .TagList[] | select(.Key==$AWSENVIRONK) | select(.Value==$MULTIAZENV)) | select( .MultiAZ==false ) | .DBInstanceIdentifier'))

    if [[ ${#NOTMULTIAZ[@]} -gt 0 ]]; then
        for DATABASE in "${NOTMULTIAZ[@]}"; do
            CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"AWS/RDS\",\"$DATABASE\",\"Multi-AZ not configured\")
        done
    fi
done

# missing AWS_ENVIRONMENT_KEY tag
MISSINGTAG=($(echo $RDSJSON | jq -r --arg AWSENVIRONK "$AWS_ENVIRONMENT_KEY" ' select( contains({TagList: [{Key: $AWSENVIRONK} ]}) | not ) | .DBInstanceIdentifier '))
if [[ ${#MISSINGTAG[@]} -gt 0 ]]; then
    for DATABASE in "${MISSINGTAG[@]}"; do
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"AWS/RDS\",\"$DATABASE\",\"Tag missing: $AWS_ENVIRONMENT_KEY\")
    done
fi

#incorrect AWS_ENVIRONMENT_KEY tag
for ENVIRONMENT in "${ENVIRONMENTLIST[@]}"; do
    NOTAWSENVIRONKREGEX=$(echo "${ENVIRONMENTLIST[*]}" | sed "s/\b${ENVIRONMENT}\b/ /g" | awk '{$1=$1};1' | sed "s/ /|/g")

    WRONGTAG=($(echo $RDSJSON | jq -r --arg ENVIRONMENT "$ENVIRONMENT" --arg AWSENVIRONK "$AWS_ENVIRONMENT_KEY" ' select( .TagList[] | select( .Key==$AWSENVIRONK ) | select( .Value==$ENVIRONMENT )) | .DBInstanceIdentifier ' | egrep "\-(${NOTAWSENVIRONKREGEX})(-|$)"))

    if [[ ${#WRONGTAG[@]} -gt 0 ]]; then
        for DATABASE in "${WRONGTAG[@]}"; do
            CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"AWS/RDS\",\"$DATABASE\",\"Tag incorrect: $AWS_ENVIRONMENT_KEY=$ENVIRONMENT\")
        done
    fi
done

# latest restorable time > 30 mins
for DATABASE in "${DBLIST[@]}"; do
    LATESTRESTORE=$(($(date +%s) - $(date -d $(echo $RDSJSON | jq -r --arg DATABASE "$DATABASE" ' select( .DBInstanceIdentifier==$DATABASE ) | .LatestRestorableTime ') +%s)))
    if [[ $LATESTRESTORE -gt 1800 ]]; then
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"AWS/RDS\",\"$DATABASE\",\"Latest Restorable Time is over 30 minutes\")
    fi
done

# daily automated snapshots
for DATABASE in "${DBLIST[@]}"; do
    LATESTSNAPSHOT=$(($(date +%s) - $(date -d $(echo $SNAPSHOTJSON | jq -r --arg DATABASE "$DATABASE" ' select( .DBInstanceIdentifier==$DATABASE ) | .SnapshotCreateTime ' | sort -r | head -1) +%s)))
    if [[ $LATESTSNAPSHOT -gt 86400 ]]; then
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"AWS/RDS\",\"$DATABASE\",\"Latest Automated Snapshot is older than 24 hours\")
    fi
done

# rds pending maintenance actions
for DATABASE in "${DBLIST[@]}"; do
    PENDINGACTION_RDS=$(echo $PENDINGACTIONS_RDS | jq -r --arg DATABASE "$DATABASE" ' select ( .ResourceIdentifier | endswith($DATABASE) ) | .PendingMaintenanceActionDetails[].Description ')
    if [[ -n "$PENDINGACTION_RDS" ]]; then
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"AWS/RDS\",\"$DATABASE\",\"Pending Maintenance: $PENDINGACTION_RDS\")
    fi
done

# cloudwatch
for DATABASE in "${DBLIST[@]}"; do
    CWALARMS_DATABASE=$(echo $CWALARMS_RDS | jq -r --arg DATABASE "$DATABASE" ' select( .Dimensions[] | select( .Name=="DBInstanceIdentifier" ) | select( .Value==$DATABASE )) | [ (.StateUpdatedTimestamp | split(".")[0] | strptime("%Y-%m-%dT%H:%M:%S") | mktime | strftime("%F","%X")), "CloudWatch", .AlarmName, .StateValue] | @csv ')
    if [[ -n "$CWALARMS_DATABASE" ]]; then
        CRITCSV=${CRITCSV}${NL}${CWALARMS_DATABASE}
    fi
done

# storage used
for DATABASE in "${DBLIST[@]}"; do

    USEDBYTES=$(aws cloudwatch get-metric-statistics \
        --metric-name FreeStorageSpace \
        --start-time $STARTTIME \
        --end-time $ENDTIME \
        --period 60 \
        --namespace AWS/RDS \
        --statistics Average \
        --dimensions Name=DBInstanceIdentifier,Value=$DATABASE |
        jq -r ' .Datapoints[].Average ')

    if [[ $? -ne 0 ]]; then
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"health-check\",\"$DATABASE\",\"Free Storage Space check failed\")
        continue
    fi

    TOTALBYTES=$(echo $(($(echo $RDSJSON | jq -r --arg DATABASE "$DATABASE" ' select( .DBInstanceIdentifier==$DATABASE ) | .AllocatedStorage ') * 1024 * 1024 * 1024)))

    USEDBYTES_PCT=$(bc <<<"scale=4; ($TOTALBYTES-$USEDBYTES)/$TOTALBYTES*100" | sed 's/[0]*$//g')

    ALARM_USEDBYTES=$(bc <<<"$USEDBYTES_PCT > $RDS_STORAGE_THRESHOLD")

    if [[ $ALARM_USEDBYTES -eq 1 ]]; then
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"AWS/RDS\",\"$DATABASE\",\"Storage Used is $USEDBYTES_PCT%\")
    fi

done

## DATABASE
#Switch directory to health check directory to access SQL files
cd $GITROOT/BIA/health-check
# expiring passwords
for DATABASE in "${DBLIST[@]}"; do
    DBJSON=$(echo $RDSJSON | jq -r --arg DATABASE "$DATABASE" ' select( .DBInstanceIdentifier==$DATABASE ) ')

    set_database_connection "$DBJSON"
    if [[ $? -ne 0 ]]; then
        continue
    fi

    EXPIREDCSV="$(
        sqlplus -s $MASTER_USERNAME/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
start expired-passwords
exit
EOF
    )"

    if [[ $? -ne 0 ]]; then
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"health-check\",\"$DATABASE\",\"Expired Password check failed\")
        continue
    fi

    if [[ -n "$EXPIREDCSV" ]]; then
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"oracle_user\",\"$DATABASE\",\"Expiring Passwords: $EXPIREDCSV\")
    fi

done

# prodtest refresh
REFRESHACTIVE=($(echo $RDSJSON | jq -r ' .TagList[] | select(.Key=="DBArefresh") | .Value '))

for DATABASE in "${REFRESHACTIVE[@]}"; do

    # idb-prodtest refresh only happens on sunday
    if [[ "$DATABASE" == "idb-prodtest" ]] && [[ $(date +%u) -ne 6 ]]; then
        continue
    fi

    DBJSON=$(echo $RDSJSON | jq -r --arg DATABASE "$DATABASE" ' select( .DBInstanceIdentifier==$DATABASE ) ')

    set_database_connection "$DBJSON"

    REFRESHOPENMODE="$(
        sqlplus -s $MASTER_USERNAME/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
start open-mode
EOF
    )"

    if [[ $? -ne 0 ]]; then
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"health-check\",\"$DATABASE\",\"refresh check failed\")
        continue
    fi

    EVENTSJSON=$(aws rds describe-events --source-identifier $DATABASE --duration 1440 --source-type db-instance)

    REFRESHDELETED=$(echo $EVENTSJSON | jq -r ' any( .Events[]; .Message | contains("DB instance deleted") ) ')
    REFRESHRESTORED=$(echo $EVENTSJSON | jq -r ' any( .Events[]; .Message | contains("Restored from snapshot") ) ')
    REFRESHPROMOTED=$(echo $EVENTSJSON | jq -r ' any( .Events[]; .Message | contains("Promoted Read Replica to a stand-alone database instance") ) ')

    if [[ "$REFRESHDELETED" == "false" ]]; then
        if [[ "$REFRESHOPENMODE" != "READ WRITE" ]]; then
            CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"refresh\",\"$DATABASE\",\"failed on step 1 of 5: PRE\")
        else
            CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"refresh\",\"$DATABASE\",\"failed on step 2 of 5: DELETION\")
        fi
        continue
    fi

    if [[ "$REFRESHRESTORED" == "false" ]]; then
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"refresh\",\"$DATABASE\",\"failed on step 3 of 5: RESTORE FROM SNAPSHOT\")
        continue
    fi

    if [[ "$REFRESHPROMOTED" == "false" ]]; then
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"refresh\",\"$DATABASE\",\"failed on step 4 of 5: PROMOTION\")
        continue
    fi

    if [[ "$REFRESHOPENMODE" != "READ WRITE" ]]; then
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"refresh\",\"$DATABASE\",\"failed on step 5 of 5: POST\")
        continue
    fi

done

## DMS

# instance status <> 'available'
UNAVAILABLE_DMS=($(echo $REPLINSTJSON | jq -r ' select( .ReplicationInstanceStatus!="available" ) | .ReplicationInstanceIdentifier '))
if [[ ${#UNAVAILABLE_DMS[@]} -gt 0 ]]; then
    for INSTANCE in "${UNAVAILABLE_DMS[@]}"; do
        REPLSTATUS=$(echo $REPLINSTJSON | jq -r --arg INSTANCE "$INSTANCE" ' select( .ReplicationInstanceIdentifier==$INSTANCE ) | .ReplicationInstanceStatus ')
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"AWS/DMS\",\"$INSTANCE\",\"DMS Replication Instance State: $REPLSTATUS\")
    done
fi

# auto upgrade enabled
AUTOUPGRADE_DMS=($(echo $REPLINSTJSON | jq -r ' select( .AutoMinorVersionUpgrade==true ) | .ReplicationInstanceIdentifier '))
if [[ ${#AUTOUPGRADE_DMS[@]} -gt 0 ]]; then
    for INSTANCE in "${AUTOUPGRADE_DMS[@]}"; do
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"AWS/DMS\",\"$INSTANCE\",\"Auto Minor Version Upgrade is enabled\")
    done
fi

# task status <> 'running'
CRITCSV=${CRITCSV}${NL}$(echo $TASKJSON | jq -r ' select( .Status!="running" ) | [ (.ReplicationTaskStats.StopDate | split(".")[0] | strptime("%Y-%m-%dT%H:%M:%S") | mktime | strftime("%F","%X")), "AWS/DMS", .ReplicationTaskIdentifier, .Status] | @csv ')

# task latency
for TASKARN in "${TASKARNS[@]}"; do

    TASKREPLARN=$(echo $TASKJSON | jq -r --arg TASKARN "$TASKARN" ' select( .ReplicationTaskArn==$TASKARN ) | select( .Status=="running" ) | .ReplicationInstanceArn ')

    if [[ -z "$TASKREPLARN" ]]; then
        continue
    fi

    TASKREPLNAME=$(echo $REPLINSTJSON | jq -r --arg TASKREPLARN "$TASKREPLARN" ' select( .ReplicationInstanceArn==$TASKREPLARN ) | .ReplicationInstanceIdentifier ')
    TASKNAME=$(echo $TASKJSON | jq -r --arg TASKARN "$TASKARN" ' select( .ReplicationTaskArn==$TASKARN ) | .ReplicationTaskIdentifier ')

    CDCLATENCYSOURCE=$(aws cloudwatch get-metric-statistics \
        --metric-name CDCLatencySource \
        --start-time $STARTTIME \
        --end-time $ENDTIME \
        --period 60 \
        --namespace AWS/DMS \
        --statistics Average \
        --unit Seconds \
        --dimensions Name=ReplicationInstanceIdentifier,Value=$TASKREPLNAME Name=ReplicationTaskIdentifier,Value=${TASKARN##*:})

    if [[ $? -ne 0 ]]; then
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"health-check\",\"$TASKNAME\",\"CDC Latency check failed\")
        continue
    fi

    LATENCY=$(echo $CDCLATENCYSOURCE | jq -r ' .Datapoints[].Average ')
    LATENCY=${LATENCY%.*}

    if [[ $LATENCY -gt $DMS_LATENCY_THRESHOLD ]]; then
        LATENCY_PRETTY=$(eval "echo $(date -d@$LATENCY -u +'$((%s/3600/24))d %T')")
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"AWS/DMS\",\"$TASKNAME\",\"CDCLatencySource is $LATENCY_PRETTY\")
    fi

    CDCLATENCYTARGET=$(aws cloudwatch get-metric-statistics \
        --metric-name CDCLatencyTarget \
        --start-time $STARTTIME \
        --end-time $ENDTIME \
        --period 60 \
        --namespace AWS/DMS \
        --statistics Average \
        --unit Seconds \
        --dimensions Name=ReplicationInstanceIdentifier,Value=$TASKREPLNAME Name=ReplicationTaskIdentifier,Value=${TASKARN##*:})

    if [[ $? -ne 0 ]]; then
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"health-check\",\"$TASKNAME\",\"CDC Latency check failed\")
        continue
    fi

    LATENCY=$(echo $CDCLATENCYTARGET | jq -r ' .Datapoints[].Average ')
    LATENCY=${LATENCY%.*}

    if [[ $LATENCY -gt $DMS_LATENCY_THRESHOLD ]]; then
        LATENCY_PRETTY=$(eval "echo $(date -d@$LATENCY -u +'$((%s/3600/24))d %T')")
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"AWS/DMS\",\"$TASKNAME\",\"CDCLatencyTarget is $LATENCY_PRETTY\")
    fi

done

# dms pending maintenance actions
for REPLINST in "${REPLINSTLIST[@]}"; do
    REPLINSTARN=$(echo $REPLINSTJSON | jq -r --arg REPLINST "$REPLINST" ' select( .ReplicationInstanceIdentifier==$REPLINST ) | .ReplicationInstanceArn ')

    PENDINGACTION_DMS=$(echo $PENDINGACTIONS_DMS | jq -r --arg REPLINSTARN "$REPLINSTARN" ' select ( .ResourceIdentifier==$REPLINSTARN ) | .PendingMaintenanceActionDetails[].Description ')
    if [[ -n "$PENDINGACTION_DMS" ]]; then
        CRITCSV=${CRITCSV}${NL}$(echo \"\",\"\",\"AWS/DMS\",\"$REPLINST\",\"Pending Maintenance: $PENDINGACTION_DMS\")
    fi
done

# cloudwatch
for REPLINST in "${REPLINSTLIST[@]}"; do
    CWALARMS_INSTANCE=$(echo $CWALARMS_DMS | jq -r --arg REPLINST "$REPLINST" ' select( .Dimensions[] | select( .Name=="ReplicationInstanceIdentifier" ) | select( .Value==$REPLINST )) | [ (.StateUpdatedTimestamp | split(".")[0] | strptime("%Y-%m-%dT%H:%M:%S") | mktime | strftime("%F","%X")), "CloudWatch", .AlarmName, .StateValue] | @csv ')
    if [[ -n "$CWALARMS_INSTANCE" ]]; then
        CRITCSV=${CRITCSV}${NL}${CWALARMS_INSTANCE}
    fi
done

#
## OUTPUT
##

echo $TOPHTML

echo $TOPTABLE

while IFS= read -r INPUT; do

    echo "<tr><td>${INPUT//\",\"/</td><td>}</td></tr>" | sed 's/\"//g'

    # add filters to the egrep regex expression as needed
done < <(printf '%s\n' "$CRITCSV" | egrep -v "(^$|${OMITFROMREPORT})" | sort -t ',' -k 3,3 -k 4,4)

echo $BOTTABLE

echo "<br>"
echo "list of health-checks:<br>"
echo "<br>"
echo "availability: dms replication and rds<br>"
echo "cloudwatch alarms: dms and rds<br>"
echo "disaster recovery: multiaz, us-gov-east-1 replica<br>"
echo "dms configuration: autoupdate<br>"
echo "dms task status and latency<br>"
echo "goldengate status and latency, via oem critical incident<br>"
echo "oem critical incidents<br>"
echo "oracle account: expiring password<br>"
echo "pending maintenance actions: dms and rds<br>"
echo "refresh from production: platform<br>"
echo "rds restorability and automated snapshots<br>"
echo "rds configuration: autoscaling, autoupdate, tagging, termination protection<br>"

echo $BOTHTML
