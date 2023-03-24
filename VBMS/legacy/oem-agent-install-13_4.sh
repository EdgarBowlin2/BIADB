curl "https://vb-shr-oem101.shared.aide.oit.va.gov:7803/em/install/getAgentImage" --insecure -o /home/oracle/AgentPull.sh
chown oracle:oinstall /home/oracle/AgentPull.sh
chmod +x /home/oracle/AgentPull.sh

cat <<EOT >/home/oracle/AgentPull.rsp
LOGIN_USER=SCRIPT
LOGIN_PASSWORD=AyTJmXNHmDhEMxGxnqGsSJCF
PLATFORM="Linux x86-64"
AGENT_REGISTRATION_PASSWORD=xLdKEE0S6njQn2PiAZ
AGENT_BASE_DIR=/u01/app/oracle/agent
ORACLE_HOSTNAME=$(hostname | cut -d "." -f1 | tr '[:lower:]' '[:upper:]').$(hostname | cut -d "." -f2- | tr '[:upper:]' '[:lower:]')
EOT

chown oracle:oinstall /home/oracle/AgentPull.rsp
sudo -u oracle /home/oracle/AgentPull.sh RSPFILE_LOC=/home/oracle/AgentPull.rsp

/u01/app/oracle/agent/agent_13.4.0.0.0/root.sh
