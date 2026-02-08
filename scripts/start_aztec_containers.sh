# === Start Aztec containers ===
function start_aztec_containers() {
  local env_file
  env_file=$(_ensure_env_file)

  echo -e "\n${YELLOW}$(t "starting_node")${NC}"

  local run_type
  run_type=$(_read_env_var "$env_file" "RUN_TYPE")

  if [[ -z "$run_type" ]]; then
    echo -e "${YELLOW}$(t "run_type_not_set")${NC}"
    read -p "$(t "confirm_cli_run") [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      run_type="CLI"
      _update_env_var "$env_file" "RUN_TYPE" "$run_type"
      echo -e "${GREEN}$(t "run_type_set_to_cli")${NC}"
    else
      echo -e "${RED}$(t "run_aborted")${NC}"
      return 1
    fi
  fi

  # Получаем значение NETWORK из env-aztec-agent
  local aztec_agent_env="$HOME/.env-aztec-agent"
  local network="testnet"
  if [[ -f "$aztec_agent_env" ]]; then
    network=$(_read_env_var "$aztec_agent_env" "NETWORK")
    [[ -z "$network" ]] && network="testnet"
  fi

  case "$run_type" in
    "DOCKER")
      local compose_path
      compose_path=$(_read_env_var "$env_file" "COMPOSE_PATH")

      if ! _validate_compose_path "$compose_path"; then
        echo -e "${RED}$(t "missing_compose")${NC}"
        read -p "$(t "enter_compose_path")" compose_path
        if ! _validate_compose_path "$compose_path"; then
          echo -e "${RED}$(t "invalid_path")${NC}"
          return 1
        fi
        _update_env_var "$env_file" "COMPOSE_PATH" "$compose_path"
      fi

      if cd "$compose_path" && docker compose up -d; then
        echo -e "${GREEN}$(t "node_started")${NC}"
      else
        echo -e "${RED}Failed to start Docker containers${NC}"
        return 1
      fi
      ;;

    "CLI")
      local p2p_ip
      p2p_ip=$(curl -s https://api.ipify.org || echo "127.0.0.1")

      declare -A vars=(
        ["RPC_URL"]="Ethereum Execution RPC URL"
        ["CONSENSUS_BEACON_URL"]="Consensus Beacon URL"
        ["VALIDATOR_PRIVATE_KEY"]="Validator Private Key (without 0x)"
        ["COINBASE"]="Coinbase (your EVM wallet address)"
        ["P2P_IP"]="$p2p_ip"
      )

      for key in "${!vars[@]}"; do
        if ! grep -q "^$key=" "$env_file"; then
          local prompt="${vars[$key]}"
          local val
          if [[ "$key" == "P2P_IP" ]]; then
            val="$p2p_ip"
          else
            read -p "$prompt: " val
          fi
          _update_env_var "$env_file" "$key" "$val"
        fi
      done

      local ethereum_rpc_url consensus_beacon_url validator_private_key coinbase
      ethereum_rpc_url=$(_read_env_var "$env_file" "RPC_URL")
      consensus_beacon_url=$(_read_env_var "$env_file" "CONSENSUS_BEACON_URL")
      validator_private_key=$(_read_env_var "$env_file" "VALIDATOR_PRIVATE_KEY")
      coinbase=$(_read_env_var "$env_file" "COINBASE")
      p2p_ip=$(_read_env_var "$env_file" "P2P_IP")

      local session_name
      session_name=$(_read_env_var "$env_file" "SCREEN_SESSION")
      [[ -z "$session_name" ]] && session_name="aztec"
      _update_env_var "$env_file" "SCREEN_SESSION" "$session_name"

      # Проверка и удаление существующих сессий с aztec
      existing_sessions=$(screen -ls | grep -oP '[0-9]+\.aztec[^\s]*')
      if [[ -n "$existing_sessions" ]]; then
        while read -r session; do
          screen -XS "$session" quit
          echo -e "${YELLOW}$(t "cli_quit_old_sessions") $session${NC}"
        done <<< "$existing_sessions"
      fi

      if screen -dmS "$session_name" && \
         screen -S "$session_name" -p 0 -X stuff "aztec start --node --archiver --sequencer \
--network $network \
--l1-rpc-urls $ethereum_rpc_url \
--l1-consensus-host-urls $consensus_beacon_url \
--sequencer.validatorPrivateKeys 0x$validator_private_key \
--sequencer.coinbase $coinbase \
--p2p.p2pIp $p2p_ip"$'\n'; then
        echo -e "${GREEN}$(t "node_started")${NC}"
      else
        echo -e "${RED}Failed to start Aztec in screen session${NC}"
        return 1
      fi
      ;;

    *)
      echo -e "${RED}Unknown RUN_TYPE: $run_type${NC}"
      return 1
      ;;
  esac
}
