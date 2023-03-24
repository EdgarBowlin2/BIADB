## variables

GRID_HOME=/u01/app/oracle/product/19.0.0/grid
ORACLE_HOME=/u01/app/oracle/product/19.0.0/db
GRID_STAGE=/dbshare/software/19.0.0   # Location of LINUX.X64_193000_grid_home.zip
ORACLE_STAGE=/dbshare/software/19.0.0 # Location of LINUX.X64_193000_db_home.zip
PATCH_STAGE=/dbshare/software/19.0.0  # Location of p########_190000_Linux-x86.64.zip files

# oracle 19.13
PSU_combo=33248471
PSU_grid=33182768
PSU_db=33192793
PSU_java=33192694

## grid infrastructure

mkdir -p $GRID_HOME

unzip $GRID_STAGE/LINUX.X64_193000_grid_home.zip -d $GRID_HOME

CHANGEARRAY=(
    INVENTORY_LOCATION=/u01/app/oraInventory
    oracle.install.option=CRS_SWONLY
    ORACLE_BASE=/u01/app/oracle
    ORACLE_HOME=$GRID_HOME
    oracle.install.asm.OSDBA=dba
    oracle.install.asm.OSOPER=dba
    oracle.install.asm.OSASM=dba
)

GRID_RSP=$GRID_HOME/inventory/response/grid_install.rsp

for C in "${CHANGEARRAY[@]}"; do
    O=$(echo $C | cut -d '=' -f1)=
    U=$(echo $C | sed 's/\//\\\//g')
    if (! grep -q "^$U" $GRID_RSP); then
        sed -i "s/$O/$U/g" $GRID_RSP
    fi
done

if [[ ! -d $PATCH_STAGE/$(echo ${PSU_combo} | cut -d "/" -f1) ]]; then
    unzip -o $PATCH_STAGE/p$(echo ${PSU_combo} | cut -d "/" -f1)_190000_Linux-x86-64.zip -d $PATCH_STAGE
fi

mv $GRID_HOME/OPatch $GRID_HOME/OPatch_$(date '+%Y%m%d')
unzip -o $PATCH_STAGE/p6880880_190000_Linux-x86-64.zip -d $GRID_HOME

$GRID_HOME/gridSetup.sh -silent -applyRU $PATCH_STAGE/$PSU_combo/$PSU_grid -responseFile $GRID_RSP

## database

mkdir -p $ORACLE_HOME

unzip $ORACLE_STAGE/LINUX.X64_193000_db_home.zip -d $ORACLE_HOME

# required for RHEL8 installation
sed -i 's/#CV_ASSUME_DISTID=OEL5/CV_ASSUME_DISTID=OL7/g' $ORACLE_HOME/cv/admin/cvu_config

CHANGEARRAY=(
    oracle.install.option=INSTALL_DB_SWONLY
    UNIX_GROUP_NAME=oinstall
    INVENTORY_LOCATION=/u01/app/oraInventory
    ORACLE_HOME=$ORACLE_HOME
    ORACLE_BASE=/u01/app/oracle
    oracle.install.db.InstallEdition=EE
    oracle.install.db.OSDBA_GROUP=dba
    oracle.install.db.OSOPER_GROUP=dba
    oracle.install.db.OSBACKUPDBA_GROUP=dba
    oracle.install.db.OSDGDBA_GROUP=dba
    oracle.install.db.OSKMDBA_GROUP=dba
    oracle.install.db.OSRACDBA_GROUP=dba
)

DB_RSP=$ORACLE_HOME/install/response/db_install.rsp

for C in "${CHANGEARRAY[@]}"; do
    O=$(echo $C | cut -d '=' -f1)=
    U=$(echo $C | sed 's/\//\\\//g')
    if (! grep -q "^$U" $DB_RSP); then
        sed -i "s/$O/$U/g" $DB_RSP
    fi
done

$ORACLE_HOME/runInstaller -silent -responseFile $DB_RSP

## patching

mv $ORACLE_HOME/OPatch $ORACLE_HOME/OPatch_$(date '+%Y%m%d')
unzip -o $PATCH_STAGE/p6880880_190000_Linux-x86-64.zip -d $ORACLE_HOME

export PATH=$ORACLE_HOME/OPatch:$PATH
cd $PATCH_STAGE/$PSU_combo/$PSU_grid/$PSU_db
opatch apply -silent
cd $PATCH_STAGE/$PSU_combo/$PSU_java
opatch apply -silent
