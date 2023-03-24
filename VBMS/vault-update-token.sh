# SET ENVIRONMENT
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/VBMS/local/env

set_vault_environment

VAULT_PASSWORD=$(aws secretsmanager get-secret-value --secret-id vbmsdba-vault | jq --raw-output '.SecretString' | jq -r .password)
NEW_VAULT_TOKEN=$(vault login -token-only -method=ldap username=vbmsdba password=$VAULT_PASSWORD)
NEW_SECRETS_JSON=$(aws secretsmanager get-secret-value --secret-id vbmsdba-vault | jq --raw-output '.SecretString' | jq --arg N "$NEW_VAULT_TOKEN" '.token=$N')

aws secretsmanager update-secret --secret-id vbmsdba-vault --secret-string ''"$NEW_SECRETS_JSON"''
