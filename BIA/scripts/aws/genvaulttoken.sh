#!/bin/bash
#---------------------------------------------------------------------------------------------
#-  New Vault Token To AWS (SecretsManager)  v1.1                                            -
#---------------------------------------------------------------------------------------------
#-  Edgar Bowlin                                                                 02-01-2023  -
#---------------------------------------------------------------------------------------------
#-  PURPOSE
#---------------------------------------------------------------------------------------------
#-  This script sets the vault environment variables to use vault command line commands to
#-  generate a new vault token. Using vault command line commands, the new vault token is
#-  stored in the vault path, overwriting the current vault token.  AWS secretsmanager
#-  command line commands are then used to update the vault token value in the specified
#-  secret-ID secret in AWS secretsmanager.
#---------------------------------------------------------------------------------------------
#-  REVISION HISTORY
#---------------------------------------------------------------------------------------------
#-  EBowlin 02-01-2023  V 1.0  Original version tested and delivered to Team Lead for review,
#-                      revisions, if any, and approval.
#-  PLynn   02-02-2023  V1.1   Patrick, Edgar, and team debugged and corrected vault and AWS
#-                             command line commands, finding the simplest, most direct
#-                             method to create new vault token and store in Vault and AWS.
#---------------------------------------------------------------------------------------------
#-  INPUT
#---------------------------------------------------------------------------------------------
#-  NONE
#---------------------------------------------------------------------------------------------
#-  OUTPUT
#---------------------------------------------------------------------------------------------
#-  A new generated Vault token will be used to replace the current Vault token as well as
#-  the token value in current AWS Secretsmanager secret.  The AWS secret with the new Vault
#-  token is then used to update the AWS secret in Secretsmanager.
#---------------------------------------------------------------------------------------------

#- Set all environment variables - BASH, Oracle, AWS
. /home/oracle/scripts/bia-devel/BIA/env
#- Set Vault environment variables for Vault command line execution
set_vault_environment

#--------------------------------------------------------------------
#- Get new policy based token from Vault.
#- Extract new token from policy and replace existing token value at
#- secret/platform/bia-dbas/vault (Vault revision is incremented).
#--------------------------------------------------------------------
NEW_VAULT_POLICY=$(vault token create -policy=bia-dbas-readwrite)
NEW_VAULT_TOKEN=`echo $NEW_VAULT_POLICY | awk '{print $6}'`

vault kv put secret/platform/bia-dbas/vault token=$NEW_VAULT_TOKEN

#--------------------------------------------------------------------
#- Update aws secretsmanager secret-id with new vault token.
#--------------------------------------------------------------------
aws secretsmanager update-secret --secret-id bia-dbas-vault --secret-string ''"$NEW_VAULT_TOKEN"''



