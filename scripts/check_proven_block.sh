# === Check Proven L2 Block and Sync Proof ===
check_proven_block() {
    ENV_FILE="$HOME/.env-aztec-agent"

    # Get network settings
    local settings
    settings=$(get_network_settings)
    local network=$(echo "$settings" | cut -d'|' -f1)
    local rpc_url=$(echo "$settings" | cut -d'|' -f2)
    local contract_address=$(echo "$settings" | cut -d'|' -f3)

    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
    fi

    AZTEC_PORT=${AZTEC_PORT:-8080}

    echo -e "\n${CYAN}$(t "current_aztec_port") $AZTEC_PORT${NC}"
    read -p "$(t "enter_aztec_port_prompt") [${AZTEC_PORT}]: " user_port

    if [ -n "$user_port" ]; then
        # Validate port: numeric and in range 1-65535 (injection prevention)
        if [[ ! "$user_port" =~ ^[0-9]+$ ]] || (( user_port < 1 || user_port > 65535 )); then
            echo -e "${RED}Invalid port. Enter a number between 1 and 65535.${NC}"
            return 1
        fi
        AZTEC_PORT=$user_port

        if grep -q "^AZTEC_PORT=" "$ENV_FILE" 2>/dev/null; then
            sed -i "s/^AZTEC_PORT=.*/AZTEC_PORT=$AZTEC_PORT/" "$ENV_FILE"
        else
            echo "AZTEC_PORT=$AZTEC_PORT" >> "$ENV_FILE"
        fi

        echo -e "${GREEN}$(t "port_saved_successfully")${NC}"
    fi

    echo -e "\n${BLUE}$(t "checking_port") $AZTEC_PORT...${NC}"
    if ! nc -z -w 2 localhost $AZTEC_PORT; then
        echo -e "\n${RED}$(t "port_not_available") $AZTEC_PORT${NC}"
        echo -e "${YELLOW}$(t "check_node_running")${NC}"
        return 1
    fi

    echo -e "\n${BLUE}$(t "get_proven_block")${NC}"

    local proven_block_tmp
    proven_block_tmp=$(mktemp)
    # Фоновый процесс получения блока
    (
        curl -s -X POST -H 'Content-Type: application/json' \
          -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
          http://localhost:$AZTEC_PORT | jq -r ".result.proven.number"
    ) > "$proven_block_tmp" &
    pid1=$!
    spinner $pid1
    wait $pid1

    PROVEN_BLOCK=$(< "$proven_block_tmp")
    rm -f "$proven_block_tmp"

    if [[ -z "$PROVEN_BLOCK" || "$PROVEN_BLOCK" == "null" ]]; then
        echo -e "\n${RED}$(t "proven_block_error")${NC}"
        return 1
    fi

    echo -e "\n${GREEN}$(t "proven_block_found") $PROVEN_BLOCK${NC}"

    echo -e "\n${BLUE}$(t "get_sync_proof")${NC}"

    local sync_proof_tmp
    sync_proof_tmp=$(mktemp)
    # Фоновый процесс получения proof
    (
        curl -s -X POST -H 'Content-Type: application/json' \
          -d "{\"jsonrpc\":\"2.0\",\"method\":\"node_getArchiveSiblingPath\",\"params\":[\"$PROVEN_BLOCK\",\"$PROVEN_BLOCK\"],\"id\":68}" \
          http://localhost:$AZTEC_PORT | jq -r ".result"
    ) > "$sync_proof_tmp" &
    pid2=$!
    spinner $pid2
    wait $pid2

    SYNC_PROOF=$(< "$sync_proof_tmp")
    rm -f "$sync_proof_tmp"

    if [[ -z "$SYNC_PROOF" || "$SYNC_PROOF" == "null" ]]; then
        echo -e "\n${RED}$(t "sync_proof_error")${NC}"
        return 1
    fi

    echo -e "\n${GREEN}$(t "sync_proof_found")${NC}"
    echo "$SYNC_PROOF"
    return 0
}
