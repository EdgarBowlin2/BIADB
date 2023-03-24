#!/bin/bash
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/env

# parse command line
usage() {
    echo "usage: $0"
    echo "    [ -d DB-INSTANCE-IDENTIFIER ]"
    echo "    [ -a allocated-storage ( 100 - 65536 ) ]"
    echo "    [ -c instance-class ]"
    echo "    [ -e engine-version ]"
    echo "    [ -i iops ( 1000 - 256000 ) ] -- This option sets the StorageType to 'io1'"
    echo "    [ -o option-group ]"
    echo "    [ -p parameter-group ]"
    exit 1
}

while getopts ":d:a:c:e:i:o:p:" options; do
    case "${options}" in
        a)
            ALLOCATEDSTORAGE="${OPTARG}"

            if ! [[ $ALLOCATEDSTORAGE =~ ^[0-9]+$ ]]; then
                echo "ERROR: -a allocated-storage must be an number value"
                usage
            fi

            if [ $ALLOCATEDSTORAGE -lt 100 ] || [ $ALLOCATEDSTORAGE -gt 65536 ]; then
                echo "ERROR: -a allocated-storage must be between 100 and 65536"
                usage
            fi
            ;;
        c)
            INSTANCECLASS="${OPTARG}"
            ;;
        d)
            DATABASE=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
            ;;
        e)
            ENGINEVERSION="${OPTARG}"
            VALIDENGINEVERSION=($(aws rds describe-db-engine-versions --engine oracle-ee --engine-version $ENGINEVERSION | jq -r '.DBEngineVersions[].EngineVersion'))

            if ! [ "$ENGINEVERSION" = "$VALIDENGINEVERSION" ]; then
                echo ""
                echo "ERROR: -e engine-version must be a valid version"
                echo ""
                exit 1
            fi
            ;;
        i)
            IOPS="${OPTARG}"

            if ! [[ $IOPS =~ ^[0-9]+$ ]]; then
                echo "ERROR: -i iops must be an number value"
                usage
            fi

            if [ $IOPS -lt 1000 ] || [ $IOPS -gt 256000 ]; then
                echo "ERROR: -i iops must be between 1000 and 256000"
                usage
            fi

            IO1STORAGE=1
            ;;
        o)
            OPTIONGROUP="${OPTARG}"
            VALIDOPTIONGROUPS=($(aws rds describe-option-groups | jq -r '.OptionGroupsList[] | select( .EngineName == "oracle-ee" ) | select( .MajorEngineVersion == "19" ) | .OptionGroupName' | sort))

            if ! [[ " ${VALIDOPTIONGROUPS[*]} " =~ " $OPTIONGROUP " ]]; then
                echo ""
                echo "ERROR: -o option-group must be an existing group"
                echo "${VALIDOPTIONGROUPS[*]}" | tr " " "\n"
                echo ""
                exit 1
            fi
            ;;
        p)
            PARAMETERGROUP="${OPTARG}"
            VALIDPARAMGROUPS=($(aws rds describe-db-parameter-groups | jq -r '.DBParameterGroups[] | select( .DBParameterGroupFamily == "oracle-ee-19" ) | .DBParameterGroupName' | sort))

            if ! [[ " ${VALIDPARAMGROUPS[*]} " =~ " $PARAMETERGROUP " ]]; then
                echo ""
                echo "ERROR: -p parameter-group must be an existing group"
                echo "${VALIDPARAMGROUPS[*]}" | tr " " "\n"
                echo ""
                exit 1
            fi
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

# VERIFY db-instance-identifier
TENANT=${DATABASE%-*}
ENVIRONMENT=${DATABASE##*-}

VALIDENVIRONMENTS=(
    cola
    demo
    dev
    int
    ivv
    pat
    pdt
    perf
    preprod
    prod
    prodtest
    test
    uat
)

if ! [[ " ${VALIDENVIRONMENTS[*]} " =~ " $ENVIRONMENT " ]]; then
    echo ""
    echo "ERROR: db-instance-identifier must end with one of the following:"
    echo "${VALIDENVIRONMENTS[*]}"
    echo ""
    exit 1
fi

# SET GLOBAL, VPC, and ENVIRONMENT PARAMETERS

# set engine version as highest version where 'DBAenv' tag = $ENVIRONMENT
if [[ -z "$ENGINEVERSION" ]]; then
    ENGINEVERSION=$(aws rds describe-db-instances | jq -r --arg ENVIRONMENT "$ENVIRONMENT" '.[] | .[] | select( .engine = "oracle-ee" ) | select( .TagList[] | select(.Key=="DBAenv") | select(.Value==$ENVIRONMENT)) | .EngineVersion' | sort -r | uniq | head -n 1)
fi

# GLOBAL DEFAULTS
DATABASEPARAMETERS=(
    AllocatedStorage,100
    AutoMinorVersionUpgrade,false
    CharacterSetName,AL32UTF8
    CopyTagsToSnapshot,true
    DBName,ORCL
    EngineVersion,$ENGINEVERSION
    Engine,oracle-ee
    LicenseModel,bring-your-own-license
    MasterUsername,dbadmin
    Port,1521
    PreferredBackupWindow,05:00-06:00
    PreferredMaintenanceWindow,sat:06:00-sat:07:00
    PubliclyAccessible,false
    StorageEncrypted,true
)

DATABASETAGS=(
    ApplicationID,$TENANT
    DBAenv,$ENVIRONMENT
    Portfolio,BAM
    Product,VBMS
    ProductLine,CandP
    Tenant,$TENANT
)

# VPC DEFAULTS
case $AWSACCOUNT in
    D)
        VPCPARAMETERS=(
            BackupRetentionPeriod,14
            DBParameterGroupName,default.oracle-ee-19
            DBSubnetGroupName,db-subnet-dev-gp-rds
            OptionGroupName,platform-oracle19-v3
        )
        VPCCLOUDWATCH=(
            alert
            listener
        )
        VPCSECURITYGROUPS=(
            sg-11a82977
            sg-09a3ed9edc43a1697
        )
        ;;
    S)
        VPCPARAMETERS=(
            BackupRetentionPeriod,14
            DBParameterGroupName,default.oracle-ee-19
            DBSubnetGroupName,db-subnet-stage-gp-rds
            OptionGroupName,platform-oracle19-v3
        )
        VPCCLOUDWATCH=(
            alert
            listener
        )
        VPCSECURITYGROUPS=(
            sg-1eb6c078
            sg-0e7dceaff93d0a846
        )
        ;;
    P)
        VPCPARAMETERS=(
            BackupRetentionPeriod,30
            DBParameterGroupName,bip-dba-oracle-ee-19
            DBSubnetGroupName,db-subnet-prod-gp-app-prod-a
            OptionGroupName,bip-dba-oracle-ee-19-pa-rpt
        )
        VPCCLOUDWATCH=(
            alert
            listener
        )
        VPCSECURITYGROUPS=(
            sg-04fa0c62
            sg-00ae03949eb7c2775
            sg-092df0017b65803cc
        )
        ;;
    *)
        echo "ERROR: VPC could not be determined.  Exiting."
        exit 1
        ;;
esac

# add VPC DEFAULTS to final parameter list
for KEYVALUE in "${VPCPARAMETERS[@]}"; do
    DATABASEPARAMETERS+=($KEYVALUE)
done

# ENVIRONMENT DEFAULTS
case $ENVIRONMENT in
    cola)
        ENVIRONMENTPARAMETERS=(
            DBInstanceClass,db.t3.medium
            DeletionProtection,true
            MultiAZ,false
        )
        ;;
    demo)
        ENVIRONMENTPARAMETERS=(
            DBInstanceClass,db.m5.large
            DeletionProtection,true
            MultiAZ,false
        )
        ;;
    dev)
        ENVIRONMENTPARAMETERS=(
            DBInstanceClass,db.t3.medium
            DeletionProtection,true
            MultiAZ,false
        )
        ;;
    int)
        ENVIRONMENTPARAMETERS=(
            DBInstanceClass,db.t3.medium
            DeletionProtection,true
            MultiAZ,false
        )
        ;;
    ivv)
        ENVIRONMENTPARAMETERS=(
            DBInstanceClass,db.m5.large
            DeletionProtection,true
            MultiAZ,false
        )
        ;;
    pat)
        ENVIRONMENTPARAMETERS=(
            DBInstanceClass,db.t3.medium
            DeletionProtection,true
            MultiAZ,false
        )
        ;;
    pdt)
        ENVIRONMENTPARAMETERS=(
            DBInstanceClass,db.t3.medium
            DeletionProtection,true
            MultiAZ,false
        )
        ;;
    perf)
        ENVIRONMENTPARAMETERS=(
            DBInstanceClass,db.m5.2xlarge
            DeletionProtection,true
            MultiAZ,false
        )
        ;;
    preprod)
        ENVIRONMENTPARAMETERS=(
            DBInstanceClass,db.m5.large
            DeletionProtection,true
            MultiAZ,false
        )
        ;;
    prod)
        ENVIRONMENTPARAMETERS=(
            DBInstanceClass,db.m5.2xlarge
            DeletionProtection,true
            MultiAZ,true
        )
        ;;
    prodtest)
        ENVIRONMENTPARAMETERS=(
            DBInstanceClass,db.m5.xlarge
            DeletionProtection,false
            MultiAZ,false
        )
        ;;
    test)
        ENVIRONMENTPARAMETERS=(
            DBInstanceClass,db.t3.medium
            DeletionProtection,true
            MultiAZ,false
        )
        ;;
    uat)
        ENVIRONMENTPARAMETERS=(
            DBInstanceClass,db.m5.xlarge
            DeletionProtection,true
            MultiAZ,false
        )
        ;;
    *)
        echo "The environment chosen does not have a defined set of default values.  Exiting."
        exit 1
        ;;
esac

# add ENVIRONMENT DEFAULTS to final parameter list
for KEYVALUE in "${ENVIRONMENTPARAMETERS[@]}"; do
    DATABASEPARAMETERS+=($KEYVALUE)
done

# add USER PARAMETERS to final parameter list
# -d
DATABASEPARAMETERS+=(DBInstanceIdentifier,$DATABASE)

# -a
if ! [[ -z "$ALLOCATEDSTORAGE" ]]; then
    DATABASEPARAMETERS+=(AllocatedStorage,$ALLOCATEDSTORAGE)
fi

# -c
if ! [[ -z "$INSTANCECLASS" ]]; then
    VALIDINSTANCECLASSES=($(aws rds describe-orderable-db-instance-options --engine oracle-ee --engine-version $ENGINEVERSION | jq -r '.OrderableDBInstanceOptions[] | .DBInstanceClass' | uniq))

    if ! [[ " ${VALIDINSTANCECLASSES[*]} " =~ " $INSTANCECLASS " ]]; then
        echo ""
        echo "ERROR: -c instance-class must be a valid option for $ENGINEVERSION"
        echo "${VALIDINSTANCECLASSES[*]}" | tr " " "\n"
        echo ""
        exit 1
    else
        DATABASEPARAMETERS+=(DBInstanceClass,$INSTANCECLASS)
    fi
fi

# -i
if [[ $IO1STORAGE -eq 1 ]]; then
    DATABASEPARAMETERS+=(StorageType,io1)
    DATABASEPARAMETERS+=(Iops,$IOPS)
else
    DATABASEPARAMETERS+=(StorageType,gp2)
fi

# -o
if ! [[ -z "$OPTIONGROUP" ]]; then
    DATABASEPARAMETERS+=(OptionGroupName,$OPTIONGROUP)
fi

# -p
if ! [[ -z "$PARAMETERGROUP" ]]; then
    DATABASEPARAMETERS+=(DBParameterGroupName,$PARAMETERGROUP)
fi

# MasterUserPassword
PASSWORD="$(generate_password)"
DATABASEPARAMETERS+=(MasterUserPassword,$PASSWORD)

# GENERATE JSON SKELETON
while true; do

    JSON=$(aws rds create-db-instance --generate-cli-skeleton | jq --sort-keys .)
    if [[ $? -eq 0 ]]; then
        break
    fi

    "WARN: aws rds create-db-instance failed to generate a JSON skeleton.  Retrying..."

done

# update JSON WITH DESIRED PARAMETERS
# remove unwanted parameters

KEYBLACKLIST=(
    AvailabilityZone
    BackupTarget
    CustomIamInstanceProfile
    DBClusterIdentifier
    DBSecurityGroups
    Domain
    DomainIAMRoleName
    EnableCustomerOwnedIp
    EnableIAMDatabaseAuthentication
    EnablePerformanceInsights
    KmsKeyId
    MaxAllocatedStorage
    MonitoringInterval
    MonitoringRoleArn
    NcharCharacterSetName
    PerformanceInsightsKMSKeyId
    PerformanceInsightsRetentionPeriod
    ProcessorFeatures
    PromotionTier
    TdeCredentialArn
    TdeCredentialPassword
    Timezone
)

if [[ $IO1STORAGE -ne 1 ]]; then
    KEYBLACKLIST+=(Iops)
fi

for key in "${KEYBLACKLIST[@]}"; do
    JSON=$(echo $JSON | jq --arg KEY "$key" 'del(.[$KEY])')
done

# update JSON with DATABASEPARAMETERS
DATATYPES=($(echo $JSON | jq -r 'to_entries[] | "\(.key),\(.value|type)"'))

for KEYVALUE in "${DATABASEPARAMETERS[@]}"; do

    KEY=$(echo $KEYVALUE | cut -d"," -f1)
    VALUE=$(echo $KEYVALUE | cut -d"," -f2)

    for TYPELOOKUP in "${DATATYPES[@]}"; do
        if [[ "$TYPELOOKUP" =~ .*"$KEY".* ]]; then
            TYPE=$(echo $TYPELOOKUP | cut -d"," -f2)
        fi
    done

    if [ "$TYPE" = "number" ] || [ "$TYPE" = "boolean" ]; then
        JSON=$(echo $JSON | jq --arg KEY "$KEY" --argjson VALUE "$VALUE" '.[$KEY]=$VALUE')
    elif [ "$TYPE" = "string" ]; then
        JSON=$(echo $JSON | jq --arg KEY "$KEY" --arg VALUE "$VALUE" '.[$KEY]=$VALUE')
    else
        echo "ERROR: key $KEY has an unknown JSON data type"
        exit 1
    fi

done

# update JSON with VPCSECURITYGROUPS
JSON=$(echo $JSON | jq '.VpcSecurityGroupIds = []')
for VALUE in "${VPCSECURITYGROUPS[@]}"; do
    JSON=$(echo $JSON | jq --arg VALUE "$VALUE" '.VpcSecurityGroupIds += [$VALUE]')
done

# update JSON with VPCTAGS
JSON=$(echo $JSON | jq '.Tags = []')
for KEYVALUE in "${DATABASETAGS[@]}"; do
    KEY=$(echo $KEYVALUE | cut -d"," -f1)
    VALUE=$(echo $KEYVALUE | cut -d"," -f2)

    JSON=$(echo $JSON | jq --arg KEY "$KEY" --arg VALUE "$VALUE" '.Tags += [{"Key":$KEY,"Value":$VALUE}]')
done

# update JSON with VPCCLOUDWATCH
JSON=$(echo $JSON | jq '.EnableCloudwatchLogsExports = []')
for VALUE in "${VPCCLOUDWATCH[@]}"; do
    JSON=$(echo $JSON | jq --arg VALUE "$VALUE" '.EnableCloudwatchLogsExports += [$VALUE]')
done

echo $JSON | jq 'del(.MasterUserPassword, .Tags)'

echo ''
while true; do
    read -p "Create the database $DATABASE with this configuration? (y/n) " yn
    case $yn in
        [Yy]*)
            echo "Creating database..."
            break
            ;;
        [Nn]*)
            echo "Exiting..."
            exit
            ;;
        *) echo "Invalid response." ;;
    esac
done

aws rds create-db-instance --cli-input-json "$JSON"
