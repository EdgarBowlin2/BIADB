#!/bin/bash

#Capture User Information

#Delete Stack
sudo aws cloudformation delete-stack --stack-name mbms-prodtest-orcl-replica-test

#Monitor Stack
sudo aws cloudformation wait stack-delete-complete --stack-name mbms-prodtest-orcl-replica-test

#Launch Cloud Formation Template
sudo aws cloudformation create-stack --stack-name mbms-prodtest-orcl-replica-test --template-url https://prod-dbas.s3-us-gov-west-1.amazonaws.com/BIP/MBMS/ProdTestReplica/mbms-prodtest-orcl-replica-v4.yml

#Monitor Stack
sudo aws cloudformation wait stack-create-complete --stack-name mbms-prodtest-orcl-replica-test

echo $?

#Promote Instance
sudo aws rds promote-read-replica --db-instance-identifier mbms-prodtest-replica

#wait 10 seconds
sleep 10

#Monitor Instance
sudo aws rds wait db-instance-available --db-instance-identifier mbms-prodtest-replica

echo $?

#Check database status
export DBSTATUS=`sqlplus -s /@mbms-prodtest-replica<<EOF
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
