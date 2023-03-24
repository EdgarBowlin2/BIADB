#!/bin/bash

blue=$(tput setaf 4)
yellow=$(tput setaf 3)
green=$(tput setaf 2)
red=$(tput setaf 1)
reset=$(tput sgr0)

#--------------------------------------
#- Include global functions library
#--------------------------------------
. $SCRIPT_DIR/functions/functions.sh

function note(){
    printf "${green}$@${reset}\n"
}

# PATH TO STORE CONNECTOR CONFIGS FOR BACKUP
CONNECTOR_STASH=~/Code/connectors

echo
echo "Select your cluster:"
list="alt8 dev8 stage8 prod8"
# IFS=$'\n'
select s_cluster in $list 
   do CLUSTER=$s_cluster && break;
done

KAFKA_CMD="--bootstrap-server kafka.confluentv2.svc.${CLUSTER}:9071 --command-config /mnt/secrets/admin-props/admin_props"
CONNECT_URL=https://connect.connectv2.${CLUSTER}.bip.va.gov
SR_URL=https://schemaregistry.schemaregistryv2.${CLUSTER}.bip.va.gov

echo
echo "Select your connector:"
list=$(curl -sk ${CONNECT_URL}/connectors | jq -r .[] | sort)
# IFS=$'\n'
select s_connector in $list 
   do CONNECTOR=$s_connector && break;
done

printf "\n${yellow}"
cat <<EOT
########## SETUP ##########
Using cluster: $CLUSTER
Connect URL: $CONNECT_URL
SchemaRegistry URL: $SR_URL

Target Connector: ${CONNECTOR}
###########################
EOT
printf "${reset}\n"

# Pull the connector config, drop the name
note "Pulling current config for ${CONNECTOR}..."
cd $CONNECTOR_STASH && { curl -sk -o connect-${CONNECTOR}.json ${CONNECT_URL}/connectors/${CONNECTOR}; cd -; }
CONNECTOR_CONFIG=$(curl -sk ${CONNECT_URL}/connectors/${CONNECTOR} | jq '.config | del(.name)')
TOPIC_REGEX="^$(curl -sk ${CONNECT_URL}/connectors/${CONNECTOR} | jq -r '.config."table.topic.name.template"' | cut -d'$' -f1).*"
REDO_LOG_TOPIC_NAME=$(curl -sk ${CONNECT_URL}/connectors/${CONNECTOR} | jq -r '.config."redo.log.topic.name"')

# Delete the connector
echo "Would you like to delete the running connector? (Continue will move forward without deletion)"
select yn in "Yes" "No" "Continue"; do
    case $yn in
        Yes ) note "Deleting the current config for ${CONNECTOR}..."; curl -XDELETE -sk ${CONNECT_URL}/connectors/${CONNECTOR}; break;;
        No ) note "Skipping connector deletion and quitting."; exit;;
        Continue ) note "Moving on without deletion..."; break;;
    esac
done


echo "These are the following TOPICS identified for deletion with the \"${TOPIC_REGEX}\" regex:"
kubectl exec -it -n confluentv2 kafka-0 -- bash -c "kafka-topics $KAFKA_CMD --list --topic \"${TOPIC_REGEX}\"";
echo

echo "These are the following SCHEMAS identified for deletion with the \"${TOPIC_REGEX}\" regex:"
curl -sk "${SR_URL}/subjects" | jq -r ".[] | select(test(\"${TOPIC_REGEX}\"))"
echo


echo "Would you like to delete the connector topics and schemas (using regex: \"${TOPIC_REGEX}\")? (Continue will move forward without deletion)"
select yn in "Yes" "No" "Continue"; do
    case $yn in
        Yes ) \
         note "Deleting the topics associated with the connector..."; \
         kubectl exec -it -n confluentv2 kafka-0 -- bash -c "kafka-topics $KAFKA_CMD --delete --topic \"${TOPIC_REGEX}\""; \
         kubectl exec -it -n confluentv2 kafka-0 -- bash -c "kafka-topics $KAFKA_CMD --delete --topic \"${REDO_LOG_TOPIC_NAME}\""; \
         echo "Deleting the schemas associated with the connector topics..."; \
         SCHEMAS=$(curl -sk "${SR_URL}/subjects" | jq -r ".[] | select(test(\"${TOPIC_REGEX}\"))"); \
         for schema in $SCHEMAS; do curl -sk -XDELETE "${SR_URL}/subjects/${schema}"; done; echo; \
         break;;
        No ) note "Skipping deletion of topics and schemas and exiting."; exit;;
        Continue ) note "Moving on without deletion..."; break;;
    esac
done


echo "Would you like to create a new REDO log topic? (Continue will move forward without creation)"
select yn in "Yes" "No" "Continue"; do
    case $yn in
        Yes ) \
         note "Creating new topic for ${REDO_LOG_TOPIC_NAME}..."; \
         kubectl exec -it -n confluentv2 kafka-0 -- bash -c "kafka-topics $KAFKA_CMD --create --partitions=1 --topic \"${REDO_LOG_TOPIC_NAME}\" --replication-factor 3 --config cleanup.policy=delete --config retention.ms=604800000 --config min.insync.replicas=2"; \
         break;;
        No ) note "Skipping connector deletion and quitting."; exit;;
        Continue ) note "Moving on without creation..."; break;;
    esac
done

CONNECTOR_NO_TIMESTAMP=$(echo $CONNECTOR | cut -d'_' -f1)
NEW_TIMESTAMP=$(date "+%Y-%m-%d-%H%M%S")
NEW_CONNECTOR=$(printf ${CONNECTOR_NO_TIMESTAMP}_${NEW_TIMESTAMP})

echo "Should I use the following generated name for redeployment?: ${NEW_CONNECTOR}"
select yn in "Yes" "No" "Continue"; do
    case $yn in
        Yes ) \
         FINAL_CONNECTOR_NAME=${NEW_CONNECTOR}; \
         break;;
        No ) printf "Enter the connector name to use: "; read -r FINAL_CONNECTOR_NAME; \
         break;;
    esac
done


note "Getting ready to re-deploy connector as ${FINAL_CONNECTOR_NAME}..."
temp_connector=$(mktemp)
cat <<EOT > $temp_connector
{
    "name": "${FINAL_CONNECTOR_NAME}",
    "config": ${CONNECTOR_CONFIG}
}
EOT

cat <<EOT
${yellow}######## DEBUG INFO ########
Temp connector file: ${temp_connector}

Contents of new connector file:
$(cat ${temp_connector} | jq -r)
############################${reset}
EOT


echo "Ready to redeploy the connector?"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) \
         note "Deploying connector configuration..."; \
         curl -sk -XPOST -H "Content-Type: application/json" $CONNECT_URL/connectors -d @${temp_connector}; echo; \
         break;;
        No ) note "Skipping deployment and quitting."; exit;;
    esac
done


note "Done!"
