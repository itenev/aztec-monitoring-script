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

    # Парсим JSON и заполняем массивы
    parse_error_definitions() {
        # Используем jq для парсинга JSON, если установлен
        if command -v jq >/dev/null; then
            while IFS= read -r line; do
                pattern=$(jq -r '.pattern' <<< "$line")
                message=$(jq -r '.message' <<< "$line")
                solution=$(jq -r '.solution' <<< "$line")
                critical_errors["$pattern"]="$message"
                error_solutions["$pattern"]="$solution"
            done < <(jq -c '.errors[]' "$ERROR_DEFINITIONS_FILE")
        else
            # Простой парсинг без jq (ограниченная функциональность)
            # Извлекаем содержимое массива errors из новой структуры JSON
            errors_section=$(sed -n '/"errors":\s*\[/,/\]/{ /"errors":\s*\[/d; /\]/d; p; }' "$ERROR_DEFINITIONS_FILE" 2>/dev/null)

            # Парсим объекты из массива errors
            current_obj=""
            brace_level=0

            while IFS= read -r line || [ -n "$line" ]; do
                # Удаляем ведущие/замыкающие пробелы и запятые
                line=$(echo "$line" | sed 's/^[[:space:],]*//;s/[[:space:],]*$//')

                # Пропускаем пустые строки
                [ -z "$line" ] && continue

                # Подсчитываем фигурные скобки в строке
                open_count=$(echo "$line" | tr -cd '{' | wc -c)
                close_count=$(echo "$line" | tr -cd '}' | wc -c)
                brace_level=$((brace_level + open_count - close_count))

                # Добавляем строку к текущему объекту
                if [ -z "$current_obj" ]; then
                    current_obj="$line"
                else
                    current_obj="${current_obj} ${line}"
                fi

                # Когда объект завершён (brace_level вернулся к 0 и есть закрывающая скобка)
                if [ "$brace_level" -eq 0 ] && [ "$close_count" -gt 0 ]; then
                    # Извлекаем pattern, message и solution из объекта
                    pattern=$(echo "$current_obj" | sed -n 's/.*"pattern"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
                    message=$(echo "$current_obj" | sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
                    solution=$(echo "$current_obj" | sed -n 's/.*"solution"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

                    if [ -n "$pattern" ] && [ -n "$message" ] && [ -n "$solution" ]; then
                        critical_errors["$pattern"]="$message"
                        error_solutions["$pattern"]="$solution"
                    fi

                    current_obj=""
                fi
            done <<< "$errors_section"
        fi
    }

    # Инициализируем массивы для ошибок и решений
    declare -A critical_errors
    declare -A error_solutions

    # Загружаем и парсим определения ошибок
    if download_error_definitions; then
        parse_error_definitions
    else
        # Используем встроенные ошибки по умолчанию если не удалось загрузить
        critical_errors=(
            ["ERROR: cli Error: World state trees are out of sync, please delete your data directory and re-sync"]="World state trees are out of sync - node needs resync"
        )
        error_solutions=(
            ["ERROR: cli Error: World state trees are out of sync, please delete your data directory and re-sync"]="1. Stop the node container. Use option 14\n2. Delete data from the folder: sudo rm -rf $HOME/.aztec/testnet/data/\n3. Run the container. Use option 13"
        )
    fi

    echo -e "\n${BLUE}$(t "search_container")${NC}"
    container_id=$(docker ps --format "{{.ID}} {{.Names}}" \
                   | grep aztec | grep -vE 'watchtower|otel|prometheus|grafana' | head -n 1 | awk '{print $1}')

    if [ -z "$container_id" ]; then
        echo -e "\n${RED}$(t "container_not_found")${NC}"
        return
    fi
    echo -e "\n${GREEN}$(t "container_found") $container_id${NC}"

    echo -e "\n${BLUE}$(t "get_block")${NC}"
    block_hex=$(cast call "$contract_address" "getPendingBlockNumber()" --rpc-url "$rpc_url" 2>/dev/null)
    [ -z "$block_hex" ] && block_hex=$(cast call "$contract_address" "getPendingCheckpointNumber()" --rpc-url "$rpc_url" 2>/dev/null)
    if [ -z "$block_hex" ]; then
        echo -e "\n${RED}$(t "block_error")${NC}"
        return
    fi
    block_number=$((16#${block_hex#0x}))
    echo -e "\n${GREEN}$(t "current_block") $block_number${NC}"

    # Получаем логи контейнера
    clean_logs=$(docker logs "$container_id" --tail 20000 2>&1 | sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g')

    # Проверяем на наличие критических ошибок
    for error_pattern in "${!critical_errors[@]}"; do
        if echo "$clean_logs" | grep -q "$error_pattern"; then
            echo -e "\n${RED}$(t "critical_error_found")${NC}"
            echo -e "${YELLOW}$(t "error_prefix") ${critical_errors[$error_pattern]}${NC}"

            # Выводим решение для данной ошибки
            if [ -n "${error_solutions[$error_pattern]}" ]; then
                echo -e "\n${BLUE}$(t "solution_prefix")${NC}"
                echo -e "${error_solutions[$error_pattern]}"
            fi

            return
        fi
    done

    temp_file=$(mktemp)
    {
        echo "$clean_logs" | tac | grep -m1 'Sequencer sync check succeeded' >"$temp_file" 2>/dev/null
        if [ ! -s "$temp_file" ]; then
            echo "$clean_logs" | tac | grep -m1 -iE 'Downloaded L2 block|Downloaded checkpoint|"checkpointNumber":[0-9]+' >"$temp_file" 2>/dev/null
        fi
    } &
    search_pid=$!
    spinner $search_pid
    wait $search_pid

    latest_log_line=$(<"$temp_file")
    rm -f "$temp_file"

    if [ -z "$latest_log_line" ]; then
        echo -e "\n${RED}$(t "agent_no_block_in_logs")${NC}"
        return
    fi

    if grep -q 'Sequencer sync check succeeded' <<<"$latest_log_line"; then
        log_block_number=$(echo "$latest_log_line" \
            | grep -o '"worldState":{"number":[0-9]\+' \
            | grep -o '[0-9]\+$')
    else
        log_block_number=$(echo "$latest_log_line" \
            | grep -oE '"checkpointNumber":[0-9]+|"blockNumber":[0-9]+' \
            | head -n1 | grep -oE '[0-9]+')
    fi

    if [ -z "$log_block_number" ]; then
        echo -e "\n${RED}$(t "log_block_extract_failed")${NC}"
        echo "$latest_log_line"
        return
    fi
    echo -e "\n${BLUE}$(t "log_block_number") $log_block_number${NC}"

    if [ "$log_block_number" -eq "$block_number" ]; then
        echo -e "\n${GREEN}$(t "node_ok")${NC}"
    else
        printf -v message "$(t "log_behind_details")" "$log_block_number" "$block_number"
        echo -e "\n${YELLOW}${message}${NC}"
        echo -e "\n${BLUE}$(t "log_line_example")${NC}"
        echo "$latest_log_line"
    fi
}
