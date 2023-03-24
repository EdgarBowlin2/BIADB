#!/bin/bash
#11/21/22 Initial Script Creation - PEL
blue=$(tput setaf 4)
yellow=$(tput setaf 3)
green=$(tput setaf 2)
red=$(tput setaf 1)
reset=$(tput sgr0)

#------------------------------------------
#- Include global functions library
#------------------------------------------
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
cd $CONNECTOR_STASH && { curl -sk -o connect-${CONNECTOR}.json ${CONNECT_URL}/connectors/${CONNECTOR}; }
echo Past the config pull
#Get number of table topics in config
NUM_CONFIG_TABLES=`cat connect-${CONNECTOR}.json | jq -r '.config."table.inclusion.regex"' | awk 'BEGIN  {FS = "]" }{print $2}' | awk 'BEGIN {FS = "|" }{print NF}'`

#Get expected topic names from connector config
EXPECTED_TOPICS=()
EXPECTED_TOPICS[0]=`cat connect-${CONNECTOR}.json | jq -r '.config."redo.log.topic.name"'`
for (( i=1 ; i<=$NUM_CONFIG_TABLES ; i++ )); 
do
EXPECTED_TOPICS[$i]=`cat connect-${CONNECTOR}.json | jq -r '.config."table.inclusion.regex"' | awk 'BEGIN  {FS = "]" }{print $2}' | awk -v var=$i 'BEGIN {FS = "|" }{print $var}'`
#echo ${EXPECTED_TOPICS[$i]}
done

#Remove leading ( from first topic
EXPECTED_TOPICS[1]=`echo ${EXPECTED_TOPICS[1]} | tr -d '('`
#Remove trailing ) from last topic 
EXPECTED_TOPICS[-1]=`echo ${EXPECTED_TOPICS[-1]} | tr -d ')'`

 
#CLUSTER=`cat connect-${CONNECTOR}.json | jq -r '.config."table.topic.name.template"' | awk 'BEGIN {FS = "_"} {print $2} '`
echo  Cluster is $CLUSTER
KAFKA_CMD="--bootstrap-server kafka.confluentv2.svc.${CLUSTER}:9071 --command-config /mnt/secrets/admin-props/admin_props"
SEARCH=`cat connect-${CONNECTOR}.json | jq -r '.config."table.topic.name.template"' | awk 'BEGIN {FS = "$"} {print $1} '`
TOPIC_REGEX="${SEARCH}.*"
NUM_EXISTING_TOPICS=`kubectl exec -it -n confluentv2 kafka-0 -- bash -c "kafka-topics $KAFKA_CMD --list --topic \"${TOPIC_REGEX}\"" | wc -l`
#Remove the redo log and extra lines from results
NUM_EXISTING_TOPICS=$(($NUM_EXISTING_TOPICS - 4))

echo Config expects to have $NUM_CONFIG_TABLES topics and there are currently $NUM_EXISTING_TOPICS

if [ $NUM_CONFIG_TABLES -ne $NUM_EXISTING_TOPICS ] 
then
echo The numbers dont match!
fi

EXISTING_TOPICS=( $(kubectl exec -it -n confluentv2 kafka-0 -- bash -c "kafka-topics $KAFKA_CMD --list --topic \"${TOPIC_REGEX}\" 2>/dev/null" 2>/dev/null) )

#Remove hidden carriage return from existing topics 
TOPIC_TRACKER=0
for x in ${EXISTING_TOPICS[@]}; do  
#echo Before ${EXISTING_TOPICS[$TOPIC_TRACKER]} | cat -v
EXISTING_TOPICS[$TOPIC_TRACKER]=`echo $x | col -b`; 
#echo After ${EXISTING_TOPICS[$TOPIC_TRACKER]} | cat -v
((TOPIC_TRACKER++))
done

#Check config topics vs existing topics
for x in ${EXPECTED_TOPICS[@]}; do 
MATCHED=0
  for y in ${EXISTING_TOPICS[@]}; do
    if [[ $y == *$x ]]; then
#      echo the   $x   expected topic matches the $y existing topic
      MATCHED=1
      break; 
    fi  
  done
  if [[ $MATCHED != 1 ]]; then 
    echo $x did not match any of the existing topics
  fi
done


#Check existing topics vs config topics
for x in ${EXISTING_TOPICS[@]}; do
MATCHED=0
  for y in ${EXPECTED_TOPICS[@]}; do
    if [[ $x == *$y ]]; then
#      echo the   $x   expected topic matches the $y existing topic
      MATCHED=1
      break;
    fi
  done
  if [[ $MATCHED != 1 ]]; then
    echo $x did not match any of the expected config topics
  fi
done



