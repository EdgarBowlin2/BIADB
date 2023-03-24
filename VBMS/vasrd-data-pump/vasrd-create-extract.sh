#!/bin/bash
# set environment
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/VBMS/local/env

# parse command line
usage() {
    echo "usage: $0 [ -d DB-INSTANCE-IDENTIFIER ]" 1>&2
    exit 1
}

while getopts ":d:" options; do
    case "${options}" in
        d)
            DATABASE=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
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

# begin
set_vault_environment

send_vasrd_report() {
    local SUBJECT="$1"
    echo "subject: vasrd-create-extract "$SUBJECT | cat - $GITROOT/VBMS/local/distro.vbms | sendmail -t
}

RDSINFO=$(get_database_metadata "$DATABASE")

if [[ $? -ne 0 ]]; then
    echo "aws rds describe-db-instances failed for $DATABASE"
    exit 1
fi

DATESTAMP=$(date +%m%d%y)
HOST=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Address)
PORT=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Port)
SID=$(echo $RDSINFO | jq -r .DBInstances[].DBName)
MASTER=$(echo $RDSINFO | jq -r .DBInstances[].MasterUsername)
MASTER_PASSWORD=$(vault kv get -field=master-password secret/platform/candp-dbas/$DATABASE)

# create DATA_PUMP_DIR cleanup script
echo "BEGIN
    FOR f in (SELECT FILENAME FROM TABLE(rdsadmin.rds_file_util.listdir(p_directory => 'DATA_PUMP_DIR')) WHERE MTIME < SYSDATE - 35)
    LOOP
            UTL_FILE.FREMOVE('DATA_PUMP_DIR',f.filename);
    END LOOP;
END;
/
" >cleanup.sql

# create EXPORT script
echo "DECLARE 
hdnl NUMBER;
BEGIN
hdnl := DBMS_DATAPUMP.OPEN( operation => 'EXPORT', job_mode => 'SCHEMA', job_name=>null, version=>'11.2');
DBMS_DATAPUMP.ADD_FILE( handle => hdnl, filename => 'rules_manager_${DATABASE}_${DATESTAMP}.dmp', directory => 'DATA_PUMP_DIR', filetype => dbms_datapump.ku\$_file_type_dump_file, reusefile => 1);
DBMS_DATAPUMP.ADD_FILE( handle => hdnl, filename => 'rules_manager_${DATABASE}_${DATESTAMP}.log', directory => 'DATA_PUMP_DIR', filetype => dbms_datapump.ku\$_file_type_log_file, reusefile => 1);
DBMS_DATAPUMP.METADATA_FILTER(hdnl,'SCHEMA_EXPR','IN (''RULES_MANAGER'')');
DBMS_DATAPUMP.START_JOB(hdnl);
END;
/
" >export.sql

# perform export
sqlplus $MASTER/"$MASTER_PASSWORD"@$HOST:$PORT/$SID <<EOF >export.log
WHENEVER SQLERROR EXIT SQL.SQLCODE;
@cleanup.sql
@export.sql
EOF

PASSWORD_STATUS=$(cat export.log | grep ORA-01017 | wc -l)
if [ $PASSWORD_STATUS -gt 0 ]; then
    echo Incorrect master-password for $DATABASE. Exiting script now.
    send_vasrd_report "ERROR incorrect $DATABASE master-password"
    exit 1
fi

# send completion e-mail
send_vasrd_report "$DATABASE COMPLETE $FILENAME"
