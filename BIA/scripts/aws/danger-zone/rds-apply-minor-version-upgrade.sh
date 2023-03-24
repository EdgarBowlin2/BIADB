#!/bin/bash
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/env

# parse command line
usage() {
    echo "usage: $0 [ -t SYSTEM-TEAM-TAG ] [ -e ENVIRONMENT ]" 1>&2
    exit 1
}

while getopts ":t:e:" options; do
    case "${options}" in
        t)
            TEAM=${OPTARG}
            ;;
        e)
            ENVIRONMENT=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
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

if [[ -z "$TEAM" ]]; then
    echo "ERROR: -t is a mandatory parameter."
    usage
fi

if [[ -z "$ENVIRONMENT" ]]; then
    echo "ERROR: -e is a mandatory parameter."
    usage
fi

# get metadata for all databases
RDSINFO=$(aws rds describe-db-instances)

# get metadata of team databases in environment
DATABASELIST=$(echo $RDSINFO | jq --arg ENVIRONMENT "$ENVIRONMENT" --arg TEAM "$TEAM" '.[] | .[] | select( .engine = "oracle-ee" ) | select ( .EngineVersion | startswith("19")) | select( .TagList[] | select(.Key=="ProductLine") | select(.Value==$TEAM)) | select( .TagList[] | select(.Key=="DBAenv") | select(.Value==$ENVIRONMENT))')

# exit if -t or -e contained invalid arguments
DATABASELISTCHECK=$(echo $DATABASELIST | jq '. | length' | wc -l)
if [[ $DATABASELISTCHECK -lt 1 ]]; then
    echo "ERROR: -t $TEAM -e $ENVIRONMENT returned with zero databases."
    exit 1
fi

# get engine info metadata
ENGINEINFO=$(aws rds describe-db-engine-versions --engine oracle-ee)

# get latest deployed minor version of team databases in environment
CURRENTVERSION=$(echo $DATABASELIST | jq -r '.EngineVersion' | sort -r | uniq | head -n 1)

# get a list of the valid upgrade paths for the latest deployed minor version
VALIDENGINES=($CURRENTVERSION)
VALIDENGINES+=($(echo $ENGINEINFO | jq -r --arg ENGINE "$CURRENTVERSION" '.DBEngineVersions[] | select ( .EngineVersion==$ENGINE ) | .ValidUpgradeTarget[].EngineVersion' | sort))

# set target version to CURRENTVERSION if it is the latest available, or let user pick target version equal or newer than CURRENTVERSION
echo ""
if [[ ${#VALIDENGINES[@]} -eq 1 ]]; then
    NEWENGINE=${VALIDENGINES[0]}
    echo "Only a single target engine version, $NEWENGINE, exists for environment $ENVIRONMENT."
else
    echo "Select the target engine version:"
    select NEWENGINE in "${VALIDENGINES[@]}"; do
        [[ -n $NEWENGINE ]] || {
            echo "Invalid response." >&2
            continue
        }
        break
    done
fi

# get list of minor versions that may be upgraded to NEWENGINE
UPGRADEABLEVERSIONS=($(echo $ENGINEINFO | jq -r --arg NEWENGINE "$NEWENGINE" '.DBEngineVersions[] | select ( .EngineVersion | startswith("19")) | select ( .ValidUpgradeTarget[].EngineVersion | contains($NEWENGINE)) | .EngineVersion'))

# find databases on version where NEWENGINE is a valid upgrade target
for VERSION in "${UPGRADEABLEVERSIONS[@]}"; do
    UPGRADELIST+=($(echo $DATABASELIST | jq -r --arg VERSION "$VERSION" 'select ( .EngineVersion==$VERSION ) | .DBInstanceIdentifier'))
done

if [[ "${#UPGRADELIST[*]}" -eq 0 ]]; then
    echo ""
    echo "All databases in environment $ENVIRONMENT are deployed with engine version $NEWENGINE."
    exit 1
fi

echo ""
echo "The following databases will upgrade to engine version $NEWENGINE:"
echo "${UPGRADELIST[*]}" | tr " " "\n"

echo ""
while true; do
    read -p "All instances will be unavilable during the upgrade.  Apply these upgrades now? (y/n) " yn
    case $yn in
        [Yy]*)
            echo "Applying upgrades..."
            break
            ;;
        [Nn]*)
            echo "Exiting without changes..."
            exit
            ;;
        *) echo "Invalid response." ;;
    esac
done

for db in "${UPGRADELIST[@]}"; do
    aws rds modify-db-instance --db-instance-identifier $db --engine-version $NEWENGINE --apply-immediately
done
