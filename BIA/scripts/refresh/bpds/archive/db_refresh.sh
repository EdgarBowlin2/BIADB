#!/bin/bash
#10/19/22 Updated template to use new RHEL8 OEM OG - PEL
# Parameters
export stackname=$1
export instanceid=$2
export connstring=$3

#Delete Stack
date
echo "sudo aws cloudformation delete-stack --stack-name ${stackname}"
sudo aws cloudformation delete-stack --stack-name ${stackname}

#wait 10 seconds
sleep 60

#Monitor Stack Deletion
date
echo "sudo aws cloudformation wait stack-delete-complete --stack-name ${stackname}"
sudo aws cloudformation wait stack-delete-complete --stack-name ${stackname}

#Launch Cloud Formation Template
date
echo "sudo aws cloudformation create-stack --stack-name ${stackname} --template-url https://prod-dbas.s3-us-gov-west-1.amazonaws.com/BIP/BPDS/PRODTEST/bpds-prodtest-orcl-replica-v4-09112021.yml"
sudo aws cloudformation create-stack --stack-name ${stackname} --template-url https://prod-dbas.s3-us-gov-west-1.amazonaws.com/BIP/BPDS/PRODTEST/bpds-prodtest-orcl-replica-v4-09112021.yml

#wait 10 seconds
sleep 60

#Monitor Stack Creation
date
echo "sudo aws cloudformation wait stack-create-complete --stack-name ${stackname}"
sudo aws cloudformation wait stack-create-complete --stack-name ${stackname}

#Repeat Monitor
date
export STACKCREATE=`sudo aws cloudformation describe-stacks --stack-name ${stackname} --query 'Stacks[0].StackStatus' --output text`
if [[ $STACKCREATE != "CREATE_COMPLETE" ]]; then
    sudo aws cloudformation wait stack-create-complete --stack-name ${stackname}
 else
    echo "Stack create is complete"
fi

#Promote Instance
sleep 60
date
echo "sudo aws rds wait db-instance-available --db-instance-identifier ${instanceid}"
sudo aws rds wait db-instance-available --db-instance-identifier ${instanceid}
date
echo "sudo aws rds promote-read-replica --db-instance-identifier ${instanceid}"
sudo aws rds promote-read-replica --db-instance-identifier ${instanceid}

#wait 10 seconds
sleep 60

#Monitor Instance Promotion
date
echo "sudo aws rds wait db-instance-available --db-instance-identifier ${instanceid}"
sudo aws rds wait db-instance-available --db-instance-identifier ${instanceid}

#Repeat Monitor
echo "Repeat Monitor"
date
export INSTANCEPROMOTE=`sudo aws rds describe-db-instances --db-instance-identifier ${instanceid} --query 'DBInstances[*].{DBStatus:DBInstanceStatus}' --output text`
if [[ $INSTANCEPROMOTE != "available" ]]; then
    sudo aws rds wait db-instance-available --db-instance-identifier ${instanceid}
 else
    echo "Stack Promotion is complete"
fi

date
#Check database status
export DBSTATUS=`sqlplus -s /@${connstring}<<EOF
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
    exit 0
fi
