#!/bin/bash
#--------------------------------------------------------------------------------
#-  BIA Health Check                                                1.5
#--------------------------------------------------------------------------------
#-  Edgar Bowlin                                                    02-25-2022
#--------------------------------------------------------------------------------
#-  This script executes three metrics, OEM Database Status,
#-  AWS DMS Task Latency, and CFT Prodtest Task Latency into one health report
#-  output file, BIAHealthCheck.txt.
#--------------------------------------------------------------------------------
#-  Input
#--------------------------------------------------------------------------------
#-  starttime, endtime for DMS Task Source and Target Latency  These variables
#-  are optional.  If provided on the command line, they will be used; otherwise,
#-  default values are assigned.
#--------------------------------------------------------------------------------
#- Revision History
#--------------------------------------------------------------------------------
#- 03-07-2022 Edgar Bowlin 1.1  Removed intermediate files for DMS Latency
#-                              metrics, changed timeframe as noted in
#-                              comments, report only top 15 highest latencies
#-                              per metric, per timeframe.
#--------------------------------------------------------------------------------
#- 03-09-2022 Edgar Bowlin 1.2 Adding additional secondary DMS metric. One metric 
#-                             will be the most recent 10 latency values per 
#-			       source/target latency measure, while the second
#-                             metric will be the highest 10 values per source/
#-                             target measure over past 12 hours. The highest 
#-                             values will be combined into a single, global
#-                             list from which the 10 highest latency values 
#-                             overall will be chosen for the health report. 
#--------------------------------------------------------------------------------
#- 03-31-2022 Patrick Lynn 1.3 Added new emails to report distro and fixed email subject
#--------------------------------------------------------------------------------
#- 11-14-2022 Edgar Bowlin 1.4 Added new employee email, Connor Northrop,
#-        		       revised paths.
#--------------------------------------------------------------------------------
#- 11-17-2022 Edgar Bowlin 1.5 Added Claims and BPDS databases to health check.
#-                             Added force switch to emcli login to override 
#-                             existing login, not error out. Added emcli sync
#-                             command prior to database health checks to ensure
#-                             most recent status information.
#-                             Removed emcli get_jobs -status_ids, awk and sed 
#-                             processing as get_jobs had a not supported against
#-                             agents speaking 13.2.0.0 client protocol. A much
#-                             better and more direct method is emcli get_targets
#-                             requiring minimal post processing to get DB status. 
#--------------------------------------------------------------------------------

#------------------------------------------------------
#- Adding all possible locations of executable files
#- to the existing PATH. The $PATH was originally left 
#- off the end of this PATH statement - VERY BAD - 
#- that "clobbers" the existing PATH rather than just
#- adding things to it, NEVER do that. 
#------------------------------------------------------

export PATH=/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/home/oracle/.local/bin:/home/oracle/bin:$PATH

#----------------------------------------------------------
#- Get Database Status for All BIA Databases via OEM
#- command line commands.
#----------------------------------------------------------
#- OEM Connection
#----------------------------------------------------------


#-------------------------------------------------------------------------------------
#- Set Environment and execute set_vault_environment function in env to prepare to 
#- execute vault commands to retrieve OEM account password. 
#-------------------------------------------------------------------------------------
. $SCRIPT_DIR/functions/functions.sh
set_vault_environment

#-------------------------------------------------------------------------------------
#- Execute Vault command to retrieve sysman account password for the correct 
#- environment. 
#-------------------------------------------------------------------------------------

#-- DEV Environment OEM
#-  SYSMAN_PASS=`vault kv get secret/platform/database-admin/bip-dev-oem | grep sysman | awk '{ print $2 }'`
#-- PROD Environment OEM
SYSMAN_PASS=`vault kv get secret/platform/prodops-dba/bip-oem | grep sysman | awk '{ print $2 }'`

#-------------------------------------------------------------------------------------
#-- OEM cli login with password retrieved from Vault also using force option to prevent
#-- error if account is already logged in.
#-------------------------------------------------------------------------------------
/home/oracle/software/emcli/emcli login -username=SYSMAN -password=$SYSMAN_PASS -force

#-----------------------------------------------------------------------------------
#- emcli get_targets will produce a "command not recognized/available" error if
#- emcli sync is not executed prior to the emcli get_targets verb.  
#-----------------------------------------------------------------------------------
/home/oracle/software/emcli/emcli sync

#-----------------------------------------------------------------------------------
#- Simpler method than emcli get_jobs using get_targets. 
#- Get DB Status directly from OEM Repository with minimal parsing effort.
#-----------------------------------------------------------------------------------
#- First Write to Output File is (>) to Clobber/Overwrite if File Exists.
#Add the subject into the txt file
echo "Subject: BIA Health Report" > /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo "Database Status for all BIA Databases" >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
/home/oracle/software/emcli/emcli get_targets -target=oracle_database -format="name:pretty" | grep fraud | awk '{ print $4"  "$2 }' >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
/home/oracle/software/emcli/emcli get_targets -target=oracle_database -format="name:pretty" | grep claims | awk '{ print $4"   "$2 }' >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
/home/oracle/software/emcli/emcli get_targets -target=oracle_database -format="name:pretty" | grep bpds | awk '{ print $4"   "$2 }' >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt

echo
echo "Oracle OEM Database Status written to BIAHealthCheck.txt"
echo

#----------------------------------------------------------
#- End OEM CLI Get Database Status Script
#----------------------------------------------------------

#--------------------------------------------------------------------------------
#-  DMS Latency Measurement via AWS CLI commands
#--------------------------------------------------------------------------------
# - Data Migration Services (DMS) Jobs to Be Measured.
#--------------------------------------------------------------------------------
#- fraud-prev-corp-prod-task-1 ARN: LFOHNQB5QJ7KN52IH3ZPWIAMN5DCY26YMW45CPY
#- fraud-prev-corp-prod-task-2 ARN: 3CYYMU5MRFNAYP7UFSWI5I7QOJUNOFJUIVJXLMI
#- fraud-prev-corp-prod-task-3 ARN: V4X5ZZHXCC3IDJKXYVPQ6LFFALBMQP6KXMRD2QA 
#- fraud-prev-corp-prod-task-4 ARN: Y463CR2TK2LQP2XOIKSCOV2KHXD25XK6LDH3DDA
#--------------------------------------------------------------------------------
#- AWS command line (CLI) commands will be used to retrieve AWS Cloudwatch
#- performance metrics stored in the AWS cloud for the DMS tasks above.
#--------------------------------------------------------------------------------

#--------------------------------------------------------------------------------
#- Get Source and Target DMS Latency via AWS CLI commands for the four fraud
#- prev jobs listed above.
#--------------------------------------------------------------------------------

#--------------------------------------------------------------------------------
#- If start and end time arguments are provided on the command line, use them;
#- otherwise, use default values.
#--------------------------------------------------------------------------------

if [[ -n $1 && -n $2 ]]; then
  starttime=$1
  endtime=$2
else
  #------------------------------------
  #- Default 7pm to 6:45am   EST
  #-         12am to 11:45am UTC
  #------------------------------------
  starttime=`date +%Y-%m-%d`"T00:00:00Z"
  endtime=`date +%Y-%m-%d`"T11:45:00Z"
fi

#-------------------------------------------------------------------------------
#-  fraud-prevention-corp-task-1 DMS Source and Target Latency
#-------------------------------------------------------------------------------
echo "fraud-prevention Data Migration Task Source and Target Latencies" >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt

#- Task 1 Source Latency Max Values
aws cloudwatch get-metric-statistics --metric-name CDCLatencySource --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=LFOHNQB5QJ7KN52IH3ZPWIAMN5DCY26YMW45CPY --output table | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { printf("T1_Source "$2" "$1"\n"); }' | sort -k 3 -n -u -r | head -10 > /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/DMS.txt

#- Task 1 Target Latency Max Values
aws cloudwatch get-metric-statistics --metric-name CDCLatencyTarget --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=LFOHNQB5QJ7KN52IH3ZPWIAMN5DCY26YMW45CPY --output table | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { printf( "T1_Target "$2" "$1"\n"); }' | sort -k 3 -n -u -r | head -10 >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/DMS.txt 

#- Task 2 Source Latency Max Values
aws cloudwatch get-metric-statistics --metric-name CDCLatencySource --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=3CYYMU5MRFNAYP7UFSWI5I7QOJUNOFJUIVJXLMI --output table | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { printf( "T2_Source "$2" "$1"\n"); }' | sort -k 3 -n -u -r | head -10 >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/DMS.txt

#- Task 2 Target Latency Max Values
aws cloudwatch get-metric-statistics --metric-name CDCLatencyTarget --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=3CYYMU5MRFNAYP7UFSWI5I7QOJUNOFJUIVJXLMI --output table | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { printf( "T2_Target "$2" "$1"\n"); }' | sort -k 3 -n -u -r | head -10 >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/DMS.txt

#- Task 3 Source Latency Max Values
aws cloudwatch get-metric-statistics --metric-name CDCLatencySource --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=V4X5ZZHXCC3IDJKXYVPQ6LFFALBMQP6KXMRD2QA --output table | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { printf( "T3_Source "$2" "$1"\n"); }' | sort -k 3 -n -u -r | head -10 >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/DMS.txt

#- Task 3 Target Latency Max Values
aws cloudwatch get-metric-statistics --metric-name CDCLatencyTarget --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=V4X5ZZHXCC3IDJKXYVPQ6LFFALBMQP6KXMRD2QA --output table | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { printf( "T3_Target "$2" "$1"\n"); }' | sort -k 3 -n -u -r | head -10 >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/DMS.txt

#- Task 4 Source Latency Max Values
aws cloudwatch get-metric-statistics --metric-name CDCLatencySource --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=Y463CR2TK2LQP2XOIKSCOV2KHXD25XK6LDH3DDA --output table | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { printf( "T4_Source "$2" "$1"\n"); }' | sort -k 3 -n -u -r | head -10 >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/DMS.txt

#- Task 4 Target Latency Max Values
aws cloudwatch get-metric-statistics --metric-name CDCLatencyTarget --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=Y463CR2TK2LQP2XOIKSCOV2KHXD25XK6LDH3DDA --output table | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { printf( "T4_Target "$2" "$1"\n"); }' | sort -k 3 -n -u -r | head -10 >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/DMS.txt

echo "Top 10 Source/Target Latencies Across All BIA DMS Tasks" >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
cat /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/DMS.txt | sort -k 3 -n -u -r | head -10 >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt

echo "fraud_prev_corp_prod_task_1  DMS_Source_Latency" >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
aws cloudwatch get-metric-statistics --metric-name CDCLatencySource --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=LFOHNQB5QJ7KN52IH3ZPWIAMN5DCY26YMW45CPY --output table | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { print$2"  "$1 }' | sort | tail -10 >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt

echo "fraud_prev_corp_prod_task_1  DMS_Target_Latency" >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
aws cloudwatch get-metric-statistics --metric-name CDCLatencyTarget --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=LFOHNQB5QJ7KN52IH3ZPWIAMN5DCY26YMW45CPY --output table | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { print$2"  "$1 }' | sort | tail -10 >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt

#-------------------------------------------------------------------------------
#-  fraud-prevention-corp-task-2 DMS Source and Target Latency
#-------------------------------------------------------------------------------

echo "fraud_prev_corp_prod_task_2  DMS_Source_Latency" >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
aws cloudwatch get-metric-statistics --metric-name CDCLatencySource --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=3CYYMU5MRFNAYP7UFSWI5I7QOJUNOFJUIVJXLMI --output table | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { print$2"  "$1 }' | sort | tail -10 >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt

echo "fraud_prev_corp_prod_task_2  DMS_Target_Latency" >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
aws cloudwatch get-metric-statistics --metric-name CDCLatencyTarget --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=3CYYMU5MRFNAYP7UFSWI5I7QOJUNOFJUIVJXLMI --output table | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { print$2"  "$1 }' | sort | tail -10 >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt

#-------------------------------------------------------------------------------
#-  fraud-prevention-corp-task-3 DMS Source and Target Latency
#-------------------------------------------------------------------------------

echo "fraud_prev_corp_prod_task_3  DMS_Source_Latency" >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
aws cloudwatch get-metric-statistics --metric-name CDCLatencySource --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=V4X5ZZHXCC3IDJKXYVPQ6LFFALBMQP6KXMRD2QA --output table | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { print$2"  "$1 }' | sort | tail -10 >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt

echo "fraud_prev_corp_prod_task_3  DMS_Target_Latency" >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
aws cloudwatch get-metric-statistics --metric-name CDCLatencyTarget --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=V4X5ZZHXCC3IDJKXYVPQ6LFFALBMQP6KXMRD2QA --output table | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { print$2"  "$1 }' | sort | tail -10 >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt

#-------------------------------------------------------------------------------
#-  fraud-prevention-corp-task-4 DMS Source and Target Latency
#-------------------------------------------------------------------------------

echo "fraud_prev_corp_prod_task_4  DMS_Source_Latency" >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
aws cloudwatch get-metric-statistics --metric-name CDCLatencySource --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=Y463CR2TK2LQP2XOIKSCOV2KHXD25XK6LDH3DDA --output table | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { print$2"  "$1 }' | sort | tail -10 >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt

echo "fraud_prev_corp_prod_task_4  DMS_Target_Latency" >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
aws cloudwatch get-metric-statistics --metric-name CDCLatencyTarget --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=Y463CR2TK2LQP2XOIKSCOV2KHXD25XK6LDH3DDA --output table | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { print$2"  "$1 }' | sort | tail -10 >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt

echo
echo "Amazon AWS Data Migration Services Jobs for Fraud Prevention Latency/Status Written to BIAHealthCheck.txt"
echo

#- End DMS Latency Section

#--------------------------------------------------------------------------------
#-  Get CFT Prodtest Refresh Latency for BIA Prodtest Job via AWS CLI commands.
#--------------------------------------------------------------------------------
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo "bpds-prodtest-orcl-replica Process Status " >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
aws cloudformation describe-stacks --stack-name bpds-prodtest-orcl-replica | jq -r '.Stacks[] | .StackStatus' >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo >> /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt

echo
echo "Amazon AWS Cloud Formation Template ProdTest Refresh Status Written to BIAHealthCheck.txt"
echo

#- End CFT Prodtest Refresh Health and Status

#--------------------------------------------------------------------------------
#-  Email results using sendmail.
#--------------------------------------------------------------------------------
echo "Subject: BIA Health Report" | sendmail -v "edgar.bowlin@va.gov" "patrick.lynn@va.gov" "connor.northrop@va.gov" "kingsley.ukiwo@va.gov" < /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
#echo "Subject: BIA Health Report" | sendmail -v "edgar.bowlin@va.gov" < /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
#sendmail -v "edgar.bowlin@va.gov" "patrick.lynn@va.gov" "connor.northrop@va.gov"  < /home/oracle/scripts/bia-devel/BIA/scripts/dbhealth/BIAHealthCheck.txt
echo
echo "BIA Health Check Report Complete and Emailed to BIA Team Recipients."
echo

#- End BIA Database Health Check

