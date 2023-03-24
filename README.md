
BID Database Operations (bid-database-ops)

Github directory structure

#---------------------------------------------
#- Current Github Directory Structure
#---------------------------------------------
#- Implemented 02-17-2023
#---------------------------------------------

The bid-database-ops repository is shared among all members of BIA, EVR, MBMS, and VBMS database system teams; however it is only really 
used by BIA and VBMS teams. Thus, the main BIA directory of the github repository is /home/oracle/github/bia-devel/BIA, while the main VBMS  
directory is /home/oracle/github/vbms-devel/VBMS.  All files in the Old ~/github/bia-devel/BIA and ~/github/bia-devel/BIA/VBMS paths have 
been moved to the ~/github/bia-devel/BIA and ~/github/vbms-devel/VBMS directories, respectively.  

/home/oracle/github/bia-devel/BIA/scripts
---------------------------------------------
/docs - Free form ASCII text files documenting processes, code operation, etc. Make additional subdirectories as appropriate.
/scripts - All code used by BIA Database System Team.
	/aws  				Scripts using aws command line functions. Subdirectories by aws components, ec2, rds, etc.
	/cdc				Confluent/Kafka Connector scripts for creation, revision, maintenance of connectors.
	/dbhealth			Scripts querying database health parameters and reporting them via emails to DBAs.
	/dbsnapshot               	Scripts to create database snapshots.
        /envfiles			Master environment files that set environment variables, parameters, etc. 
        /functions 			Contains functions.sh and other library files as needed to simplify scripting and centralize/single source often used functions.
        /health-check			Contains script and supporting files/scripts/sql files for checking all database metrics and emailing team members. 
  	/inactiveusers                  Scripts that generate inactive user lists, emails DBAs, deletes users, if required.
	/log  				Main log directory for all scripting.  Subdirectories for AWS, CDC, EMCLI, etc. as needed.
	/monitor 			Report generation scripts that generate a single report for multiple SQL queries as needed.
	/oem 				Oracle EM command line scripts for any EM functionality from adding instances to retrieving metrics.
	/passwordmgmt 			Scripts that email users as their passwords age close to expiration.
	/redis 				Parameters for redis database functionality.
	/refresh			Scripts for refreshing databases.
	/reset-expired-password 	Scripts to reset expiring passwords, particularly of admin accounts.
	/rman				Oracle backup scripts.
	/run_it				Script management scripts and supporting files. Main script is runjobs.
	/sh				Generic Linux BASH shell scripts, that is all other scripts not related to AWS, OEM, CDC, etc.
	/sql				Oracle SQL queries for often used DDL and DML statements.
     	/vault				Vault scripts to retrieve/add/update Vault key/value pairs or scalar (singular) values.
	
/home/oracle/github/vbms-devel/VBMS
-------------------------------------------
       There is not currently a subdirectory structure here, it is just a collection of scripts used by the VBMS team.

