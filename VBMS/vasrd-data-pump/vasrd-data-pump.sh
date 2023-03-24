#!/bin/bash

## CRONTAB USAGE
## assumes export from vasrd-int
## x x * * x cd /home/oracle/github/VBMS/vasrd-data-pump && ./vasrd-data-pump.sh -d <db-instance-identifier> -l VASRD_INT -f rules_manager_vasrd-int_`date "+\%m\%d\%y"`.dmp > ./vasrd-data-pump.log 2>&1 

# set environment
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/VBMS/local/env

# parse command line
usage() {
    echo "usage: $0 [ -d DB-INSTANCE-IDENTIFIER ] [ -l DATABASE LINK NAME ] [ -f EXPORT FILE NAME ]" 1>&2
    exit 1
}

while getopts ":d:f:l:" options; do
    case "${options}" in
        d)
            DATABASE=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
            ;;
        f)
            FILENAME=${OPTARG}
            ;;
        l)
            DBLINK=$(echo "${OPTARG}" | tr '[:lower:]' '[:upper:]')
            ;;
        :)
            echo "ERROR: -${OPTARG} requires an argument."
            usage
            ;;
        *)
            usage
            ;;
    esac
done

if [[ -z "$DATABASE" ]]; then
    echo "ERROR: -d is a mandatory parameter."
    usage
fi

if [[ -z "$FILENAME" ]]; then
    echo "ERROR: -f is a mandatory parameter."
    usage
fi

if [[ -z "$DBLINK" ]]; then
    echo "ERROR: -l is a mandatory parameter."
    usage
fi

send_vasrd_report() {
    local SUBJECT="$1"
    echo "subject: vasrd-data-pump "$SUBJECT | cat - $GITROOT/VBMS/local/distro.vbms | sendmail -t
}

#begin
set_vault_environment

RDSINFO=$(get_database_metadata "$DATABASE")

if [[ $? -ne 0 ]]; then
    echo "aws rds describe-db-instances failed for $DATABASE"
    exit 1
fi

HOST=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Address)
PORT=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Port)
SID=$(echo $RDSINFO | jq -r .DBInstances[].DBName)
MASTER=$(echo $RDSINFO | jq -r .DBInstances[].MasterUsername)

# get database passwords
MASTER_PASSWORD=$(vault kv get -field=master-password secret/platform/candp-dbas/$DATABASE)

if [ -z "$MASTER_PASSWORD" ]; then
    echo Missing password for $DATABASE Database. Exiting script now.
    send_vasrd_report "ERROR retrieving $DATABASE password"
    exit 1
fi

RULES_MANAGER_PASSWORD=`sqlplus -s $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
  SET HEAD OFF
  SET LINESIZE 500
  SET LONG 500
  SET LONGCHUNK 500
  SELECT REGEXP_SUBSTR(SYS.DBMS_METADATA.GET_DDL('USER', 'RULES_MANAGER'), '''[^'']+''') FROM DBA_USERS WHERE USERNAME = 'RULES_MANAGER'; 
  EXIT
EOF
`

# verify no datapump jobs running on source database
JOBS_LEFT=1
while [ $JOBS_LEFT -ne 0 ]; do

    sleep 30

    JOBS_LEFT=`sqlplus -s $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
  SET HEAD OFF
  SET FEED OFF
  SELECT COUNT(*) FROM DBA_DATAPUMP_JOBS@$DBLINK;
  EXIT
EOF
    `

    echo Checking for data pump jobs executing on the source...

done


# TRANSFER DATAPUMP FILE
echo Transferring file to $DATABASE across database link $DBLINK.

# create transfer script
echo "BEGIN
DBMS_FILE_TRANSFER.GET_FILE(
source_directory_object => 'DATA_PUMP_DIR',
source_file_name => '$FILENAME',
destination_directory_object => 'DATA_PUMP_DIR',
destination_file_name => '$FILENAME',
source_database => '$DBLINK'
);
END;
/
" >file_transfer.sql

# create DATA_PUMP_DIR cleanup script
echo "BEGIN
    FOR f in (SELECT FILENAME FROM TABLE(rdsadmin.rds_file_util.listdir(p_directory => 'DATA_PUMP_DIR')) WHERE MTIME < SYSDATE - 35)
    LOOP
            UTL_FILE.FREMOVE('DATA_PUMP_DIR',f.filename);
    END LOOP;
END;
/
" >cleanup.sql

# initiate the transfer
sqlplus -s $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
@cleanup.sql
@file_transfer.sql
EOF

# verify transfer
EXPORT_SIZE=`sqlplus -s $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
    set serveroutput on
    set feedback off
DECLARE
    fexists      BOOLEAN;
    file_length  NUMBER;
    block_size   BINARY_INTEGER;
BEGIN
    UTL_FILE.FGETATTR@$DBLINK ('DATA_PUMP_DIR', '$FILENAME', fexists, file_length, block_size);
    IF fexists THEN
        dbms_output.put_line(file_length);
    ELSE
        dbms_output.put_line('ERROR');
    END IF;
END;
/
EOF
    `

IMPORT_SIZE=`sqlplus -s $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
    set serveroutput on
    set feedback off
DECLARE
    fexists      BOOLEAN;
    file_length  NUMBER;
    block_size   BINARY_INTEGER;
BEGIN
    UTL_FILE.FGETATTR ('DATA_PUMP_DIR', '$FILENAME', fexists, file_length, block_size);
    IF fexists THEN
        dbms_output.put_line(file_length);
    ELSE
        dbms_output.put_line('ERROR');
    END IF;
END;
/
EOF
    `

if [[ "$IMPORT_SIZE" == "ERROR" ]] || [[ "$EXPORT_SIZE" == "ERROR" ]]; then
    echo Transfer to $DATABASE unsuccessful. Exiting script now.
    send_vasrd_report "ERROR unsuccessful transfer to $DATABASE"
    exit 1
fi

if [ $IMPORT_SIZE != $EXPORT_SIZE ]; then
    echo Transfer to $DATABASE unsuccessful. Exiting script now.
    send_vasrd_report "ERROR unsuccessful transfer to $DATABASE"
    exit 1
fi

echo The transfer to $DATABASE is complete. Checking for RULES_MANAGER sessions.

# IMPORT PREPARATION
# create STAGE import script
echo "DECLARE
hdnl NUMBER;
BEGIN
hdnl := DBMS_DATAPUMP.OPEN( operation => 'IMPORT', job_mode => 'SCHEMA', job_name=>null, VERSION=>'11.2');
DBMS_DATAPUMP.ADD_FILE( handle => hdnl, filename => '$FILENAME', directory => 'DATA_PUMP_DIR', filetype => dbms_datapump.ku\$_file_type_dump_file);
DBMS_DATAPUMP.ADD_FILE( handle => hdnl, filename => '$FILENAME.log', directory => 'DATA_PUMP_DIR', filetype => dbms_datapump.ku\$_file_type_log_file);
DBMS_DATAPUMP.METADATA_FILTER(hdnl,'SCHEMA_EXPR','IN (''RULES_MANAGER'')');
DBMS_DATAPUMP.START_JOB(hdnl);
END;
/
" >file_import.sql

# create RULES_MANAGER recreate script
echo "drop user RULES_MANAGER cascade;

CREATE USER "RULES_MANAGER" IDENTIFIED BY VALUES $RULES_MANAGER_PASSWORD
    DEFAULT TABLESPACE "RULES_MANAGER_TS"
    TEMPORARY TABLESPACE "TEMP"
    PROFILE "APP_PROFILE_RATINGS";
     
GRANT CREATE ANY MATERIALIZED VIEW TO "RULES_MANAGER";
GRANT CREATE MATERIALIZED VIEW TO "RULES_MANAGER";
GRANT CREATE ANY TABLE TO "RULES_MANAGER";
GRANT UNLIMITED TABLESPACE TO "RULES_MANAGER";
GRANT CREATE SESSION TO "RULES_MANAGER";
" >rules_manager_recreate.sql

# create post import cleanup script
echo "DELETE FROM RULES_MANAGER.SCHEDULE WHERE PUBLISHED = 0;
TRUNCATE TABLE RULES_MANAGER.TRANSACTION_ATTR;
ALTER TABLE RULES_MANAGER.TRANSACTION_ATTR DISABLE CONSTRAINT FK_TRANSACTION_ATTR_TX;
TRUNCATE TABLE RULES_MANAGER.TRANSACTION;
ALTER TABLE RULES_MANAGER.TRANSACTION_ATTR ENABLE CONSTRAINT FK_TRANSACTION_ATTR_TX;
DELETE FROM RULES_MANAGER.DVS_RESULT_SUMMARY;
DELETE FROM RULES_MANAGER.DVS_INPUT_SUMMARY;
DELETE FROM RULES_MANAGER.DVS_FILE;
DELETE FROM RULES_MANAGER.VASRD_USER WHERE LOGIN NOT IN ('ADMIN', 'RATINGSVIEW', 'RATINGSWRITE');
COMMIT;
" >post_cleanup.sql

if [[ "$AWSACCOUNT" == "P" ]]; then
    echo "DELETE FROM RULES_MANAGER.SCHEDULE WHERE TEST_MODE = 1;
COMMIT;
" >>post_cleanup.sql
fi

# IMPORT
# verify application is down
APP_CONNECTIONS=50
SESSION='v$session'
ATTEMPTS=0

while [ $APP_CONNECTIONS -ne 0 ]; do

    ATTEMPTS=$((ATTEMPTS + 1))
    APP_CONNECTIONS=`sqlplus -s $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
  SET HEAD OFF
  SET FEED OFF
  SELECT COUNT(*) FROM $SESSION WHERE USERNAME='RULES_MANAGER' AND STATUS!='KILLED';
  EXIT
EOF
    `

    sleep 30

    if [ $ATTEMPTS -gt 30 ]; then
        echo Application in $DATABASE has been up for 15 minutes. Exiting script now.
        send_vasrd_report "ERROR $DATABASE application up"
        exit 1
    fi

    echo There are currently $APP_CONNECTIONS application accounts still connected in $DATABASE. Attempt $ATTEMPTS of 30.

done

echo There are zero RULES_MANAGER sessions in $DATABASE. Beginning Import.

# import
sqlplus $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
@rules_manager_recreate.sql
@file_import.sql
EOF

JOBS_LEFT=1
while [ $JOBS_LEFT -ne 0 ]; do

    sleep 30

    JOBS_LEFT=`sqlplus -s $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
  SET HEAD OFF
  SET FEED OFF
  SELECT COUNT(*) FROM DBA_DATAPUMP_JOBS;
  EXIT
EOF
    `

    echo The $DATABASE import job is still running.

done

echo The $DATABASE import is complete.

# verify import
IMPORT_VERIFY=`sqlplus -s $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
    SET HEAD OFF
    SET FEED OFF
    SELECT COUNT(*)
    FROM TABLE ( rdsadmin.rds_file_util.read_text_file(p_directory => 'DATA_PUMP_DIR', p_filename => '$FILENAME.log') )
    WHERE TEXT LIKE '%ORA-%' AND TEXT NOT LIKE '%ORA-31684%';
    EXIT
EOF
    `

if [ $IMPORT_VERIFY -ne 0 ]; then
    echo Import errors detected. Exiting script now.
    send_vasrd_report "ERROR $IMPORT_VERIFY import errors"
    exit 1
fi

# execute post-import cleanup
sqlplus $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF
@post_cleanup.sql
EOF

# send completion e-mail
send_vasrd_report "$DATABASE COMPLETE $FILENAME"
