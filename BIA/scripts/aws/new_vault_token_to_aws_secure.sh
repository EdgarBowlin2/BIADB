#!/bin/bash
#---------------------------------------------------------------------------------------------
#-  New Vault Token To AWS (SecretsManager)  v1.1                                            -
#---------------------------------------------------------------------------------------------
#-  Edgar Bowlin                                                                 01-11-2023  -
#---------------------------------------------------------------------------------------------
#-  PURPOSE 
#---------------------------------------------------------------------------------------------
#-  This script sets the vault environment variables to use vault command line commands to   
#-  generate a new vault token.  AWS secretsmanager command line commands are then used to 
#-  update the vault token value in the specified key/value pair in the secret-ID secret in 
#-  AWS secretsmanager. 
#---------------------------------------------------------------------------------------------
#-  REVISION HISTORY 
#---------------------------------------------------------------------------------------------
#-  EBowlin 01-11-2023	V 1.0  Original version tested and delivered to Team Lead for review,  
#-                      revisions, if any, and approval.
#---------------------------------------------------------------------------------------------
#-  REMAINING WORK TO DO
#---------------------------------------------------------------------------------------------
#-  Create input arguments for username, password, secret-id and validate prior to execution.
#---------------------------------------------------------------------------------------------


#- Set all environment variables - BASH, Oracle, AWS
. /home/oracle/scripts/bia-devel/BIA/env
#- Set Vault environment variables for Vault command line execution
set_vault_environment

#--------------------------------------------------------------------
#- Get new token generated from Vault
#--------------------------------------------------------------------
NEW_VAULT_TOKEN=$(vault login -token-only -method=ldap username=ebowlin password="xxxxxxxxxxxxxxxxxx")

#--------------------------------------------------------------------
#- Substitute new token in existing secret-id secretstring
#--------------------------------------------------------------------
NEW_SECRETS_JSON=$(aws secretsmanager get-secret-value --secret-id project-bip-platform/shared-secrets | jq --raw-output '.SecretString' | jq --arg N "$NEW_VAULT_TOKEN" '.test_key=$N)

#--------------------------------------------------------------------
#- Update aws secretsmanager secret-id with updated secret-string
#--------------------------------------------------------------------
aws secretsmanager update-secret --secret-id project-bip-platform/shared-secrets --secret-string ''"$NEW_SECRETS_JSON"''

