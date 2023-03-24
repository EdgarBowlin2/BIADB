#--------------------------------------------------------------------------------
#-  Fraud Prev DMS Latency Measurement via AWS CLI commands
#--------------------------------------------------------------------------------
#-  Edgar Bowlin						02-16-2022
#--------------------------------------------------------------------------------
# - Fraud Prev Data Migration Services (DMS) Jobs to Be Measured.
#--------------------------------------------------------------------------------
#- fraud-prev-corp-prod-task-1 ARN: LFOHNQB5QJ7KN52IH3ZPWIAMN5DCY26YMW45CPY
#- fraud-prev-corp-prod-task-2 ARN: 3CYYMU5MRFNAYP7UFSWI5I7QOJUNOFJUIVJXLMI
#- fraud-prev-corp-prod-task-3 ARN: 5IOHJ3MB6MVONFL6RBHTIWENAYRNMFG5MHVEPRQ
#- fraud-prev-corp-prod-task-4 ARN: Y463CR2TK2LQP2XOIKSCOV2KHXD25XK6LDH3DDA
#--------------------------------------------------------------------------------
#- AWS command line (CLI) commands will be used to retrieve AWS Cloudwatch
#- performance metrics stored in the AWS cloud for the DMS tasks listed above.
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
  #- Default 5am to 5pm EST 
  #-        10am to 10pm UTC
  #------------------------------------ 
  starttime=`date +%Y-%m-%d`"T10:00:00Z"
  endtime=`date +%Y-%m-%d`"T20:00:00Z"
fi 

#-------------------------------------------------------------------------------
#-  fraud-prevention-corp-task-1 DMS Source and Target Latency
#-------------------------------------------------------------------------------

aws cloudwatch get-metric-statistics --metric-name CDCLatencySource --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=LFOHNQB5QJ7KN52IH3ZPWIAMN5DCY26YMW45CPY --output table >> Task1Source.txt
cat Task1Source.txt | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { print $2"  "$1 }' > Task1.tmp 
cat Task1.tmp | sort > Task1.source 
#-----------------------------------------------------------------------------
#- First write to output file must be a "clobber", overwriting existing      
#- results, if any. 
#-----------------------------------------------------------------------------
echo "fraud_prev_corp_prod_task_1  DMS_Source_Latency" > DMSResults.txt 
echo >> DMSResults.txt 
cat Task1.source >> DMSResults.txt 
rm Task1* 

aws cloudwatch get-metric-statistics --metric-name CDCLatencyTarget --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=LFOHNQB5QJ7KN52IH3ZPWIAMN5DCY26YMW45CPY --output table >> Task2Source.txt
cat Task2Source.txt | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { print $2"  "$1 }' > Task2.tmp
cat Task2.tmp | sort > Task2.target
echo "fraud_prev_corp_prod_task_1  DMS_Target_Latency" >> DMSResults.txt 
echo >> DMSResults.txt 
cat Task2.target >> DMSResults.txt
rm Task2*

#-------------------------------------------------------------------------------
#-  fraud-prevention-corp-task-2 DMS Source and Target Latency
#-------------------------------------------------------------------------------

aws cloudwatch get-metric-statistics --metric-name CDCLatencySource --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=3CYYMU5MRFNAYP7UFSWI5I7QOJUNOFJUIVJXLMI --output table >> Task3Source.txt
cat Task3Source.txt | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { print $2"  "$1 }' > Task3.tmp 
cat Task3.tmp | sort > Task3.source 
echo "fraud_prev_corp_prod_task_2  DMS_Source_Latency" >> DMSResults.txt 
echo >> DMSResults.txt 
cat Task3.source >> DMSResults.txt 
rm Task3* 

aws cloudwatch get-metric-statistics --metric-name CDCLatencyTarget --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=3CYYMU5MRFNAYP7UFSWI5I7QOJUNOFJUIVJXLMI --output table >> Task4Source.txt
cat Task4Source.txt | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { print $2"  "$1 }' > Task4.tmp
cat Task4.tmp | sort > Task4.target
echo "fraud_prev_corp_prod_task_2  DMS_Target_Latency" >> DMSResults.txt 
echo >> DMSResults.txt 
cat Task4.target >> DMSResults.txt
rm Task4*

#-------------------------------------------------------------------------------
#-  fraud-prevention-corp-task-3 DMS Source and Target Latency
#-------------------------------------------------------------------------------

aws cloudwatch get-metric-statistics --metric-name CDCLatencySource --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=5IOHJ3MB6MVONFL6RBHTIWENAYRNMFG5MHVEPRQ --output table >> Task5Source.txt
cat Task5Source.txt | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { print $2"  "$1 }' > Task5.tmp 
cat Task5.tmp | sort > Task5.source 
echo "fraud_prev_corp_prod_task_3  DMS_Source_Latency" >> DMSResults.txt 
echo >> DMSResults.txt 
cat Task5.source >> DMSResults.txt 
rm Task5* 

aws cloudwatch get-metric-statistics --metric-name CDCLatencyTarget --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=5IOHJ3MB6MVONFL6RBHTIWENAYRNMFG5MHVEPRQ --output table >> Task6Source.txt
cat Task6Source.txt | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { print $2"  "$1 }' > Task6.tmp
cat Task6.tmp | sort > Task6.target
echo "fraud_prev_corp_prod_task_3  DMS_Target_Latency" >> DMSResults.txt 
echo >> DMSResults.txt 
cat Task6.target >> DMSResults.txt
rm Task6*

#-------------------------------------------------------------------------------
#-  fraud-prevention-corp-task-4 DMS Source and Target Latency
#-------------------------------------------------------------------------------

aws cloudwatch get-metric-statistics --metric-name CDCLatencySource --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=Y463CR2TK2LQP2XOIKSCOV2KHXD25XK6LDH3DDA --output table >> Task7Source.txt
cat Task7Source.txt | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { print $2"  "$1 }' > Task7.tmp 
cat Task7.tmp | sort > Task7.source 
echo "fraud_prev_corp_prod_task_4  DMS_Source_Latency" >> DMSResults.txt 
echo >> DMSResults.txt 
cat Task7.source >> DMSResults.txt 
rm Task7* 

aws cloudwatch get-metric-statistics --metric-name CDCLatencyTarget --start-time $starttime --end-time $endtime --period 300 --namespace AWS/DMS --statistics Average --dimensions Name=ReplicationInstanceIdentifier,Value=fraud-prevention-replication-instance Name=ReplicationTaskIdentifier,Value=Y463CR2TK2LQP2XOIKSCOV2KHXD25XK6LDH3DDA --output table >> Task8Source.txt
cat Task8Source.txt | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' | awk '/Seconds/ { print $2"  "$1 }' > Task8.tmp
cat Task8.tmp | sort > Task8.target
echo "fraud_prev_corp_prod_task_4  DMS_Target_Latency" >> DMSResults.txt 
echo >> DMSResults.txt 
cat Task8.target >> DMSResults.txt
rm Task8*

cat DMSResults.txt | sed 's/|//g' | sed 's/-//g' | sed 's/+//g' >> BIAHealthCheck.txt

