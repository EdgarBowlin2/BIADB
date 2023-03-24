#-----------------------------------------------------------------------------------------
#-  EC2 Snapshot Status V1.2                                                 04-25-2022
#-----------------------------------------------------------------------------------------
#-  Edgar Bowlin
#-----------------------------------------------------------------------------------------
#-  Purpose / Overview
#-----------------------------------------------------------------------------------------
#-  Using the Amazon Web Services (AWS) Command Line Interface (CLI) Version 2.x, this    
#-  script will review all snapshots, of all volumes associated with an instance, 
#-  reporting any failed or incomplete snapshots, along with their source volume, 
#-  start date, and current status. This process will be repeated for each instance in 
#-  an input list of AWS EC2 instances.
#-----------------------------------------------------------------------------------------
#-  Input 
#-----------------------------------------------------------------------------------------
#-  The input for this script is a text file named serverlist, with the following space 
#-  delimited format:
#- 
#-  EC2_Instance_Type EC2_Instance_ID EC2_Instance_Name
#-
#-  DEV i-0dc3daa66996a6784 (dev-vpc-sqlplus)
#-  DEV i-097e1468c93d5dfb2 (non-prod-bastion)
#-  STAGE i-0811388f36d51111b (project-candp-dba-stage-toolbox)
#-  STAGE i-0b929de1806cce2df (bia-dba-stage-toolbox)
#-  PROD i-06c243481f8393202 (project_bip_dba_oem)
#-  PROD i-0666fdf1871a7e5ec (project_bip_dba_admin)
#-----------------------------------------------------------------------------------------
#-  Revision History
#-----------------------------------------------------------------------------------------
#-  0.99  Edgar Bowlin  04-26-2022	Original Script for Peer Review
#-  1.0   Edgar Bowlin  05-10-2022      Production Release
#-  1.1   Edgar Bowlin  05-18-2022	Format Final Output for Better Readability
#-  1.2   Edgar Bowlin  05-19-2022  	Add Instance Name for better report useage.
#-----------------------------------------------------------------------------------------

#!/bin/bash

#----------------------------------------------------------------------------------------
#- SECTION ONE 
#----------------------------------------------------------------------------------------
#- For the EC2 instances specified in the input file, serverlist, retrieve the instance
#- volume ids. List the EC2 instances and instance volumes in an output file called
#- InstanceVolumes.txt
#----------------------------------------------------------------------------------------

#- For Each EC2 Instance, Get List of Volumes
input="/home/oracle/scripts/dbsnapshot/serverlist"

#- Initialize Output File - i.e. delete if it exists
if [ -e "InstanceVolumes.txt" ]; then
   rm InstanceVolumes.txt 
fi

#- Read Space Delimited Input File Into Three Variables
#- EC2 Instance Type (PROD, DEV, STAGE), EC2 Instance ID, EC2 Instance Name
while IFS=" "  read -r type id name 
  do
    #- For PROD EC2 Instances
    if [ $type = "PROD" ]; then
       echo $type"  "$name"  "$id
       aws ec2 describe-instances --filters Name=instance-id,Values=$id --output table | sed 's/+\-.*+//g' | sed 's/\-.*-//g' | sed 's/|//g' | awk -v instance=$id -v outtype="PROD" -v instancename=$name '/VolumeId/ { print outtype" "instance" "instancename" "$2 }' >> InstanceVolumes.txt
       #aws ec2 describe-instances --filters Name=instance-id,Values=$id --output table > $id".txt"
       #cat $id".txt" | sed 's/+\-.*+//g' | sed 's/\-.*-//g' | sed 's/|//g' | awk '/VolumeId/ { print $2 }' > $id"_final.txt"
       #cat $id".txt" | sed 's/+\-.*+//g' | sed 's/\-.*-//g' | sed 's/|//g' > $id"_clean.txt"
       #cat $id"_clean.txt" | awk '/VolumeId/ { print $2 }' > $id"_final.txt" 
    #- For STAGE EC2 Instances 
    elif [ $type = "STAGE" ]; then
       echo $type"  "$name"  "$id
       aws ec2 describe-instances --filters Name=instance-id,Values=$id --output table | sed 's/+\-.*+//g' | sed 's/\-.*-//g' | sed 's/|//g' | awk -v instance=$id -v outtype="STAGE" '/VolumeId/ { print outtype" "instance" "$2 }' >> InstanceVolumes.txt  
    #- For DEV EC2 Instances 
    elif [ $type = "DEV" ]; then
       echo $type"  "$name"  "$id
       aws ec2 describe-instances --filters Name=instance-id,Values=$id --output table | sed 's/+\-.*+//g' | sed 's/\-.*-//g' | sed 's/|//g' | awk -v instance=$id -v outtype="DEV" '/VolumeId/ { print outtype" "instance" "$2 }' >> InstanceVolumes.txt 
    fi 
  done < $input

#----------------------------------------------------------------------------------------
#- SECTION TWO 
#----------------------------------------------------------------------------------------
#- Using the InstanceVolumes.txt file from Section 1 as input, retrieve EC2 
#- Snapshots that have failed for all instance volumes. Create an output file 
#- SnapshotFails.txt, containing the Instance Type, Instance ID, Instance Volume,  
#- Snapshot ID, Start Time, Status. 
#----------------------------------------------------------------------------------------


#- Initialize Output File - i.e. delete if it exists
if [ -e "SnapshotFails.txt" ]; then
   rm SnapshotFails.txt 
fi

#Header with Column Names for AWS Command Output
echo Nothing | awk -v OFS='\t' '{ print "TYPE     ",   " INSTANCE     ",  " INSTANCENAME     ", "      VOLUME               ",       " SNAPSHOT               ",    "SNAPSHOT CREATED    ",    " STATUS    " }' >>SnapshotFails.txt

#- Read Space Delimited Output File of Instances and Instance Volumes from Section 1
while IFS=" " read -r type instance instancename volume
  do
     #echo $type "  " $instance "  " $volume >> SnapshotFails.txt 
     #aws ec2 describe-snapshots --filters Name=status,Values=completed,pending Name=volume-id,Values=$volume --output table | sed 's/+\-.*+//g' | sed 's/\-.*-//g' | sed 's/|//g' | awk -v outtype=$type -v outinstance=$instance -v outvolume=$volume '/SnapshotId/ { Snap=$2; next } /StartTime/ { Start=$2; next } /State/ { print outtype" "outinstance" "outvolume" "Snap" "Start" "$2 }' >> SnapshotFails.txt 

     aws ec2 describe-snapshots --filters Name=status,Values=completed,pending Name=volume-id,Values=$volume --output table | sed 's/+\-.*+//g' | sed 's/\-.*-//g' | sed 's/|//g' | awk -v outtype=$type -v outinstance=$instance -v outname=$instancename -v outvolume=$volume -v OFS='\t' '/SnapshotId/ { Snap=$2; next } /StartTime/ { Start=$2; next } /State/ { print outtype, outinstance, outname, outvolume, " " , Snap, Start,"   "$2 }' >> SnapshotFails.txt 

  done < InstanceVolumes.txt

 #echo "subject: EC2 Snapshot Statuses " | cat - emaillist.txt /home/oracle/scripts/dbsnapshot/SnapshotFails.txt  | /usr/sbin/sendmail -t
/usr/sbin/sendmail -v "edgar.bowlin@va.gov, patrick.lynn@va.gov" -s "EC2 Snapshot Status" < /home/oracle/bia-devel/BIA/scripts/dbsnapshot/SnapshotFails.txt


