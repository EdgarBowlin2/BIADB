#!/bin/bash

# Parameters
export stackname=$1
export instanceid=$2
export connstring=$3
export passwd=$4
echo "Stack " $stackname " Instance  " $instanceid "  ConnString " $connstring "  Password " $passwd

#Delete Stack
echo "Begin Stack deletion of: " $stackname " at " `date`

echo "aws cloudformation delete-stack --stack-name ${stackname}"
aws cloudformation delete-stack --stack-name ${stackname}

#wait 10 seconds
sleep 60

#Monitor Stack Deletion
echo "Monitor Stack Deletion of: " $stackname " " `date`
echo "aws cloudformation wait stack-delete-complete --stack-name ${stackname}"
aws cloudformation wait stack-delete-complete --stack-name ${stackname}
echo $stackname " has been deleted. " `date`

#Launch Cloud Formation Template
echo "Launch Cloud Formation Template for: " $stackname " " `date`

echo "aws cloudformation create-stack --stack-name ${stackname} --template-url https://prod-dbas.s3-us-gov-west-1.amazonaws.com/BIP/BPDS/PRODTEST/patrick-orcl-replica-v2.yml"
aws cloudformation create-stack --stack-name ${stackname} --template-url https://prod-dbas.s3-us-gov-west-1.amazonaws.com/BIP/BPDS/PRODTEST/patrick-orcl-replica-v2.yml

#wait 10 seconds
sleep 60

#Monitor Stack Creation
echo "Monitor Stack Creation. " `date`
echo "aws cloudformation wait stack-create-complete --stack-name ${stackname}"
aws cloudformation wait stack-create-complete --stack-name ${stackname}

#Repeat Monitor
echo "If Stack is Still Creating, issue wait -stack-create-complete command again. " `date`
echo "Else, echo Create Complete. "
export STACKCREATE=`aws cloudformation describe-stacks --stack-name ${stackname} --query 'Stacks[0].StackStatus' --output text`
if [[ $STACKCREATE != "CREATE_COMPLETE" ]]; then
    aws cloudformation wait stack-create-complete --stack-name ${stackname}
 else
    echo "Stack Creation is Complete. " `date` 
fi

#Promote Instance
sleep 60
echo "Promote Instance : " $instanceid " " `date`
echo "First, Wait for Instance Available."
echo "aws rds wait db-instance-available --db-instance-identifier ${instanceid}"
aws rds wait db-instance-available --db-instance-identifier ${instanceid}
echo "Instance: " $instanceid " Is Available. " `date`

echo "Promote Read Replica Instance: " $instanceid " " `date`
echo "aws rds promote-read-replica --db-instance-identifier ${instanceid}"
aws rds promote-read-replica --db-instance-identifier ${instanceid}

#wait 10 seconds
sleep 60

#Monitor Instance Promotion
echo "Monitor Instance Promotion of: " $instanceid " " `date`
echo "aws rds wait db-instance-available --db-instance-identifier ${instanceid}"
aws rds wait db-instance-available --db-instance-identifier ${instanceid}

#Repeat Monitor
echo "if Instance is Still Not Available, Repeat Monitor. " `date`
echo "Else, if Instance Available, echo Promotion Complete."
export INSTANCEPROMOTE=`aws rds describe-db-instances --db-instance-identifier ${instanceid} --query 'DBInstances[*].{DBStatus:DBInstanceStatus}' --output text`
if [[ $INSTANCEPROMOTE != "available" ]]; then
    aws rds wait db-instance-available --db-instance-identifier ${instanceid}
 else
    echo "Stack Promotion is Complete for: " $stackname " " `date`
fi

echo "Check Database Status. " `date`
#Check database status
export conn="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=patrick-replica.cetxxdbd6our.us-gov-west-1.rds.amazonaws.com)(PORT=1521))(CONNECT_DATA=(SERVER=DEDICATED)(SID=ORCL)))"
export DBSTATUS=`sqlplus -s dbadmin/${passwd}@${conn}<<EOF
set echo off
set feedback off
set termout off
set pages 0
select open_mode from v\\$database;
exit
EOF`

if [[ "$DBSTATUS" != "READ WRITE" ]]; then
    echo "*** Database Status is not open.  Please investigate.  Exiting..."
    exit 1
 else
    echo "Database Status is Open."
fi

echo "Database Refresh Complete for: " $stackname " " `date` 
