#!/bin/bash
################################################################################
#
#   Name:       automate_rds_standup.sh
#   Create:     2021/12/07
#   Author:     Patrick Lynn
#   Platform:   Linux
#   Purpose:    Generates source CFT for cloudformation standup
################################################################################
# set environment
GITROOT=$( git rev-parse --show-toplevel )
. $GITROOT/env
. $GITROOT/BIA/env
. $GITROOT/BIA/new-instance-setup/source_rds_params.txt
DBInstanceID=${TENANT}-${ENVIRONMENT}
set_vault_environment
#Setup your log file
exec 1> $GITROOT/BIA/new-instance-setup/log/$DBInstanceID-`date "+%Y-%m-%d"`.log 2>&1

echo The database instance ID is $DBInstanceID
export AWS_DEFAULT_REGION=us-gov-west-1
#Copy source parameters to have a record of CFT variables
cp source_rds_params.txt ${DBInstanceID}_source_rds_params.txt
mv ${DBInstanceID}_source_rds_params.txt gov-west

#Standup your source instance
aws cloudformation create-stack --stack-name ${DBInstanceID}-rds --template-body file:///home/oracle/bia-devel/BIA/new-instance-setup/cft-rds-oracle.yaml --parameters ParameterKey=VPC,ParameterValue=$VPC ParameterKey=Environment,ParameterValue=$ENVIRONMENT ParameterKey=ProductLine,ParameterValue=$PRODUCTLINE ParameterKey=Tenant,ParameterValue=$TENANT ParameterKey=StorageType,ParameterValue=$STORAGETYPE

#Wait until the db  is available
DB_CREATION_START=0
while [ $DB_CREATION_START -ne 1 ]
do
        AWSRDS=$( aws rds describe-db-instances --db-instance-identifier $DBInstanceID )
        PENDING=$( echo $AWSRDS | jq -r .DBInstances[].PendingModifiedValues )
        STATUS=$( echo $AWSRDS | jq -r .DBInstances[].DBInstanceStatus )
        if [[ "$STATUS" == "available" ]] && [[ "$PENDING" == "{}" ]]
        then
                DB_CREATION_START=1
        fi
        sleep 30
done

DBADMIN_PASSWORD="$(generate_password)"
echo "Updating DBADMIN password in database and Vault."

aws rds modify-db-instance --db-instance-identifier $DBInstanceID --master-user-password $DBADMIN_PASSWORD

echo "Waiting for AWS to complete DBADMIN password change."

DBADMIN_RESET_START=0
while [ $DBADMIN_RESET_START -ne 1 ]
do
        AWSRDS=$( aws rds describe-db-instances --db-instance-identifier $DBInstanceID )
        PENDING=$( echo $AWSRDS | jq -r .DBInstances[].PendingModifiedValues )
        STATUS=$( echo $AWSRDS | jq -r .DBInstances[].DBInstanceStatus )
        if [[ "$STATUS" == "available" ]] && [[ "$PENDING" == "{}" ]]
        then
                DBADMIN_RESET_START=1
        fi
        sleep 30
done

echo "Executing baseline script."

DBSNMP_PASSWORD="$(generate_password)"
BIPDBA_PASSWORD="$(generate_password)"
LIQUID_PASSWORD="$(generate_password)"
VASCAN_PASSWORD="$(generate_password)"

AWSRDS=$( aws rds describe-db-instances --db-instance-identifier $DBInstanceID )
HOST=$( echo $AWSRDS | jq -r .DBInstances[].Endpoint.Address )
PORT=$( echo $AWSRDS | jq -r .DBInstances[].Endpoint.Port )
SID=$( echo $AWSRDS | jq -r .DBInstances[].DBName )

sqlplus dbadmin/"$DBADMIN_PASSWORD"@$HOST:$PORT/$SID <<EOF
start new-instance-setup $BIPDBA_PASSWORD $DBSNMP_PASSWORD $LIQUID_PASSWORD $VASCAN_PASSWORD
exit
EOF

echo "Adding secrets to vault."

vault kv put secret/platform/bia-dbas/$TENANT/$ENVIRONMENT dbadmin=$DBADMIN_PASSWORD dbsnmp=$DBSNMP_PASSWORD bip_dba=$BIPDBA_PASSWORD liquibase_admin=$LIQUID_PASSWORD fqdn=$HOST

#Register instance in OEM
SYSMAN_PASS=`vault kv get $OEM_PATH| grep sysman | awk '{ print $2 }'`
/home/oracle/emcli/emcli login -username=SYSMAN -password=$SYSMAN_PASS
/home/oracle/emcli/emcli add_target \
  -name="${DBInstanceID}" \
  -type="oracle_database" \
  -host="${HOST}" \
  -credentials="UserName:DBSNMP;password:${DBSNMP_PASSWORD};Role:Normal" \
  -properties="SID:ORCL;Port:1521;OracleHome:/oracle;MachineName:${HOST}"

#Create standby instance in gov-east
DB_ARN=`printf "$AWSRDS" | jq -r '.DBInstances | map([.DBInstanceArn] | join (",")) | join("")' | awk 'BEGIN { FS = "?" } {printf $1}'`
export AWS_DEFAULT_REGION=us-gov-east-1
aws cloudformation create-stack --stack-name ${DBInstanceID}-rds-dr --template-body file:////home/oracle/bia-devel/aws/cft/cft-rds-oracle-replica.yaml --parameters ParameterKey=VPC,ParameterValue=$VPC ParameterKey=SourceName,ParameterValue=$DBInstanceID ParameterKey=SourceARN,ParameterValue=$DB_ARN ParameterKey=StorageType,ParameterValue=$STORAGETYPE ParameterKey=SourceEncrypted,ParameterValue=$ENCRYPTED

