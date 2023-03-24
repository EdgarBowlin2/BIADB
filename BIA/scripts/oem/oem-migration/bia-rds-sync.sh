#!/bin/bash
# set environment
GITROOT=$( git rev-parse --show-toplevel )
. $GITROOT/BIA/env
. $GITROOT/env
set_vault_environment
DBARRAY=($(generate_database_list BIA))
for DATABASE in "${DBARRAY[@]}"; do
echo $DATABASE
done
#Login to oem
#Get sysman password from correct vault location
if [[ "$AWSACCOUNT" == "P" ]]; then
SYSMAN_PASSWORD=$(vault kv get -field=sysman secret/platform/bia-dbas/oem)
elif [[ "$AWSACCOUNT" == "S" ]]; then
SYSMAN_PASSWORD=$(vault kv get -field=sysman secret/platform/bia-dbas/oem)
elif [[ "$AWSACCOUNT" == "D" ]]; then
SYSMAN_PASSWORD=$(vault kv get -field=sysman secret/platform/bia-dbas/oem)
else echo "Not a AWS known account"
fi


echo EMCLI home is $EMCLI_HOME
$EMCLI_HOME/emcli login -username=sysman -password=$SYSMAN_PASSWORD >/dev/null 2>&1
$EMCLI_HOME/emcli sync >/dev/null 2>&1
for DATABASE in "${DBARRAY[@]}"; do

    RDSINFO=$(get_database_metadata "$DATABASE")

    if [[ $? -ne 0 ]]; then
        echo "aws rds describe-db-instances failed for $DATABASE"
        break
    fi

    HOST=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Address)
    PORT=$(echo $RDSINFO | jq -r .DBInstances[].Endpoint.Port)
    SID=$(echo $RDSINFO | jq -r .DBInstances[].DBName)
    DBSNMP_PASSWORD=$(vault kv get -field=DBSNMP secret/platform/bia-dbas/$DATABASE)
        if [[ $? -ne 0 ]]; then
        echo "Failed to find vault credentials"
                continue
    fi
echo $EMCLI_HOME/emcli add_target \
     -name="${DATABASE}" \
     -type="oracle_database" \
     -host="${HOST}" \
     -credentials="UserName:DBSNMP;password:${DBSNMP_PASSWORD};Role:Normal" \
     -properties="SID:"${SID}";Port:"${PORT}";OracleHome:/oracle;MachineName:${HOST}"

$EMCLI_HOME/emcli add_target \
     -name="${DATABASE}" \
     -type="oracle_database" \
     -host="${HOST}" \
     -credentials="UserName:DBSNMP;password:${DBSNMP_PASSWORD};Role:Normal" \
     -properties="SID:"${SID}";Port:"${PORT}";OracleHome:/oracle;MachineName:${HOST}"
done
