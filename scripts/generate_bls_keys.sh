# === Generate BLS keys with mode selection ===
generate_bls_keys() {
    echo -e "\n${BLUE}=== BLS Keys Generation and Transfer ===${NC}"
    echo -e "${RED}WARNING: This operation involves handling private keys. Please be extremely careful and ensure you are in a secure environment.${NC}"

    # Выбор способа генерации
    echo -e "\n${CYAN}Select an action with BLS:${NC}"
    echo -e "1) $(t "bls_method_new_operator")"
    echo -e "2) $(t "bls_method_existing")"
    echo -e "3) $(t "bls_to_keystore")"
    echo -e "4) $(t "bls_method_dashboard")"
    echo ""
    read -p "$(t "bls_method_prompt") " GENERATION_METHOD

    case $GENERATION_METHOD in
        1)
            generate_bls_new_operator_method
            ;;
        2)
            generate_bls_existing_method
            ;;
        3)
            add_bls_to_keystore
            ;;
        4)
            generate_bls_dashboard_method
            ;;
        *)
            echo -e "${RED}$(t "bls_invalid_method")${NC}"
            return 1
            ;;
    esac
}

add_bls_to_keystore() {
    echo -e "\n${BLUE}=== $(t "bls_add_to_keystore_title") ===${NC}"

    # Файлы
    local BLS_PK_FILE="$HOME/aztec/bls-filtered-pk.json"
    local KEYSTORE_FILE="$HOME/aztec/config/keystore.json"
    local KEYSTORE_BACKUP="${KEYSTORE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

    # Проверка существования файлов
    if [ ! -f "$BLS_PK_FILE" ]; then
        echo -e "${RED}$(t "bls_pk_file_not_found")${NC}"
        return 1
    fi

    if [ ! -f "$KEYSTORE_FILE" ]; then
        echo -e "${RED}$(t "bls_keystore_not_found")${NC}"
        return 1
    fi

    # Создаем бекап
    echo -e "${CYAN}$(t "bls_creating_backup")${NC}"
    cp "$KEYSTORE_FILE" "$KEYSTORE_BACKUP"
    echo -e "${GREEN}✅ $(t "bls_backup_created"): $KEYSTORE_BACKUP${NC}"

    # Создаем временный файл
    local TEMP_KEYSTORE=$(mktemp)
    local MATCH_COUNT=0
    local TOTAL_VALIDATORS=0

    # Получаем общее количество валидаторов в keystore.json
    TOTAL_VALIDATORS=$(jq '.validators | length' "$KEYSTORE_FILE")

    echo -e "${CYAN}$(t "bls_processing_validators"): $TOTAL_VALIDATORS${NC}"

    # Создаем ассоциативный массив для сопоставления адресов с BLS ключами
    declare -A ADDRESS_TO_BLS_MAP

    # Заполняем маппинг адресов к BLS ключам из bls-filtered-pk.json
    echo -e "\n${BLUE}$(t "bls_reading_bls_keys")${NC}"
    while IFS= read -r validator; do
        local PRIVATE_KEY=$(echo "$validator" | jq -r '.attester.eth')
        local BLS_KEY=$(echo "$validator" | jq -r '.attester.bls')

        if [ -n "$PRIVATE_KEY" ] && [ "$PRIVATE_KEY" != "null" ] &&
           [ -n "$BLS_KEY" ] && [ "$BLS_KEY" != "null" ]; then

            # Генерируем адрес из приватного ключа
            local ETH_ADDRESS=$(cast wallet address --private-key "$PRIVATE_KEY" 2>/dev/null | tr '[:upper:]' '[:lower:]')

            if [ -n "$ETH_ADDRESS" ]; then
                ADDRESS_TO_BLS_MAP["$ETH_ADDRESS"]="$BLS_KEY"
                echo -e "${GREEN}✅ $(t "bls_mapped_address"): $ETH_ADDRESS${NC}"
            else
                echo -e "${YELLOW}⚠️ $(t "bls_failed_generate_address"): ${PRIVATE_KEY:0:20}...${NC}"
            fi
        fi
    done < <(jq -c '.validators[]' "$BLS_PK_FILE")

    if [ ${#ADDRESS_TO_BLS_MAP[@]} -eq 0 ]; then
        echo -e "${RED}$(t "bls_no_valid_mappings")${NC}"
        rm -f "$TEMP_KEYSTORE"
        return 1
    fi

    echo -e "${GREEN}✅ $(t "bls_total_mappings"): ${#ADDRESS_TO_BLS_MAP[@]}${NC}"

    # Обрабатываем keystore.json и добавляем BLS ключи
    echo -e "\n${BLUE}$(t "bls_updating_keystore")${NC}"

    # Создаем новый массив валидаторов с добавленными BLS ключами
    local UPDATED_VALIDATORS_JSON=$(jq -c \
        --argjson mappings "$(declare -p ADDRESS_TO_BLS_MAP)" \
        '
        .validators = (.validators | map(
            . as $validator |
            $validator.attester.eth as $address |
            if $address and ($address | ascii_downcase) then
                # Ищем соответствующий BLS ключ
                ($address | ascii_downcase) as $normalized_addr |
                if (env | has("ADDRESS_TO_BLS_MAP")) and (env.ADDRESS_TO_BLS_MAP | has($normalized_addr)) then
                    $validator | .attester.bls = env.ADDRESS_TO_BLS_MAP[$normalized_addr]
                else
                    $validator
                end
            else
                $validator
            end
        ))' "$KEYSTORE_FILE" 2>/dev/null)

    # Альтернативный подход через временные файлы
    local TEMP_JSON=$(mktemp)

    # Начинаем сборку нового JSON
    cat "$KEYSTORE_FILE" | jq '.' > "$TEMP_JSON"

    # Обновляем каждый валидатор
    for i in $(seq 0 $((TOTAL_VALIDATORS - 1))); do
        local VALIDATOR_ETH=$(jq -r ".validators[$i].attester.eth" "$TEMP_JSON" | tr '[:upper:]' '[:lower:]')

        if [ -n "$VALIDATOR_ETH" ] && [ "$VALIDATOR_ETH" != "null" ]; then
            if [ -n "${ADDRESS_TO_BLS_MAP[$VALIDATOR_ETH]}" ]; then
                # Обновляем валидатор с добавлением BLS ключа
                jq --arg idx "$i" --arg bls "${ADDRESS_TO_BLS_MAP[$VALIDATOR_ETH]}" \
                    '.validators[$idx | tonumber].attester.bls = $bls' \
                    "$TEMP_JSON" > "${TEMP_JSON}.tmp" && mv "${TEMP_JSON}.tmp" "$TEMP_JSON"

                ((MATCH_COUNT++))
                echo -e "${GREEN}✅ $(t "bls_key_added"): $VALIDATOR_ETH${NC}"
            else
                echo -e "${YELLOW}⚠️ $(t "bls_no_key_for_address"): $VALIDATOR_ETH${NC}"
            fi
        fi
    done

    # Проверяем результат
    if [ $MATCH_COUNT -eq 0 ]; then
        echo -e "${RED}$(t "bls_no_matches_found")${NC}"
        rm -f "$TEMP_JSON" "${TEMP_JSON}.tmp"
        return 1
    fi

    # Проверяем валидность JSON перед сохранением
    if jq empty "$TEMP_JSON" 2>/dev/null; then
        # Сохраняем обновленный файл
        cp "$TEMP_JSON" "$KEYSTORE_FILE"
        echo -e "${GREEN}✅ $(t "bls_keystore_updated")${NC}"
        echo -e "${GREEN}✅ $(t "bls_total_updated"): $MATCH_COUNT/$TOTAL_VALIDATORS${NC}"

        # Показываем пример обновленной структуры
        echo -e "\n${BLUE}=== $(t "bls_updated_structure_sample") ===${NC}"
        jq '.validators[0]' "$KEYSTORE_FILE" | head -20
    else
        echo -e "${RED}$(t "bls_invalid_json")${NC}"
        echo -e "${YELLOW}$(t "bls_restoring_backup")${NC}"
        cp "$KEYSTORE_BACKUP" "$KEYSTORE_FILE"
        rm -f "$TEMP_JSON" "${TEMP_JSON}.tmp"
        return 1
    fi

    # Очистка временных файлов
    rm -f "$TEMP_JSON" "${TEMP_JSON}.tmp"

    echo -e "\n${GREEN}🎉 $(t "bls_operation_completed")${NC}"
    return 0
}


# === Dashboard keystores: private + staker_output (docs.aztec.network/operate/.../sequencer_management) ===
generate_bls_dashboard_method() {
    echo -e "\n${BLUE}=== $(t "bls_dashboard_title") ===${NC}"

    local AZTEC_DIR="$HOME/aztec"
    
    local PRIVATE_FILE="$AZTEC_DIR/dashboard_keystore.json"
    local STAKER_FILE="$AZTEC_DIR/dashboard_keystore_staker_output.json"

    mkdir -p "$AZTEC_DIR"

    # Сеть и RPC из настроек скрипта
    local settings
    settings=$(get_network_settings)
    local network=$(echo "$settings" | cut -d'|' -f1)
    local rpc_url=$(echo "$settings" | cut -d'|' -f2)

    local GSE_ADDRESS
    if [[ "$network" == "mainnet" ]]; then
        GSE_ADDRESS="$GSE_ADDRESS_MAINNET"
    else
        GSE_ADDRESS="$GSE_ADDRESS_TESTNET"
    fi

    if [ -z "$rpc_url" ] || [ "$rpc_url" = "null" ]; then
        rpc_url="https://ethereum-sepolia-rpc.publicnode.com"
        echo -e "${YELLOW}RPC not set in .env-aztec-agent, using default: $rpc_url${NC}"
    fi

    echo -e "${CYAN}$(t "bls_dashboard_new_or_mnemonic")${NC}"
    read -p "> " DASHBOARD_MODE

    local RUN_OK=0
    if [ "$DASHBOARD_MODE" = "2" ]; then
        echo -e "\n${CYAN}$(t "bls_mnemonic_prompt")${NC}"
        read -s -p "> " MNEMONIC
        echo
        if [ -z "$MNEMONIC" ]; then
            echo -e "${RED}Error: Mnemonic phrase cannot be empty${NC}"
            return 1
        fi
        echo -e "\n${CYAN}$(t "bls_dashboard_count_prompt")${NC}"
        read -p "> " WALLET_COUNT
        if ! [[ "$WALLET_COUNT" =~ ^[1-9][0-9]*$ ]]; then
            WALLET_COUNT=1
        fi
        echo -e "\n${YELLOW}Running: aztec validator-keys new --staker-output ... --file dashboard_keystore.json --mnemonic \"...\" --count $WALLET_COUNT${NC}"
        if aztec validator-keys new \
            --fee-recipient "$FEE_RECIPIENT_ZERO" \
            --staker-output \
            --gse-address "$GSE_ADDRESS" \
            --l1-rpc-urls "$rpc_url" \
            --data-dir "$AZTEC_DIR" \
            --file "dashboard_keystore.json" \
            --mnemonic "$MNEMONIC" \
            --count "$WALLET_COUNT"; then
            RUN_OK=1
        fi
    else
        echo -e "\n${CYAN}$(t "bls_dashboard_count_prompt")${NC}"
        read -p "> " WALLET_COUNT
        if ! [[ "$WALLET_COUNT" =~ ^[1-9][0-9]*$ ]]; then
            WALLET_COUNT=1
        fi
        echo -e "\n${YELLOW}Running: aztec validator-keys new --staker-output ... --file dashboard_keystore.json --count $WALLET_COUNT (new mnemonic)${NC}"
        if aztec validator-keys new \
            --fee-recipient "$FEE_RECIPIENT_ZERO" \
            --staker-output \
            --gse-address "$GSE_ADDRESS" \
            --l1-rpc-urls "$rpc_url" \
            --data-dir "$AZTEC_DIR" \
            --file "dashboard_keystore.json" \
            --count "$WALLET_COUNT"; then
            RUN_OK=1
        fi
    fi

    if [ "$RUN_OK" -eq 1 ]; then
        if [ -f "$PRIVATE_FILE" ]; then
            echo -e "${GREEN}✅ $(t "bls_dashboard_saved")${NC}"
            echo -e "   Private: $PRIVATE_FILE"
            [ -f "$STAKER_FILE" ] && echo -e "   Staker (for dashboard): $STAKER_FILE"
        else
            echo -e "${YELLOW}Command succeeded but expected file not found: $PRIVATE_FILE (check CLI --file/--data-dir behavior)${NC}"
        fi
    else
        echo -e "${RED}$(t "bls_generation_failed")${NC}"
        return 1
    fi
    return 0
}

# === Исправленная версия функции для новой структуры keystore.json ===
generate_bls_existing_method() {
    echo -e "\n${BLUE}=== $(t "bls_existing_method_title") ===${NC}"

    # 1. Запрос мнемонической фразы (скрытый ввод)
    echo -e "\n${CYAN}$(t "bls_mnemonic_prompt")${NC}"
    read -s -p "> " MNEMONIC
    echo

    if [ -z "$MNEMONIC" ]; then
        echo -e "${RED}Error: Mnemonic phrase cannot be empty${NC}"
        return 1
    fi

    # 2. Запрос количества кошельков
    echo -e "\n${CYAN}$(t "bls_wallet_count_prompt")${NC}"
    read -p "> " WALLET_COUNT

    if ! [[ "$WALLET_COUNT" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${RED}$(t "bls_invalid_number")${NC}"
        return 1
    fi

    # 3. Получение feeRecipient из keystore.json
    local KEYSTORE_FILE="$HOME/aztec/config/keystore.json"
    if [ ! -f "$KEYSTORE_FILE" ]; then
        echo -e "${RED}$(t "bls_keystore_not_found")${NC}"
        return 1
    fi

    # Извлекаем feeRecipient из первого валидатора
    local FEE_RECIPIENT_ADDRESS
    FEE_RECIPIENT_ADDRESS=$(jq -r '.validators[0].feeRecipient' "$KEYSTORE_FILE" 2>/dev/null)

    if [ -z "$FEE_RECIPIENT_ADDRESS" ] || [ "$FEE_RECIPIENT_ADDRESS" = "null" ]; then
        echo -e "${RED}$(t "bls_fee_recipient_not_found")${NC}"
        return 1
    fi

    echo -e "${GREEN}Found feeRecipient: $FEE_RECIPIENT_ADDRESS${NC}"

    # 4. Генерация BLS ключей
    echo -e "\n${BLUE}$(t "bls_generating_keys")${NC}"

    local BLS_OUTPUT_FILE="$HOME/aztec/bls.json"
    local BLS_FILTERED_PK_FILE="$HOME/aztec/bls-filtered-pk.json"
    local BLS_ETHWALLET_FILE="$HOME/aztec/bls-ethwallet.json"

    # Выполнение команды генерации
    echo -e "${YELLOW}Running command: aztec validator-keys new... Wait until process will not finished${NC}"

    if aztec validator-keys new \
        --fee-recipient "$FEE_RECIPIENT_ADDRESS" \
        --mnemonic "$MNEMONIC" \
        --count "$WALLET_COUNT" \
        --file "bls.json" \
        --data-dir "$HOME/aztec/"; then

        echo -e "${GREEN}$(t "bls_generation_success")${NC}"
        echo -e "${YELLOW}↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓${NC}"
        echo -e "${YELLOW}$(t "bls_public_save_attention")${NC}"
        echo -e "${YELLOW}↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑${NC}"
    else
        echo -e "${RED}$(t "bls_generation_failed")${NC}"
        return 1
    fi

    # 5. Проверка существования сгенерированного файла
    if [ ! -f "$BLS_OUTPUT_FILE" ]; then
        echo -e "${RED}$(t "bls_file_not_found")${NC}"
        return 1
    fi

    echo -e "${GREEN}✅ Generated BLS file: $BLS_OUTPUT_FILE${NC}"

    # 6. Получаем адреса валидаторов из keystore.json
    echo -e "\n${BLUE}$(t "bls_searching_matches")${NC}"

    # Извлекаем адреса валидаторов из keystore.json в правильном порядке
    local KEYSTORE_VALIDATOR_ADDRESSES=()
    while IFS= read -r address; do
        if [ -n "$address" ] && [ "$address" != "null" ]; then
            KEYSTORE_VALIDATOR_ADDRESSES+=("${address,,}")
        fi
    done < <(jq -r '.validators[].attester.eth' "$KEYSTORE_FILE" 2>/dev/null)

    if [ ${#KEYSTORE_VALIDATOR_ADDRESSES[@]} -eq 0 ]; then
        echo -e "${RED}No validator addresses found in keystore.json${NC}"
        return 1
    fi

    echo -e "${GREEN}Found ${#KEYSTORE_VALIDATOR_ADDRESSES[@]} validators in keystore.json${NC}"

    # 7. Создаем bls-ethwallet.json с добавленными eth адресами
    echo -e "\n${BLUE}=== Creating temp bls-ethwallet.json with ETH addresses ===${NC}"

    # Временный файл для преобразованного JSON
    local TEMP_ETHWALLET=$(mktemp)

    # Читаем исходный bls.json и добавляем eth адреса
    if jq '.validators[]' "$BLS_OUTPUT_FILE" > /dev/null 2>&1; then
        # Создаем новый JSON с добавленными адресами
        local VALIDATORS_WITH_ADDRESSES=()

        while IFS= read -r validator; do
            local PRIVATE_KEY=$(echo "$validator" | jq -r '.attester.eth')
            local BLS_KEY=$(echo "$validator" | jq -r '.attester.bls')

            # Генерируем eth адрес из приватного ключа
            local ETH_ADDRESS=$(cast wallet address --private-key "$PRIVATE_KEY" 2>/dev/null | tr '[:upper:]' '[:lower:]')

            if [ -n "$ETH_ADDRESS" ]; then
                # Создаем новый объект валидатора с добавленным адресом
                local NEW_VALIDATOR=$(jq -n \
                    --arg priv "$PRIVATE_KEY" \
                    --arg bls "$BLS_KEY" \
                    --arg addr "$ETH_ADDRESS" \
                    '{
                        "attester": {
                            "eth": $priv,
                            "bls": $bls,
                            "address": $addr
                        },
                        "feeRecipient": "'"$FEE_RECIPIENT_ADDRESS"'"
                    }')
                VALIDATORS_WITH_ADDRESSES+=("$NEW_VALIDATOR")
            else
                echo -e "${RED}Error: Failed to generate address for private key${NC}"
            fi
        done < <(jq -c '.validators[]' "$BLS_OUTPUT_FILE")

        # Собираем финальный JSON
        if [ ${#VALIDATORS_WITH_ADDRESSES[@]} -gt 0 ]; then
            printf '{\n  "schemaVersion": 1,\n  "validators": [\n' > "$TEMP_ETHWALLET"
            for i in "${!VALIDATORS_WITH_ADDRESSES[@]}"; do
                if [ $i -gt 0 ]; then
                    printf ",\n" >> "$TEMP_ETHWALLET"
                fi
                jq -c . <<< "${VALIDATORS_WITH_ADDRESSES[$i]}" >> "$TEMP_ETHWALLET"
            done
            printf '\n  ]\n}' >> "$TEMP_ETHWALLET"

            mv "$TEMP_ETHWALLET" "$BLS_ETHWALLET_FILE"
            echo -e "${GREEN}✅ Created temp bls-ethwallet.json with ${#VALIDATORS_WITH_ADDRESSES[@]} validators${NC}"
        else
            echo -e "${RED}Error: No validators processed${NC}"
            rm -f "$TEMP_ETHWALLET"
            return 1
        fi
    else
        echo -e "${RED}Error: Invalid JSON format in $BLS_OUTPUT_FILE${NC}"
        return 1
    fi

    # 8. Создаем bls-filtered-pk.json в порядке keystore.json через jq (без разбора по "|" и с корректным экранированием)
    echo -e "\n${BLUE}=== Creating final bls-filtered-pk.json in keystore.json order ===${NC}"

    # Формируем JSON-массив адресов в порядке keystore (lowercase для сопоставления)
    local ADDRESSES_JSON
    ADDRESSES_JSON=$(printf '%s\n' "${KEYSTORE_VALIDATOR_ADDRESSES[@]}" | jq -R . | jq -s .)

    # Собираем bls-filtered-pk.json через jq: для каждого адреса keystore берём соответствующего валидатора из bls-ethwallet
    # (attester.eth = приватный ETH, attester.bls = приватный BLS — подставляются напрямую из источника без разделителей)
    if ! jq --argjson addresses "$ADDRESSES_JSON" --arg feeRecipient "$FEE_RECIPIENT_ADDRESS" '
        .validators as $validators |
        [
            $addresses[] | ascii_downcase as $addr |
            ($validators[] | select((.attester.address | ascii_downcase) == $addr)) // empty
        ] |
        map({
            attester: { eth: .attester.eth, bls: .attester.bls },
            feeRecipient: $feeRecipient
        }) |
        { schemaVersion: 1, validators: . }
    ' "$BLS_ETHWALLET_FILE" > "$BLS_FILTERED_PK_FILE"; then
        echo -e "${RED}Error: Failed to build bls-filtered-pk.json with jq${NC}"
        rm -f "$BLS_OUTPUT_FILE" "$BLS_ETHWALLET_FILE"
        return 1
    fi

    local MATCH_COUNT
    MATCH_COUNT=$(jq -r '.validators | length' "$BLS_FILTERED_PK_FILE")

    # Предупреждение о несовпавших адресах (адрес есть в keystore, но нет в bls-ethwallet)
    for keystore_address in "${KEYSTORE_VALIDATOR_ADDRESSES[@]}"; do
        if ! jq -e --arg addr "$keystore_address" '
            [.validators[] | .attester.address | ascii_downcase] | index($addr) != null
        ' "$BLS_ETHWALLET_FILE" > /dev/null 2>&1; then
            echo -e "${YELLOW}⚠️ No matching keys found for address: $keystore_address${NC}"
        fi
    done

    if [ "$MATCH_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✅ BLS keys file created with validators in keystore.json order${NC}"

        # Очистка временных файлов
        rm -f "$BLS_OUTPUT_FILE" "$BLS_ETHWALLET_FILE"

        echo -e "${GREEN}$(printf "$(t "bls_matches_found")" "$MATCH_COUNT")${NC}"
        echo -e "${GREEN}📁 Private keys saved to: $BLS_FILTERED_PK_FILE${NC}"

        return 0
    else
        echo -e "${RED}$(t "bls_no_matches")${NC}"

        # Очистка временных файлов
        rm -f "$BLS_OUTPUT_FILE" "$BLS_ETHWALLET_FILE"
        return 1
    fi
}

# === New operator method для новой структуры keystore.json ===
generate_bls_new_operator_method() {
    echo -e "\n${BLUE}=== $(t "bls_new_operator_title") ===${NC}"

    # Запрос данных старого валидатора
    echo -e "${CYAN}$(t "bls_old_validator_info")${NC}"
    read -sp "$(t "bls_old_private_key_prompt") " PRIVATE_KEYS_INPUT && echo

    # Обработка нескольких приватных ключей через запятую
    local OLD_SEQUENCER_KEYS
    IFS=',' read -ra OLD_SEQUENCER_KEYS <<< "$PRIVATE_KEYS_INPUT"

    if [ ${#OLD_SEQUENCER_KEYS[@]} -eq 0 ]; then
        echo -e "${RED}$(t "bls_no_private_keys")${NC}"
        return 1
    fi

    echo -e "${GREEN}$(t "bls_found_private_keys") ${#OLD_SEQUENCER_KEYS[@]}${NC}"

    # Генерируем адреса для старых валидаторов
    local OLD_VALIDATOR_ADDRESSES=()
    echo -e "\n${BLUE}Generating addresses for old validators...${NC}"
    for private_key in "${OLD_SEQUENCER_KEYS[@]}"; do
        local old_address=$(cast wallet address --private-key "$private_key" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        if [ -n "$old_address" ]; then
            OLD_VALIDATOR_ADDRESSES+=("$old_address")
            echo -e "  ${GREEN}✓${NC} $old_address"
        else
            echo -e "  ${RED}✗${NC} Failed to generate address for key: ${private_key:0:10}..."
            OLD_VALIDATOR_ADDRESSES+=("unknown")
        fi
    done

    # Получаем порядок адресов из keystore.json
    local KEYSTORE_FILE="$HOME/aztec/config/keystore.json"
    if [ ! -f "$KEYSTORE_FILE" ]; then
        echo -e "${RED}$(t "bls_keystore_not_found")${NC}"
        return 1
    fi

    # Извлекаем адреса валидаторов из новой структуры keystore.json
    local KEYSTORE_VALIDATOR_ADDRESSES=()
    while IFS= read -r address; do
        if [ -n "$address" ] && [ "$address" != "null" ]; then
            KEYSTORE_VALIDATOR_ADDRESSES+=("${address,,}")
        fi
    done < <(jq -r '.validators[].attester.eth' "$KEYSTORE_FILE" 2>/dev/null)

    if [ ${#KEYSTORE_VALIDATOR_ADDRESSES[@]} -eq 0 ]; then
        echo -e "${RED}No validator addresses found in keystore.json${NC}"
        return 1
    fi

    echo -e "${GREEN}Found ${#KEYSTORE_VALIDATOR_ADDRESSES[@]} validators in keystore.json${NC}"

    # Получаем feeRecipient из keystore.json
    local FEE_RECIPIENT_ADDRESS
    FEE_RECIPIENT_ADDRESS=$(jq -r '.validators[0].feeRecipient' "$KEYSTORE_FILE" 2>/dev/null)

    if [ -z "$FEE_RECIPIENT_ADDRESS" ] || [ "$FEE_RECIPIENT_ADDRESS" = "null" ]; then
        echo -e "${RED}$(t "bls_fee_recipient_not_found")${NC}"
        return 1
    fi

    echo -e "${GREEN}Found feeRecipient: $FEE_RECIPIENT_ADDRESS${NC}"

    # Используем стандартный RPC URL вместо запроса у пользователя
    local RPC_URL="https://ethereum-sepolia-rpc.publicnode.com"
    echo -e "${GREEN}$(t "bls_starting_generation")${NC}"
    echo -e "${CYAN}Using default RPC: $RPC_URL${NC}"

    # Создаем папку для временных файлов
    local TEMP_DIR=$(mktemp -d)

    # Ассоциативные массивы для хранения ключей по адресам
    declare -A OLD_PRIVATE_KEYS_MAP
    declare -A NEW_ETH_PRIVATE_KEYS_MAP
    declare -A NEW_BLS_KEYS_MAP
    declare -A NEW_ETH_ADDRESSES_MAP

    # Заполняем маппинг старых приватных ключей по адресам
    for ((i=0; i<${#OLD_VALIDATOR_ADDRESSES[@]}; i++)); do
        if [ "${OLD_VALIDATOR_ADDRESSES[$i]}" != "unknown" ]; then
            OLD_PRIVATE_KEYS_MAP["${OLD_VALIDATOR_ADDRESSES[$i]}"]="${OLD_SEQUENCER_KEYS[$i]}"
        fi
    done

    echo -e "${YELLOW}$(t "bls_ready_to_generate")${NC}"

    # Генерация отдельных ключей для каждого валидатора
    for ((i=0; i<${#OLD_SEQUENCER_KEYS[@]}; i++)); do
        echo -e "\n${BLUE}Generating keys for validator $((i+1))/${#OLD_SEQUENCER_KEYS[@]}...${NC}"

        # Удаляем старый файл и генерируем новые ключи
        rm -f ~/.aztec/keystore/key1.json
        read -p "$(t "bls_press_enter_to_generate") " -r

        # Генерация новых ключей с правильным feeRecipient
        if ! aztec validator-keys new --fee-recipient "$FEE_RECIPIENT_ADDRESS"; then
            echo -e "${RED}$(t "bls_generation_failed")${NC}"
            rm -rf "$TEMP_DIR"
            return 1
        fi

        # Извлечение новых ключей
        local KEYSTORE_FILE=~/.aztec/keystore/key1.json
        if [ ! -f "$KEYSTORE_FILE" ]; then
            echo -e "${RED}$(t "bls_keystore_not_found")${NC}"
            rm -rf "$TEMP_DIR"
            return 1
        fi

        local NEW_ETH_PRIVATE_KEY=$(jq -r '.validators[0].attester.eth' "$KEYSTORE_FILE" 2>/dev/null)
        local BLS_ATTESTER_PRIV_KEY=$(jq -r '.validators[0].attester.bls' "$KEYSTORE_FILE" 2>/dev/null)
        local ETH_ATTESTER_ADDRESS=$(cast wallet address --private-key "$NEW_ETH_PRIVATE_KEY" 2>/dev/null | tr '[:upper:]' '[:lower:]')

        if [ -z "$NEW_ETH_PRIVATE_KEY" ] || [ "$NEW_ETH_PRIVATE_KEY" = "null" ] ||
           [ -z "$BLS_ATTESTER_PRIV_KEY" ] || [ "$BLS_ATTESTER_PRIV_KEY" = "null" ]; then
            echo -e "${RED}$(t "bls_key_extraction_failed")${NC}"
            rm -rf "$TEMP_DIR"
            return 1
        fi

        # Сохраняем ключи в ассоциативные массивы по старому адресу
        local OLD_ADDRESS="${OLD_VALIDATOR_ADDRESSES[$i]}"
        if [ "$OLD_ADDRESS" != "unknown" ]; then
            NEW_ETH_PRIVATE_KEYS_MAP["$OLD_ADDRESS"]="$NEW_ETH_PRIVATE_KEY"
            NEW_BLS_KEYS_MAP["$OLD_ADDRESS"]="$BLS_ATTESTER_PRIV_KEY"
            NEW_ETH_ADDRESSES_MAP["$OLD_ADDRESS"]="$ETH_ATTESTER_ADDRESS"
        fi

        # Показываем пользователю новые ключи
        echo -e "${GREEN}✅ Keys generated for validator $((i+1))${NC}"
        echo -e "   - $(t "bls_new_eth_private_key"): ${NEW_ETH_PRIVATE_KEY:0:20}..."
        echo -e "   - $(t "bls_new_bls_private_key"): ${BLS_ATTESTER_PRIV_KEY:0:20}..."
        echo -e "   - $(t "bls_new_public_address"): $ETH_ATTESTER_ADDRESS"

        # Сохраняем копию файла для каждого валидатора
        cp "$KEYSTORE_FILE" "$TEMP_DIR/keystore_validator_$((i+1)).json"
    done

    echo ""

    # Сохраняем ключи в файл для совместимости с stake_validators
    local BLS_PK_FILE="$HOME/aztec/bls-filtered-pk.json"

    # Создаем массив валидаторов в порядке keystore.json
    local VALIDATORS_JSON=""
    local MATCH_COUNT=0

    for keystore_address in "${KEYSTORE_VALIDATOR_ADDRESSES[@]}"; do
        if [ -n "${OLD_PRIVATE_KEYS_MAP[$keystore_address]}" ] &&
           [ -n "${NEW_ETH_PRIVATE_KEYS_MAP[$keystore_address]}" ] &&
           [ -n "${NEW_BLS_KEYS_MAP[$keystore_address]}" ] &&
           [ -n "${NEW_ETH_ADDRESSES_MAP[$keystore_address]}" ]; then

            ((MATCH_COUNT++))

            if [ -n "$VALIDATORS_JSON" ]; then
                VALIDATORS_JSON+=","
            fi

            VALIDATORS_JSON+=$(cat <<EOF
    {
      "attester": {
        "eth": "${OLD_PRIVATE_KEYS_MAP[$keystore_address]}",
        "bls": "${NEW_BLS_KEYS_MAP[$keystore_address]}",
        "old_address": "$keystore_address"
      },
      "feeRecipient": "$FEE_RECIPIENT_ADDRESS",
      "new_operator_info": {
        "eth_private_key": "${NEW_ETH_PRIVATE_KEYS_MAP[$keystore_address]}",
        "bls_private_key": "${NEW_BLS_KEYS_MAP[$keystore_address]}",
        "eth_address": "${NEW_ETH_ADDRESSES_MAP[$keystore_address]}",
        "rpc_url": "$RPC_URL"
      }
    }
EOF
            )
        else
            echo -e "${YELLOW}⚠️ No matching keys found for address: $keystore_address${NC}"
        fi
    done

    if [ $MATCH_COUNT -eq 0 ]; then
        echo -e "${RED}No matching validators found between provided keys and keystore.json${NC}"
        rm -rf "$TEMP_DIR"
        return 1
    fi

    cat > "$BLS_PK_FILE" << EOF
{
  "schemaVersion": 1,
  "validators": [
$VALIDATORS_JSON
  ]
}
EOF

    # Очищаем временную папку
    rm -rf "$TEMP_DIR"

    # Показываем сводную информацию
    echo -e "${GREEN}✅ $(t "bls_keys_saved_success")${NC}"
    echo -e "\n${BLUE}=== Summary of generated validators (in keystore.json order) ===${NC}"

    for keystore_address in "${KEYSTORE_VALIDATOR_ADDRESSES[@]}"; do
        if [ -n "${OLD_PRIVATE_KEYS_MAP[$keystore_address]}" ] &&
           [ -n "${NEW_ETH_ADDRESSES_MAP[$keystore_address]}" ]; then
            echo -e "${CYAN}Validator: $keystore_address${NC}"
            echo -e "  Old address: $keystore_address"
            echo -e "  New address: ${NEW_ETH_ADDRESSES_MAP[$keystore_address]}"
            echo -e "  Funding required: ${NEW_ETH_ADDRESSES_MAP[$keystore_address]}"
            echo ""
        fi
    done

    echo -e "${YELLOW}$(t "bls_next_steps")${NC}"
    echo -e "   1. $(t "bls_send_eth_step")"
    echo -e "   2. $(t "bls_run_approve_step")"
    echo -e "   3. $(t "bls_run_stake_step")"

    return 0
}
