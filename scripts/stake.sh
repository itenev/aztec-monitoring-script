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

# === Old format (existing method) ===
stake_validators_old_format() {
    local network="$1"
    local rpc_url="$2"
    local contract_address="$3"

    local KEYSTORE_FILE="$HOME/aztec/config/keystore.json"
    local BLS_PK_FILE="$HOME/aztec/bls-filtered-pk.json"

    if [ ! -f "$KEYSTORE_FILE" ]; then
        printf "${RED}❌ $(t "file_not_found")${NC}\n" "keystore.json" "$KEYSTORE_FILE"
        return 1
    fi

    if [ ! -f "$BLS_PK_FILE" ]; then
        printf "${RED}❌ $(t "file_not_found")${NC}\n" \
         "bls-filtered-pk.json" "$BLS_PK_FILE"
        return 1
    fi

    # Формируем ссылку для валидатора в зависимости от сети
    local validator_link_template
    if [[ "$network" == "mainnet" ]]; then
        validator_link_template="https://dashtec.xyz/validators/\$validator"
    else
        validator_link_template="https://${network}.dashtec.xyz/validators/\$validator"
    fi

    # Оригинальная логика для существующего метода
    local VALIDATOR_COUNT=$(jq -r '.validators | length' "$BLS_PK_FILE" 2>/dev/null)
    if [ -z "$VALIDATOR_COUNT" ] || [ "$VALIDATOR_COUNT" -eq 0 ]; then
        echo -e "${RED}❌ $(t "staking_no_validators") $BLS_PK_FILE${NC}"
        return 1
    fi

    printf "${GREEN}$(t "staking_found_validators")${NC}\n" "$VALIDATOR_COUNT"
    echo ""

    # Список RPC провайдеров
    local rpc_providers=(
        "$rpc_url"
        "https://ethereum-sepolia-rpc.publicnode.com"
        "https://1rpc.io/sepolia"
        "https://sepolia.drpc.org"
    )

    printf "${YELLOW}$(t "using_contract_address")${NC}\n" "$contract_address"
    echo ""

    # Цикл по всем валидаторам
    for ((i=0; i<VALIDATOR_COUNT; i++)); do
        printf "\n${BLUE}=== $(t "staking_processing") ===${NC}\n" \
         "$((i+1))" "$VALIDATOR_COUNT"
         echo ""

        # Из BLS файла берем приватные ключи
        local PRIVATE_KEY_OF_OLD_SEQUENCER=$(jq -r ".validators[$i].attester.eth" "$BLS_PK_FILE" 2>/dev/null)
        local BLS_ATTESTER_PRIV_KEY=$(jq -r ".validators[$i].attester.bls" "$BLS_PK_FILE" 2>/dev/null)

        # Из keystore файла берем Ethereum адреса
        local ETH_ATTESTER_ADDRESS=$(jq -r ".validators[$i].attester.eth" "$KEYSTORE_FILE" 2>/dev/null)

        # Проверяем что все данные получены
        if [ -z "$PRIVATE_KEY_OF_OLD_SEQUENCER" ] || [ "$PRIVATE_KEY_OF_OLD_SEQUENCER" = "null" ]; then
            printf "${RED}❌ $(t "staking_failed_private_key")${NC}\n" \
            "$((i+1))"
            continue
        fi

        if [ -z "$ETH_ATTESTER_ADDRESS" ] || [ "$ETH_ATTESTER_ADDRESS" = "null" ]; then
            printf "${RED}❌ $(t "staking_failed_eth_address")${NC}\n" \
            "$((i+1))"
            continue
        fi

        if [ -z "$BLS_ATTESTER_PRIV_KEY" ] || [ "$BLS_ATTESTER_PRIV_KEY" = "null" ]; then
            printf "${RED}❌ $(t "staking_failed_bls_key")${NC}\n" \
            "$((i+1))"
            continue
        fi

        echo -e "${GREEN}✓ $(t "staking_data_loaded")${NC}"
        echo -e "  $(t "eth_address"): $ETH_ATTESTER_ADDRESS"
        echo -e "  $(t "private_key"): ${PRIVATE_KEY_OF_OLD_SEQUENCER:0:10}..."
        echo -e "  $(t "bls_key"): ${BLS_ATTESTER_PRIV_KEY:0:20}..."

        # Цикл по RPC провайдерам
        local success=false
        for current_rpc_url in "${rpc_providers[@]}"; do
            printf "\n${YELLOW}$(t "staking_trying_rpc")${NC}\n" \
                  "$current_rpc_url"
             echo ""

            # Формируем команду
            local cmd="aztec add-l1-validator \\
  --l1-rpc-urls \"$current_rpc_url\" \\
  --network $network \\
  --private-key \"$PRIVATE_KEY_OF_OLD_SEQUENCER\" \\
  --attester \"$ETH_ATTESTER_ADDRESS\" \\
  --withdrawer \"$ETH_ATTESTER_ADDRESS\" \\
  --bls-secret-key \"$BLS_ATTESTER_PRIV_KEY\" \\
  --rollup \"$contract_address\""

            # Показываем команду с частичными приватными ключами (первые 7 символов)
            local PRIVATE_KEY_PREVIEW="${PRIVATE_KEY_OF_OLD_SEQUENCER:0:7}..."
            local BLS_KEY_PREVIEW="${BLS_ATTESTER_PRIV_KEY:0:7}..."

            local safe_cmd="aztec add-l1-validator \\
  --l1-rpc-urls \"$current_rpc_url\" \\
  --network $network \\
  --private-key \"$PRIVATE_KEY_PREVIEW\" \\
  --attester \"$ETH_ATTESTER_ADDRESS\" \\
  --withdrawer \"$ETH_ATTESTER_ADDRESS\" \\
  --bls-secret-key \"$BLS_KEY_PREVIEW\" \\
  --rollup \"$contract_address\""

            echo -e "${CYAN}$(t "command_to_execute")${NC}"
            echo -e "$safe_cmd"

            # Запрос подтверждения
            echo -e "\n${YELLOW}$(t "staking_command_prompt")${NC}"
            read -p "$(t "staking_execute_prompt"): " confirm

            case "$confirm" in
                [yY])
                    echo -e "${GREEN}$(t "staking_executing")${NC}"

                    if eval "$cmd"; then
                        printf "${GREEN}✅ $(t "staking_success")${NC}\n" \
                            "$((i+1))" "$current_rpc_url"
                        # Показываем ссылку на валидатора
                        local validator_link
                        if [[ "$network" == "mainnet" ]]; then
                            validator_link="https://dashtec.xyz/validators/$ETH_ATTESTER_ADDRESS"
                        else
                            validator_link="https://${network}.dashtec.xyz/validators/$ETH_ATTESTER_ADDRESS"
                        fi
                        echo -e "${CYAN}🌐 $(t "validator_link"): $validator_link${NC}"
                         echo ""

                        success=true
                        break  # Переходим к следующему валидатору
                    else
                        printf "${RED}❌ $(t "staking_failed")${NC}\n" \
                         "$((i+1))" "$current_rpc_url"
                         echo ""
                        echo -e "${YELLOW}$(t "trying_next_rpc")${NC}"
                    fi
                    ;;
                [sS])
                    printf "${YELLOW}⏭️ $(t "staking_skipped_validator")${NC}\n" \
                     "$((i+1))"
                    success=true  # Помечаем как "успех" чтобы перейти к следующему
                    break
                    ;;
                [qQ])
                    echo -e "${YELLOW}🛑 $(t "staking_cancelled")${NC}"
                    return 0
                    ;;
                *)
                    echo -e "${YELLOW}⏭️ $(t "staking_skipped_rpc")${NC}"
                    ;;
            esac
        done

        if [ "$success" = false ]; then
            printf "${RED}❌ $(t "staking_all_failed")${NC}\n" \
             "$((i+1))"
             echo ""
            echo -e "${YELLOW}$(t "continuing_next_validator")${NC}"
        fi

        # Небольшая пауза между валидаторами
        if [ $i -lt $((VALIDATOR_COUNT-1)) ]; then
            echo -e "\n${BLUE}--- $(t "waiting_before_next_validator") ---${NC}"
            sleep 2
        fi
    done

    echo -e "\n${GREEN}✅ $(t "staking_completed")${NC}"
    return 0
}

# === New format (new operator method) ===
stake_validators_new_format() {
    local network="$1"
    local rpc_url="$2"
    local contract_address="$3"

    local BLS_PK_FILE="$HOME/aztec/bls-filtered-pk.json"
    local KEYSTORE_FILE="$HOME/aztec/config/keystore.json"

    # Получаем количество валидаторов
    local VALIDATOR_COUNT=$(jq -r '.validators | length' "$BLS_PK_FILE" 2>/dev/null)
    if [ -z "$VALIDATOR_COUNT" ] || [ "$VALIDATOR_COUNT" -eq 0 ]; then
        echo -e "${RED}❌ $(t "staking_no_validators")${NC}"
        return 1
    fi

    echo -e "${GREEN}$(t "staking_found_validators_new_operator")${NC}" "$VALIDATOR_COUNT"
    echo ""

    # Создаем папку для ключей если не существует
    local KEYS_DIR="$HOME/aztec/keys"
    mkdir -p "$KEYS_DIR"

    printf "${YELLOW}$(t "using_contract_address")${NC}\n" "$contract_address"
    echo ""

    # Создаем резервную копию keystore.json перед изменениями
    local KEYSTORE_BACKUP="$KEYSTORE_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    if [ -f "$KEYSTORE_FILE" ]; then
        cp "$KEYSTORE_FILE" "$KEYSTORE_BACKUP"
        echo -e "${YELLOW}📁 $(t "staking_keystore_backup_created")${NC}" "$KEYSTORE_BACKUP"
    fi

    # Цикл по всем валидаторам
    for ((i=0; i<VALIDATOR_COUNT; i++)); do
        printf "\n${BLUE}=== $(t "staking_processing_new_operator") ===${NC}\n" \
         "$((i+1))" "$VALIDATOR_COUNT"
         echo ""

        # Получаем данные для текущего валидатора
        local PRIVATE_KEY_OF_OLD_SEQUENCER=$(jq -r ".validators[$i].attester.eth" "$BLS_PK_FILE" 2>/dev/null)
        local OLD_VALIDATOR_ADDRESS=$(jq -r ".validators[$i].attester.old_address" "$BLS_PK_FILE" 2>/dev/null)
        local NEW_ETH_PRIVATE_KEY=$(jq -r ".validators[$i].new_operator_info.eth_private_key" "$BLS_PK_FILE" 2>/dev/null)
        local BLS_ATTESTER_PRIV_KEY=$(jq -r ".validators[$i].new_operator_info.bls_private_key" "$BLS_PK_FILE" 2>/dev/null)
        local ETH_ATTESTER_ADDRESS=$(jq -r ".validators[$i].new_operator_info.eth_address" "$BLS_PK_FILE" 2>/dev/null)
        local VALIDATOR_RPC_URL=$(jq -r ".validators[$i].new_operator_info.rpc_url" "$BLS_PK_FILE" 2>/dev/null)

        # Приводим адреса к нижнему регистру для сравнения
        local OLD_VALIDATOR_ADDRESS_LOWER=$(echo "$OLD_VALIDATOR_ADDRESS" | tr '[:upper:]' '[:lower:]')
        local ETH_ATTESTER_ADDRESS_LOWER=$(echo "$ETH_ATTESTER_ADDRESS" | tr '[:upper:]' '[:lower:]')

        # Проверяем что все данные получены
        if [ -z "$PRIVATE_KEY_OF_OLD_SEQUENCER" ] || [ "$PRIVATE_KEY_OF_OLD_SEQUENCER" = "null" ] ||
           [ -z "$NEW_ETH_PRIVATE_KEY" ] || [ "$NEW_ETH_PRIVATE_KEY" = "null" ] ||
           [ -z "$BLS_ATTESTER_PRIV_KEY" ] || [ "$BLS_ATTESTER_PRIV_KEY" = "null" ] ||
           [ -z "$ETH_ATTESTER_ADDRESS" ] || [ "$ETH_ATTESTER_ADDRESS" = "null" ]; then
            printf "${RED}❌ $(t "staking_failed_private_key")${NC}\n" "$((i+1))"
            continue
        fi

        echo -e "${GREEN}✓ $(t "staking_data_loaded")${NC}"
        echo -e "  Old address: $OLD_VALIDATOR_ADDRESS"
        echo -e "  New address: $ETH_ATTESTER_ADDRESS"
        echo -e "  $(t "private_key"): ${PRIVATE_KEY_OF_OLD_SEQUENCER:0:10}..."
        echo -e "  $(t "bls_key"): ${BLS_ATTESTER_PRIV_KEY:0:20}..."

        # Список RPC провайдеров (используем сохраненный или дефолтный список)
        local rpc_providers=("${VALIDATOR_RPC_URL:-$rpc_url}")
        if [ -z "$VALIDATOR_RPC_URL" ] || [ "$VALIDATOR_RPC_URL" = "null" ]; then
            rpc_providers=(
                "$rpc_url"
                "https://ethereum-sepolia-rpc.publicnode.com"
                "https://1rpc.io/sepolia"
                "https://sepolia.drpc.org"
            )
        fi

        # Цикл по RPC провайдерам
        local success=false
        for current_rpc_url in "${rpc_providers[@]}"; do
            printf "\n${YELLOW}$(t "staking_trying_rpc")${NC}\n" "$current_rpc_url"
            echo ""

            # Формируем команду
            local cmd="aztec add-l1-validator \\
  --l1-rpc-urls \"$current_rpc_url\" \\
  --network $network \\
  --private-key \"$PRIVATE_KEY_OF_OLD_SEQUENCER\" \\
  --attester \"$ETH_ATTESTER_ADDRESS\" \\
  --withdrawer \"$ETH_ATTESTER_ADDRESS\" \\
  --bls-secret-key \"$BLS_ATTESTER_PRIV_KEY\" \\
  --rollup \"$contract_address\""

            # Безопасное отображение команды
            local PRIVATE_KEY_PREVIEW="${PRIVATE_KEY_OF_OLD_SEQUENCER:0:7}..."
            local BLS_KEY_PREVIEW="${BLS_ATTESTER_PRIV_KEY:0:7}..."

            local safe_cmd="aztec add-l1-validator \\
  --l1-rpc-urls \"$current_rpc_url\" \\
  --network $network \\
  --private-key \"$PRIVATE_KEY_PREVIEW\" \\
  --attester \"$ETH_ATTESTER_ADDRESS\" \\
  --withdrawer \"$ETH_ATTESTER_ADDRESS\" \\
  --bls-secret-key \"$BLS_KEY_PREVIEW\" \\
  --rollup \"$contract_address\""

            echo -e "${CYAN}$(t "command_to_execute")${NC}"
            echo -e "$safe_cmd"

            # Запрос подтверждения
            echo -e "\n${YELLOW}$(t "staking_command_prompt")${NC}"
            read -p "$(t "staking_execute_prompt"): " confirm

            case "$confirm" in
                [yY])
                    echo -e "${GREEN}$(t "staking_executing")${NC}"
                    if eval "$cmd"; then
                        printf "${GREEN}✅ $(t "staking_success_new_operator")${NC}\n" \
                                    "$((i+1))" "$current_rpc_url"

                        local validator_link
                        if [[ "$network" == "mainnet" ]]; then
                            validator_link="https://dashtec.xyz/validators/$ETH_ATTESTER_ADDRESS"
                        else
                            validator_link="https://${network}.dashtec.xyz/validators/$ETH_ATTESTER_ADDRESS"
                        fi
                        echo -e "${CYAN}🌐 $(t "validator_link"): $validator_link${NC}"

                        # Создаем YML файл для успешно застейканного валидатора
                        local YML_FILE="$KEYS_DIR/new_validator_$((i+1)).yml"
                        cat > "$YML_FILE" << EOF
type: "file-raw"
keyType: "SECP256K1"
privateKey: "$NEW_ETH_PRIVATE_KEY"
EOF

                        if [ -f "$YML_FILE" ]; then
                            echo -e "${GREEN}📁 $(t "staking_yml_file_created")${NC}" "$YML_FILE"

                            # Перезапускаем web3signer для загрузки нового ключа
                            echo -e "${BLUE}🔄 $(t "staking_restarting_web3signer")${NC}"
                            if docker restart web3signer > /dev/null 2>&1; then
                                echo -e "${GREEN}✅ $(t "staking_web3signer_restarted")${NC}"

                                # Проверяем статус web3signer после перезапуска
                                sleep 3
                                if docker ps | grep -q web3signer; then
                                    echo -e "${GREEN}✅ $(t "staking_web3signer_running")${NC}"
                                else
                                    echo -e "${YELLOW}⚠️ $(t "staking_web3signer_not_running")${NC}"
                                fi
                            else
                                echo -e "${RED}❌ $(t "staking_web3signer_restart_failed")${NC}"
                            fi
                        else
                            echo -e "${RED}⚠️ $(t "staking_yml_file_failed")${NC}" "$YML_FILE"
                        fi

                        # Заменяем старый адрес валидатора на новый в keystore.json
                        if [ -f "$KEYSTORE_FILE" ] && [ "$OLD_VALIDATOR_ADDRESS" != "null" ] && [ -n "$OLD_VALIDATOR_ADDRESS" ]; then
                            echo -e "${BLUE}🔄 $(t "staking_updating_keystore")${NC}"

                            # Создаем временный файл для обновленного keystore
                            local TEMP_KEYSTORE=$(mktemp)

                            # Заменяем старый адрес на новый в keystore.json (регистронезависимо)
                            if jq --arg old_addr_lower "$OLD_VALIDATOR_ADDRESS_LOWER" \
                                  --arg new_addr "$ETH_ATTESTER_ADDRESS" \
                                  'walk(if type == "object" and has("attester") and (.attester | ascii_downcase) == $old_addr_lower then .attester = $new_addr else . end)' \
                                  "$KEYSTORE_FILE" > "$TEMP_KEYSTORE"; then

                                # Проверяем, что замена произошла
                                if jq -e --arg new_addr "$ETH_ATTESTER_ADDRESS" \
                                         'any(.validators[]; .attester == $new_addr)' "$TEMP_KEYSTORE" > /dev/null; then

                                    mv "$TEMP_KEYSTORE" "$KEYSTORE_FILE"
                                    echo -e "${GREEN}✅ $(t "staking_keystore_updated")${NC}" "$OLD_VALIDATOR_ADDRESS → $ETH_ATTESTER_ADDRESS"

                                    # Дополнительная проверка: находим все вхождения нового адреса
                                    local MATCH_COUNT=$(jq -r --arg new_addr "$ETH_ATTESTER_ADDRESS" \
                                                         '[.validators[] | select(.attester == $new_addr)] | length' "$KEYSTORE_FILE")
                                    echo -e "${CYAN}🔍 Found $MATCH_COUNT occurrence(s) of new address in keystore${NC}"

                                else
                                    echo -e "${YELLOW}⚠️ $(t "staking_keystore_no_change")${NC}" "$OLD_VALIDATOR_ADDRESS"
                                    echo -e "${CYAN}Debug: Searching for old address in keystore...${NC}"

                                    # Отладочная информация: проверяем наличие старого адреса в keystore
                                    local OLD_ADDR_COUNT=$(jq -r --arg old_addr_lower "$OLD_VALIDATOR_ADDRESS_LOWER" \
                                                         '[.validators[] | select(.attester | ascii_downcase == $old_addr_lower)] | length' "$KEYSTORE_FILE")
                                    echo -e "${CYAN}Debug: Found $OLD_ADDR_COUNT occurrence(s) of old address (case-insensitive)${NC}"

                                    rm -f "$TEMP_KEYSTORE"
                                fi
                            else
                                echo -e "${RED}❌ $(t "staking_keystore_update_failed")${NC}"
                                rm -f "$TEMP_KEYSTORE"
                            fi
                        else
                            echo -e "${YELLOW}⚠️ $(t "staking_keystore_skip_update")${NC}"
                        fi

                        success=true
                        break
                    else
                        printf "${RED}❌ $(t "staking_failed_new_operator")${NC}\n" \
                         "$((i+1))" "$current_rpc_url"
                        echo -e "${YELLOW}$(t "trying_next_rpc")${NC}"
                    fi
                    ;;
                [sS])
                    printf "${YELLOW}⏭️ $(t "staking_skipped_validator")${NC}\n" "$((i+1))"
                    success=true
                    break
                    ;;
                [qQ])
                    echo -e "${YELLOW}🛑 $(t "staking_cancelled")${NC}"
                    return 0
                    ;;
                *)
                    echo -e "${YELLOW}⏭️ $(t "staking_skipped_rpc")${NC}"
                    ;;
            esac
        done

        if [ "$success" = false ]; then
            printf "${RED}❌ $(t "staking_all_failed_new_operator")${NC}\n" "$((i+1))"
            echo -e "${YELLOW}$(t "continuing_next_validator")${NC}"
        fi

        # Небольшая пауза между валидаторами
        if [ $i -lt $((VALIDATOR_COUNT-1)) ]; then
            echo -e "\n${BLUE}--- $(t "waiting_before_next_validator") ---${NC}"
            sleep 2
        fi
    done

    echo -e "\n${GREEN}✅ $(t "staking_completed_new_operator")${NC}"
    echo -e "${YELLOW}$(t "bls_restart_node_notice")${NC}"

    # Показываем итоговую информацию о созданных файлах
    local CREATED_FILES=$(find "$KEYS_DIR" -name "new_validator_*.yml" | wc -l)
    if [ "$CREATED_FILES" -gt 0 ]; then
        echo -e "${GREEN}📂 $(t "staking_total_yml_files_created")${NC}" "$CREATED_FILES"
        echo -e "${CYAN}$(t "staking_yml_files_location")${NC}" "$KEYS_DIR"

        # Финальный перезапуск web3signer для гарантии загрузки всех ключей
        echo -e "\n${BLUE}🔄 $(t "staking_final_web3signer_restart")${NC}"
        if docker restart web3signer > /dev/null 2>&1; then
            echo -e "${GREEN}✅ $(t "staking_final_web3signer_restarted")${NC}"
        else
            echo -e "${YELLOW}⚠️ $(t "staking_final_web3signer_restart_failed")${NC}"
        fi
    fi

    return 0
}
