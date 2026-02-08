# === Remove systemd task and agent ===
remove_systemd_agent() {
  echo -e "\n${BLUE}$(t "removing_systemd_agent")${NC}"
  systemctl stop aztec-agent.timer
  systemctl disable aztec-agent.timer
  rm /etc/systemd/system/aztec-agent.*
  rm -rf "$AGENT_SCRIPT_PATH"
  echo -e "\n${GREEN}$(t "agent_systemd_removed")${NC}"
}
