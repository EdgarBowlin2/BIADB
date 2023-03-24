#!/bin/bash
# set environment
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/VBMS/local/env

# begin
TEAM="CandP"
DBARRAY=($(generate_database_list "$TEAM"))
if [ "${#DBARRAY[@]}" -eq 0 ]; then
    echo "ERROR: -t ${TEAM} returned with zero objects."
    exit 1
fi

set_vault_environment

SYSMAN_PASSWORD=$(vault kv get -field=sysman secret/platform/candp-dbas/oem)

$EMCLI_HOME/emcli logout >/dev/null 2>&1
$EMCLI_HOME/emcli login -username=sysman -password=$SYSMAN_PASSWORD >/dev/null 2>&1
$EMCLI_HOME/emcli sync >/dev/null 2>&1

EMCLILIST=$($EMCLI_HOME/emcli get_targets -noheader -format="name:csv" -targets="oracle_database")
OEMLIST=$(for db in ${EMCLILIST[@]}; do echo $db | cut -d, -f4; done)

MISSINGLIST=$(comm --check-order -23 <(printf '%s\n' "${DBARRAY[@]}" | sort) <(printf '%s\n' "${OEMLIST[@]}" | sort))

echo "The following RDS instances are not being monitored in OEM:"
echo "${MISSINGLIST[@]}"
