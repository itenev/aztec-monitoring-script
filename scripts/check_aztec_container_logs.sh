# === Check container logs for block ===
check_aztec_container_logs() {
    cd $HOME

    # Get network settings
    local settings
    settings=$(get_network_settings)
    local network=$(echo "$settings" | cut -d'|' -f1)
    local rpc_url=$(echo "$settings" | cut -d'|' -f2)
    local contract_address=$(echo "$settings" | cut -d'|' -f3)

    # Security: Use local file instead of remote download to prevent supply chain attacks
    ERROR_DEFINITIONS_FILE="$SCRIPT_DIR/error_definitions.json"

    # Загружаем JSON с определениями ошибок из локального файла
    download_error_definitions() {
        if [ ! -f "$ERROR_DEFINITIONS_FILE" ]; then
            echo -e "\n${YELLOW}Warning: Error definitions file not found at $ERROR_DEFINITIONS_FILE${NC}"
            echo -e "${YELLOW}Please download the Error definitions file with Option 24${NC}"
            return 1
        fi
        return 0
    }
