# === Stake validators ===
stake_validators() {
    echo -e "\n${BLUE}=== $(t "staking_title") ===${NC}"

    # Get network settings
    local settings
    settings=$(get_network_settings)
    local network=$(echo "$settings" | cut -d'|' -f1)
    local rpc_url=$(echo "$settings" | cut -d'|' -f2)
    local contract_address=$(echo "$settings" | cut -d'|' -f3)

    # Проверяем существование необходимых файлов
    local KEYSTORE_FILE="$HOME/aztec/config/keystore.json"
    local BLS_PK_FILE="$HOME/aztec/bls-filtered-pk.json"

    if [ ! -f "$BLS_PK_FILE" ]; then
        printf "${RED}❌ $(t "file_not_found")${NC}\n" "bls-filtered-pk.json" "$BLS_PK_FILE"
        echo -e "${YELLOW}$(t "staking_run_bls_generation_first")${NC}"
        return 1
    fi

    # Правильная проверка формата - ищем поле new_operator_info внутри validators
    if jq -e '.validators[0].new_operator_info' "$BLS_PK_FILE" > /dev/null 2>&1; then
        # Новый формат - есть информация о новом операторе внутри валидаторов
        echo -e "${GREEN}🔍 Detected new operator method format${NC}"
        stake_validators_new_format "$network" "$rpc_url" "$contract_address"
    else
        # Старый формат - нет информации о новом операторе
        echo -e "${GREEN}🔍 Detected existing method format${NC}"
        stake_validators_old_format "$network" "$rpc_url" "$contract_address"
    fi
}
