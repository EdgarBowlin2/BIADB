#!/bin/bash
#This script gathers the current DMS tasks and outputs their tables
aws dms describe-replication-tasks | jq -r '.ReplicationTasks | map([.ReplicationTaskIdentifier, .ReplicationTaskArn, .TargetEndpointArn, .SourceEndpointArn]| join (", ")) | join("\n")' > prod_task_info.txt
echo "" > dms_task_tables.txt
#RDS_INFO='aws rds describe-db-instances'
while IFS=',' read n l o p; do
export TASK_ID=$n
export TASK_ARN=$l
export SOURCE_ENDPOINT=$p
export TARGET_ENDPOINT=$o
export SOURCE_DB=`aws dms describe-endpoints --filters "Name=endpoint-arn, Values=$SOURCE_ENDPOINT" | jq -r '.Endpoints[] | .ServerName'`
export TARGET_DB=`aws dms describe-endpoints --filters "Name=endpoint-arn, Values=$TARGET_ENDPOINT" | jq -r '.Endpoints[] | .ServerName'`
export TARGET_DB_ID=`echo $TARGET_DB | awk -F '.' '{print $1}'`
export TARGET_DB_VERSION=`aws rds describe-db-instances --filters "Name=db-instance-id, Values=$TARGET_DB_ID"| jq -r '.DBInstances[] | .EngineVersion'`
export TAGS=`aws rds describe-db-instances --filters "Name=db-instance-id, Values=$TARGET_DB_ID" | jq -r '[.DBInstances[] | .TagList[] | select( .Key == ("Tenant"))]'`
TENANT=`echo $TAGS | awk 'BEGIN { FS = ":" } ; { print $3 }' | sed 's/"//g' | sed 's/}//g' | sed 's/]//g'`
echo " TARGET_DB_ID is " $TARGET_DB " " $TARGET_DB_ID " and its version is " $TARGET_DB_VERSION " supporting " $TENANT
table_stats=`aws dms describe-table-statistics --replication-task-arn $TASK_ARN`
echo $table_stats | jq --arg LOCAL_VAR "$TASK_ID" --arg LOCAL_VAR2 "$SOURCE_DB" --arg LOCAL_VAR3 "$TARGET_DB" --arg LOCAL_VAR4 "$TARGET_DB_VERSION" --arg LOCAL_VAR5 "$TENANT" -r '.TableStatistics | map([$LOCAL_VAR, .SchemaName, .TableName, $LOCAL_VAR2, $LOCAL_VAR3, $LOCAL_VAR4, $LOCAL_VAR5]| join (", ")) | join("\n")' >> dms_task_tables.txt
done < prod_task_info.txt
