#!/bin/bash
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/env

ORACLE_BASE=/u01/app/oracle
ORACLE_HOME=/u01/app/oracle/product/19.0.0/db
STAGE=$HOME

read -p "database FQDN: " FQDN
read -p "MEMORY (in MB): " MEMORY

SID=$(echo $FQDN | cut -d '.' -f1 | tr '[:upper:]' '[:lower:]')
DOMAIN=$(echo $FQDN | cut -d '.' -f2- | tr '[:upper:]' '[:lower:]')
PASSWORD="$(generate_password)"
echo 'Power User (SYS/SYSTEM/DBSNMP) Password: '$PASSWORD

#  database

PATH=$ORACLE_HOME/bin:$PATH

CHANGEARRAY=(
    gdbName=$SID.$DOMAIN
    sid=$SID
    databaseConfigType=SI
    templateName=General_Purpose.dbc
    sysPassword=$PASSWORD
    systemPassword=$PASSWORD
    dbsnmpPassword=$PASSWORD
    datafileDestination=/u01/app/oracle/oradata
    recoveryAreaDestination=/u01/app/oracle/oradata
    storageType=FS
    characterSet=AL32UTF8
    totalMemory=$MEMORY
)

cp $ORACLE_HOME/assistants/dbca/dbca.rsp $STAGE
DB_RSP=$STAGE/dbca.rsp

for C in "${CHANGEARRAY[@]}"; do
    O=$(echo $C | cut -d '=' -f1)=
    U=$(echo $C | sed 's/\//\\\//g')
    if (! grep -q "^$U" $DB_RSP); then
        sed -i "s/$O/$U/g" $DB_RSP
    fi
done

$ORACLE_HOME/bin/dbca -createDatabase -silent -responseFile $DB_RSP

rm $DB_RSP
