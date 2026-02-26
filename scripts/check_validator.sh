# === Validator check module ===
check_validator_queue(){
    local validator_addresses=("$@")
    local network="${NETWORK:-$(get_network_for_validator)}"
    local results=()
    local found_count=0
    local not_found_count=0

    # Выбор адресов в зависимости от сети
    local QUEUE_URL
    if [[ "$network" == "mainnet" ]]; then
        QUEUE_URL="https://dashtec.xyz/api/sequencers/queue"
    else
        QUEUE_URL="https://${network}.dashtec.xyz/api/sequencers/queue"
    fi

    echo -e "${YELLOW}$(t "fetching_queue")${NC}"
    echo -e "${GRAY}Checking ${#validator_addresses[@]} validators in queue...${NC}"
    local temp_file
    temp_file=$(mktemp)

    # Функция для отправки уведомления об ошибке API
    send_api_error_notification() {
        local error_type="$1"
        local validator_address="$2"
        local message="🚨 *Dashtec API Error*

🔧 *Error Type:* $error_type
🔍 *Validator:* \`${validator_address:-"Batch check"}\`
⏰ *Time:* $(date '+%d.%m.%Y %H:%M UTC')
⚠️ *Issue:* Possible problems with Dashtec API

📞 *Contact developer:* https://t.me/+zEaCtoXYYwIyZjQ0"

        if [ -n "${TELEGRAM_BOT_TOKEN-}" ] && [ -n "${TELEGRAM_CHAT_ID-}" ]; then
            curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
                -d chat_id="$TELEGRAM_CHAT_ID" -d text="$message" -d parse_mode="Markdown" >/dev/null 2>&1
        fi
    }

    check_single_validator(){
        local validator_address=$1
        local temp_file=$2
        local search_address_lower=${validator_address,,}
        local search_url="${QUEUE_URL}?page=1&limit=10&search=${search_address_lower}"
        local response_data
        response_data="$(cffi_http_get "$search_url" "$network")"

        if [ -z "$response_data" ]; then
            echo "$validator_address|ERROR|Empty API response" >> "$temp_file"
            send_api_error_notification "Empty response" "$validator_address"
            return 1
        fi

        if ! jq -e . >/dev/null 2>&1 <<<"$response_data"; then
            echo "$validator_address|ERROR|Invalid JSON response" >> "$temp_file"
            send_api_error_notification "Invalid JSON" "$validator_address"
            return 1
        fi

        # Проверяем статус ответа
        local status=$(echo "$response_data" | jq -r '.status')
        if [ "$status" != "ok" ]; then
            echo "$validator_address|ERROR|API returned non-ok status: $status" >> "$temp_file"
            send_api_error_notification "Non-OK status: $status" "$validator_address"
            return 1
        fi

        local validator_info
        validator_info=$(echo "$response_data" | jq -r ".validatorsInQueue[] | select(.address? | ascii_downcase == \"$search_address_lower\")")
        local filtered_count
        filtered_count=$(echo "$response_data" | jq -r '.filteredCount // 0')

        if [ -n "$validator_info" ] && [ "$filtered_count" -gt 0 ]; then
            local position withdrawer queued_at tx_hash index
            position=$(echo "$validator_info" | jq -r '.position')
            withdrawer=$(echo "$validator_info" | jq -r '.withdrawerAddress')
            queued_at=$(echo "$validator_info" | jq -r '.queuedAt')
            tx_hash=$(echo "$validator_info" | jq -r '.transactionHash')
            index=$(echo "$validator_info" | jq -r '.index')
            echo "$validator_address|FOUND|$position|$withdrawer|$queued_at|$tx_hash|$index" >> "$temp_file"
        else
            echo "$validator_address|NOT_FOUND||" >> "$temp_file"
        fi
    }

    local pids=()
    for validator_address in "${validator_addresses[@]}"; do
        check_single_validator "$validator_address" "$temp_file" &
        pids+=($!)
    done

    # Ожидаем завершения всех процессов
    local api_errors=0
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || ((api_errors++))
    done

    # Если все запросы завершились с ошибкой API, отправляем общее уведомление
    if [ $api_errors -eq ${#validator_addresses[@]} ] && [ ${#validator_addresses[@]} -gt 0 ]; then
        send_api_error_notification "All API requests failed" "Batch check"
    fi

    # Обрабатываем результаты
    while IFS='|' read -r address status position withdrawer queued_at tx_hash index; do
        case "$status" in
            FOUND) results+=("FOUND|$address|$position|$withdrawer|$queued_at|$tx_hash|$index"); found_count=$((found_count+1));;
            NOT_FOUND) results+=("NOT_FOUND|$address"); not_found_count=$((not_found_count+1));;
            ERROR) results+=("ERROR|$address|$position"); not_found_count=$((not_found_count+1));;
        esac
    done < "$temp_file"
    rm -f "$temp_file"

    echo -e "\n${CYAN}=== Queue Check Results ===${NC}"
    echo -e "Found in queue: ${GREEN}$found_count${NC}"
    echo -e "Not found: ${RED}$not_found_count${NC}"
    echo -e "Total checked: ${BOLD}${#validator_addresses[@]}${NC}"

    if [ $found_count -gt 0 ]; then
        echo -e "\n${GREEN}Validators found in queue:${NC}"
        for result in "${results[@]}"; do
            IFS='|' read -r status address position withdrawer queued_at tx_hash index <<<"$result"
            if [ "$status" == "FOUND" ]; then
                local formatted_date
                formatted_date=$(date -d "$queued_at" '+%d.%m.%Y %H:%M UTC' 2>/dev/null || echo "$queued_at")
                echo -e "  ${CYAN}• ${address}${NC}"
                echo -e "    ${BOLD}Position:${NC} $position"
                echo -e "    ${BOLD}Withdrawer:${NC} $withdrawer"
                echo -e "    ${BOLD}Queued at:${NC} $formatted_date"
                echo -e "    ${BOLD}Tx Hash:${NC} $tx_hash"
                echo -e "    ${BOLD}Index:${NC} $index"
            fi
        done
    fi

    if [ $not_found_count -gt 0 ]; then
        echo -e "\n${RED}Validators not found in queue:${NC}"
        for result in "${results[@]}"; do
            IFS='|' read -r status address error_msg <<<"$result"
            if [ "$status" == "NOT_FOUND" ]; then
                echo -e "  ${RED}• ${address}${NC}"
            elif [ "$status" == "ERROR" ]; then
                echo -e "  ${RED}• ${address} (Error: ${error_msg})${NC}"
            fi
        done
    fi

    # Устанавливаем глобальные переменные с результатами поиска
    QUEUE_FOUND_COUNT=$found_count
    QUEUE_FOUND_ADDRESSES=()

    # Заполняем массив найденными адресами
    for result in "${results[@]}"; do
        IFS='|' read -r status address position withdrawer queued_at tx_hash index <<<"$result"
        if [ "$status" == "FOUND" ]; then
            QUEUE_FOUND_ADDRESSES+=("$address")
        fi
    done

    if [ $found_count -gt 0 ]; then return 0; else return 1; fi
}

# Вспомогательная функция для проверки одного валидатора (для обратной совместимости)
check_single_validator_queue() {
    local validator_address=$1
    check_validator_queue "$validator_address"
}

create_monitor_script(){
    local validator_address=$1
    local network=$2
    local MONITOR_DIR=$3
    local QUEUE_URL=$4
    local validator_address=$(echo "$validator_address" | xargs)
    local normalized_address=${validator_address,,}
    local script_name="monitor_${normalized_address:2}.sh"
    local log_file="$MONITOR_DIR/monitor_${normalized_address:2}.log"
    local position_file="$MONITOR_DIR/last_position_${normalized_address:2}.txt"
    if [ -f "$MONITOR_DIR/$script_name" ]; then
        echo -e "${YELLOW}$(t "notification_exists")${NC}"
        return
    fi
    mkdir -p "$MONITOR_DIR"

    local start_message="🎯 *Queue Monitoring Started*

🔹 *Address:* \`$validator_address\`
⏰ *Monitoring started at:* $(date '+%d.%m.%Y %H:%M UTC')
📋 *Check frequency:* Hourly
🔔 *Notifications:* Position changes"

    if [ -n "${TELEGRAM_BOT_TOKEN-}" ] && [ -n "${TELEGRAM_CHAT_ID-}" ]; then
        curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            -d chat_id="$TELEGRAM_CHAT_ID" -d text="$start_message" -d parse_mode="Markdown" >/dev/null 2>&1
    fi

    cat > "$MONITOR_DIR/$script_name" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

VALIDATOR_ADDRESS="__ADDR__"
NETWORK="__NETWORK__"
MONITOR_DIR="__MDIR__"
LAST_POSITION_FILE="__POSFILE__"
LOG_FILE="__LOGFILE__"
TELEGRAM_BOT_TOKEN="__TBOT__"
TELEGRAM_CHAT_ID="__TCHAT__"

CURL_CONNECT_TIMEOUT=15
CURL_MAX_TIME=45
API_RETRY_DELAY=30
MAX_RETRIES=2

mkdir -p "$MONITOR_DIR"
log_message(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

# Ensure curl_cffi
python3 - <<'PY' >/dev/null 2>&1 || exit 1
try:
    import pkgutil
    assert pkgutil.find_loader("curl_cffi")
except Exception:
    raise SystemExit(1)
print("OK")
PY

send_telegram(){
    local message="$1"
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        log_message "No Telegram tokens"
        return 1
    fi
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" -d text="$message" -d parse_mode="Markdown" >/dev/null
}

format_date(){
    local iso_date="$1"
    if [[ "$iso_date" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2}) ]]; then
        echo "${BASH_REMATCH[3]}.${BASH_REMATCH[2]}.${BASH_REMATCH[1]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]} UTC"
    else
        echo "$iso_date"
    fi
}

cffi_http_get(){
  local url="$1"
  python3 - "$url" "$NETWORK" <<'PY'
import sys
from curl_cffi import requests
u = sys.argv[1]
network = sys.argv[2]

# Формируем origin и referer в зависимости от сети
if network == "mainnet":
    base_url = "https://dashtec.xyz"
else:
    base_url = f"https://{network}.dashtec.xyz"

headers = {
    "accept": "application/json, text/plain, */*",
    "origin": base_url,
    "referer": base_url + "/"
}
try:
    r = requests.get(u, headers=headers, impersonate="chrome131", timeout=30)
    ct = (r.headers.get("content-type") or "").lower()
    txt = r.text
    if "application/json" in ct:
        print(txt)
    else:
        i, j = txt.find("{"), txt.rfind("}")
        print(txt[i:j+1] if i!=-1 and j!=-1 and j>i else txt)
except Exception as e:
    print(f'{{"error": "Request failed: {e}"}}')
PY
}

monitor_position(){
    log_message "Start monitor_position for $VALIDATOR_ADDRESS"
    local last_position=""
    [[ -f "$LAST_POSITION_FILE" ]] && last_position=$(cat "$LAST_POSITION_FILE")

    # Функция для отправки уведомления об ошибке API в мониторе
    send_monitor_api_error(){
        local error_type="$1"
        local message="🚨 *Dashtec API Error - Monitor*

🔧 *Error Type:* $error_type
🔍 *Validator:* \`$VALIDATOR_ADDRESS\`
⏰ *Time:* $(date '+%d.%m.%Y %H:%M UTC')
⚠️ *Issue:* Possible problems with Dashtec API
📞 *Contact developer:* https://t.me/+zEaCtoXYYwIyZjQ0"

        if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
            curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
                -d chat_id="$TELEGRAM_CHAT_ID" -d text="$message" -d parse_mode="Markdown" >/dev/null
        fi
    }

    # Формируем URL для очереди в зависимости от сети
    local queue_url
    if [[ "$NETWORK" == "mainnet" ]]; then
        queue_url="https://dashtec.xyz/api/sequencers/queue"
    else
        queue_url="https://${NETWORK}.dashtec.xyz/api/sequencers/queue"
    fi

    local search_url="${queue_url}?page=1&limit=10&search=${VALIDATOR_ADDRESS,,}"
    log_message "GET $search_url"
    local response_data; response_data="$(cffi_http_get "$search_url")"

    if [ -z "$response_data" ]; then
        log_message "Empty API response"
        send_monitor_api_error "Empty response"
        return 1
    fi

    # Проверяем наличие ошибки в ответе
    if echo "$response_data" | jq -e 'has("error")' >/dev/null 2>&1; then
        local error_msg=$(echo "$response_data" | jq -r '.error')
        log_message "API request failed: $error_msg"
        send_monitor_api_error "Request failed: $error_msg"
        return 1
    fi

    if ! echo "$response_data" | jq -e . >/dev/null 2>&1; then
        log_message "Invalid JSON response: $response_data"
        send_monitor_api_error "Invalid JSON"
        return 1
    fi

    # Проверяем статус ответа
    local api_status=$(echo "$response_data" | jq -r '.status')
    if [ "$api_status" != "ok" ]; then
        log_message "API returned non-ok status: $api_status"
        send_monitor_api_error "Non-OK status: $api_status"
        return 1
    fi

    local validator_info; validator_info=$(echo "$response_data" | jq -r ".validatorsInQueue[] | select(.address? | ascii_downcase == \"${VALIDATOR_ADDRESS,,}\")")
    local filtered_count; filtered_count=$(echo "$response_data" | jq -r '.filteredCount // 0')

    if [[ -n "$validator_info" && "$filtered_count" -gt 0 ]]; then
        local current_position queued_at withdrawer_address transaction_hash index
        current_position=$(echo "$validator_info" | jq -r '.position')
        queued_at=$(format_date "$(echo "$validator_info" | jq -r '.queuedAt')")
        withdrawer_address=$(echo "$validator_info" | jq -r '.withdrawerAddress')
        transaction_hash=$(echo "$validator_info" | jq -r '.transactionHash')
        index=$(echo "$validator_info" | jq -r '.index')

        if [[ "$last_position" != "$current_position" ]]; then
            local message
            if [[ -n "$last_position" ]]; then
                message="📊 *Validator Position Update*

🔹 *Address:* \`$VALIDATOR_ADDRESS\`
🔄 *Change:* $last_position → $current_position
📅 *Queued since:* $queued_at
🏦 *Withdrawer:* \`$withdrawer_address\`
🔗 *Transaction:* \`$transaction_hash\`
🏷️ *Index:* $index
⏳ *Checked at:* $(date '+%d.%m.%Y %H:%M UTC')"
            else
                message="🎉 *New Validator in Queue*

🔹 *Address:* \`$VALIDATOR_ADDRESS\`
📌 *Initial Position:* $current_position
📅 *Queued since:* $queued_at
🏦 *Withdrawer:* \`$withdrawer_address\`
🔗 *Transaction:* \`$transaction_hash\`
🏷️ *Index:* $index
⏳ *Checked at:* $(date '+%d.%m.%Y %H:%M UTC')"
            fi
            if send_telegram "$message"; then
                log_message "Notification sent"
            else
                log_message "Failed to send notification"
            fi
            echo "$current_position" > "$LAST_POSITION_FILE"
            log_message "Saved new position: $current_position"
        else
            log_message "Position unchanged: $current_position"
        fi
    else
        log_message "Validator not found in queue"
        if [[ -n "$last_position" ]]; then
            # Формируем URL для активного набора в зависимости от сети
            local active_url
            if [[ "$NETWORK" == "mainnet" ]]; then
                active_url="https://dashtec.xyz/api/validators?page=1&limit=10&sortBy=rank&sortOrder=asc&search=${VALIDATOR_ADDRESS,,}"
            else
                active_url="https://${NETWORK}.dashtec.xyz/api/validators?page=1&limit=10&sortBy=rank&sortOrder=asc&search=${VALIDATOR_ADDRESS,,}"
            fi

            log_message "Checking active set: $active_url"
            local active_response; active_response="$(cffi_http_get "$active_url" 2>/dev/null || echo "")"

            if [[ -n "$active_response" ]] && echo "$active_response" | jq -e . >/dev/null 2>&1; then
                local api_status_active=$(echo "$active_response" | jq -r '.status')

                if [[ "$api_status_active" == "ok" ]]; then
                    local active_validator; active_validator=$(echo "$active_response" | jq -r ".validators[] | select(.address? | ascii_downcase == \"${VALIDATOR_ADDRESS,,}\")")

                    if [[ -n "$active_validator" ]]; then
                        # Валидатор найден в активном наборе
                        local status balance rank attestation_success proposal_success
                        status=$(echo "$active_validator" | jq -r '.status')
                        rank=$(echo "$active_validator" | jq -r '.rank')

                        # Формируем ссылку для валидатора в зависимости от сети
                        local validator_link
                        if [[ "$NETWORK" == "mainnet" ]]; then
                            validator_link="https://dashtec.xyz/validators"
                        else
                            validator_link="https://${NETWORK}.dashtec.xyz/validators"
                        fi

                        local message="✅ *Validator Moved to Active Set*

🔹 *Address:* \`$VALIDATOR_ADDRESS\`
🎉 *Status:* $status
🏆 *Rank:* $rank
⌛ *Last Queue Position:* $last_position
🔗 *Validator Link:* $validator_link/$VALIDATOR_ADDRESS
⏳ *Checked at:* $(date '+%d.%m.%Y %H:%M UTC')"
                        send_telegram "$message" && log_message "Active set notification sent"
                    else
                        # Формируем ссылку для очереди в зависимости от сети
                        local queue_link
                        if [[ "$NETWORK" == "mainnet" ]]; then
                            queue_link="https://dashtec.xyz/queue"
                        else
                            queue_link="https://${NETWORK}.dashtec.xyz/queue"
                        fi

                        # Валидатор не найден ни в очереди, ни в активном наборе
                        local message="❌ *Validator Removed from Queue*

🔹 *Address:* \`$VALIDATOR_ADDRESS\`
⌛ *Last Position:* $last_position
⏳ *Checked at:* $(date '+%d.%m.%Y %H:%M UTC')

⚠️ *Possible reasons:*
• Validator was removed from queue
• Validator activation failed
• Technical issue with the validator

📊 Check queue: $queue_link"
                        send_telegram "$message" && log_message "Removal notification sent"
                    fi
                else
                    log_message "Active set API returned non-ok status: $api_status_active"
                    # Формируем ссылку для очереди в зависимости от сети
                    local queue_link
                    if [[ "$NETWORK" == "mainnet" ]]; then
                        queue_link="https://dashtec.xyz/queue"
                    else
                        queue_link="https://${NETWORK}.dashtec.xyz/queue"
                    fi

                    # Не удалось проверить активный набор из-за статуса API
                    local message="❌ *Validator No Longer in Queue*

🔹 *Address:* \`$VALIDATOR_ADDRESS\`
⌛ *Last Position:* $last_position
⏳ *Checked at:* $(date '+%d.%m.%Y %H:%M UTC')

ℹ️ *Note:* Could not verify active set status (API error)
📊 Check status: $queue_link"
                    send_telegram "$message" && log_message "General removal notification sent"
                fi
            else
                # Формируем ссылку для очереди в зависимости от сети
                local queue_link
                if [[ "$NETWORK" == "mainnet" ]]; then
                    queue_link="https://dashtec.xyz/queue"
                else
                    queue_link="https://${NETWORK}.dashtec.xyz/queue"
                fi

                # Не удалось получить ответ от API активного набора
                local message="❌ *Validator No Longer in Queue*

🔹 *Address:* \`$VALIDATOR_ADDRESS\`
⌛ *Last Position:* $last_position
⏳ *Checked at:* $(date '+%d.%m.%Y %H:%M UTC')

ℹ️ *Note:* Could not verify active set status
📊 Check status: $queue_link"
                send_telegram "$message" && log_message "General removal notification sent"
            fi

            # Очищаем ресурсы в любом случае
            rm -f "$LAST_POSITION_FILE"; log_message "Removed position file"
            rm -f "$0"; log_message "Removed monitor script"
            (crontab -l | grep -v "$0" | crontab - 2>/dev/null) || true
            rm -f "$LOG_FILE"
        fi
    fi
    return 0
}

main(){
    log_message "===== Starting monitor cycle ====="
    ( sleep 300; log_message "ERROR: Script timed out after 5 minutes"; kill -TERM $$ 2>/dev/null ) & TO_PID=$!
    monitor_position; local ec=$?
    kill "$TO_PID" 2>/dev/null || true
    [[ $ec -ne 0 ]] && log_message "ERROR: exit $ec"
    log_message "===== Monitor cycle completed ====="
    return $ec
}
main >> "$LOG_FILE" 2>&1
EOF
    # substitute placeholders
    sed -i "s|__ADDR__|$validator_address|g" "$MONITOR_DIR/$script_name"
    sed -i "s|__NETWORK__|$network|g" "$MONITOR_DIR/$script_name"
    sed -i "s|__MDIR__|$MONITOR_DIR|g" "$MONITOR_DIR/$script_name"
    sed -i "s|__POSFILE__|$position_file|g" "$MONITOR_DIR/$script_name"
    sed -i "s|__LOGFILE__|$log_file|g" "$MONITOR_DIR/$script_name"
    sed -i "s|__TBOT__|${TELEGRAM_BOT_TOKEN-}|g" "$MONITOR_DIR/$script_name"
    sed -i "s|__TCHAT__|${TELEGRAM_CHAT_ID-}|g" "$MONITOR_DIR/$script_name"

    chmod +x "$MONITOR_DIR/$script_name"
    if ! crontab -l 2>/dev/null | grep -q "$MONITOR_DIR/$script_name"; then
        (crontab -l 2>/dev/null; echo "0 * * * * timeout 600 $MONITOR_DIR/$script_name") | crontab -
    fi
    printf -v message "$(t "notification_script_created")" "$validator_address"
    echo -e "\n${GREEN}${message}${NC}"
    echo -e "${YELLOW}$(t "initial_notification_note")${NC}"
    echo -e "${CYAN}$(t "running_initial_test")${NC}"
    timeout 60 "$MONITOR_DIR/$script_name" >/dev/null 2>&1 || true
}

# Функция для отображения списка активных мониторингов
list_monitor_scripts() {
    local MONITOR_DIR="$1"
    local scripts=($(ls "$MONITOR_DIR"/monitor_*.sh 2>/dev/null))

    if [ ${#scripts[@]} -eq 0 ]; then
        echo -e "${YELLOW}$(t "no_notifications")${NC}"
        return
    fi

    echo -e "${BOLD}$(t "active_monitors")${NC}"
    for script in "${scripts[@]}"; do
        local address=$(grep -oP 'VALIDATOR_ADDRESS="\K[^"]+' "$script")
        echo -e "  ${CYAN}$address${NC}"
    done
}

# Функция для получения списка валидаторов через GSE контракт
get_validators_via_gse() {
    local network="$1"
    local ROLLUP_ADDRESS="$2"
    local GSE_ADDRESS="$3"

    echo -e "${YELLOW}$(t "getting_validator_count")${NC}"

    # Используем правильный RPC URL в зависимости от сети
    local current_rpc="$RPC_URL"
    if [[ "$network" == "mainnet" && -n "$ALT_RPC" ]]; then
        current_rpc="$ALT_RPC"
        echo -e "${YELLOW}Using mainnet RPC: $current_rpc${NC}"
    fi

    VALIDATOR_COUNT=$(cast call "$ROLLUP_ADDRESS" "getActiveAttesterCount()" --rpc-url "$current_rpc" | cast to-dec)

    # Проверяем успешность выполнения и валидность результата
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to get validator count${NC}"
        return 1
    fi

    if ! [[ "$VALIDATOR_COUNT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid validator count format: '$VALIDATOR_COUNT'${NC}"
        return 1
    fi

    echo -e "${GREEN}Validator count: $VALIDATOR_COUNT${NC}"

    echo -e "${YELLOW}$(t "getting_current_slot")${NC}"

    SLOT=$(cast call "$ROLLUP_ADDRESS" "getCurrentSlot()" --rpc-url "$current_rpc" | cast to-dec)

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to get current slot${NC}"
        return 1
    fi

    if ! [[ "$SLOT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid slot format: '$SLOT'${NC}"
        return 1
    fi

    echo -e "${GREEN}Current slot: $SLOT${NC}"

    echo -e "${YELLOW}$(t "deriving_timestamp")${NC}"

    TIMESTAMP=$(cast call "$ROLLUP_ADDRESS" "getTimestampForSlot(uint256)" $SLOT --rpc-url "$current_rpc" | cast to-dec)

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to get timestamp for slot${NC}"
        return 1
    fi

    if ! [[ "$TIMESTAMP" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid timestamp format: '$TIMESTAMP'${NC}"
        return 1
    fi

    echo -e "${GREEN}Timestamp for slot $SLOT: $TIMESTAMP${NC}"

    # Создаем массив индексов от 0 до VALIDATOR_COUNT-1
    INDICES=()
    for ((i=0; i<VALIDATOR_COUNT; i++)); do
        INDICES+=("$i")
    done

    echo -e "${YELLOW}$(t "querying_attesters")${NC}"

    # Инициализируем массив для всех адресов
    local ALL_VALIDATOR_ADDRESSES=()
    local BATCH_SIZE=3000
    local TOTAL_BATCHES=$(( (VALIDATOR_COUNT + BATCH_SIZE - 1) / BATCH_SIZE ))

    # Обрабатываем индексы партиями
    for ((BATCH_START=0; BATCH_START<VALIDATOR_COUNT; BATCH_START+=BATCH_SIZE)); do
        BATCH_END=$((BATCH_START + BATCH_SIZE - 1))
        if [ $BATCH_END -ge $VALIDATOR_COUNT ]; then
            BATCH_END=$((VALIDATOR_COUNT - 1))
        fi

        CURRENT_BATCH=$((BATCH_START / BATCH_SIZE + 1))
        BATCH_INDICES=("${INDICES[@]:$BATCH_START:$BATCH_SIZE}")
        BATCH_COUNT=${#BATCH_INDICES[@]}

        echo -e "${GRAY}Processing batch $CURRENT_BATCH/$TOTAL_BATCHES (indices $BATCH_START-$BATCH_END, $BATCH_COUNT addresses)${NC}"

        # Преобразуем массив в строку для передачи в cast call
        INDICES_STR=$(printf "%s," "${BATCH_INDICES[@]}")
        INDICES_STR="${INDICES_STR%,}"  # Убираем последнюю запятую

        # Вызываем GSE контракт для получения списка валидаторов
        VALIDATORS_RESPONSE=$(cast call "$GSE_ADDRESS" \
            "getAttestersFromIndicesAtTime(address,uint256,uint256[])" \
            "$ROLLUP_ADDRESS" "$TIMESTAMP" "[$INDICES_STR]" \
            --rpc-url "$current_rpc")
        local exit_code=$?

        if [ $exit_code -ne 0 ]; then
            echo -e "${RED}Error: GSE contract call failed for batch $CURRENT_BATCH with exit code $exit_code${NC}"
            return 1
        fi

        if [ -z "$VALIDATORS_RESPONSE" ]; then
            echo -e "${RED}Error: Empty response from GSE contract for batch $CURRENT_BATCH${NC}"
            return 1
        fi

        # Парсим ABI-encoded динамический массив
        # Убираем префикс 0x
        RESPONSE_WITHOUT_PREFIX=${VALIDATORS_RESPONSE#0x}

        # Извлекаем длину массива (первые 64 символа после смещения)
        OFFSET_HEX=${RESPONSE_WITHOUT_PREFIX:0:64}
        ARRAY_LENGTH_HEX=${RESPONSE_WITHOUT_PREFIX:64:64}

        # Конвертируем hex в decimal
        local ARRAY_LENGTH=$(printf "%d" "0x$ARRAY_LENGTH_HEX")

        if [ $ARRAY_LENGTH -eq 0 ]; then
            echo -e "${YELLOW}Warning: Empty validator array in batch $CURRENT_BATCH${NC}"
            continue
        fi

        if [ $ARRAY_LENGTH -ne $BATCH_COUNT ]; then
            echo -e "${YELLOW}Warning: Batch array length ($ARRAY_LENGTH) doesn't match batch count ($BATCH_COUNT)${NC}"
        fi

        # Извлекаем адреса из массива
        local START_POS=$((64 + 64))  # Пропускаем offset и length (по 64 символа каждый)

        for ((i=0; i<ARRAY_LENGTH; i++)); do
            # Каждый адрес занимает 64 символа (32 bytes), но нам нужны только последние 40 символов (20 bytes)
            ADDR_HEX=${RESPONSE_WITHOUT_PREFIX:$START_POS:64}
            ADDR="0x${ADDR_HEX:24:40}"  # Берем последние 20 bytes (40 символов)

            # Проверяем валидность адреса
            if [[ "$ADDR" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
                ALL_VALIDATOR_ADDRESSES+=("$ADDR")
            else
                echo -e "${YELLOW}Warning: Invalid address format at batch position $i: '$ADDR'${NC}"
            fi

            START_POS=$((START_POS + 64))
        done

        echo -e "${GREEN}Batch $CURRENT_BATCH processed: ${#ALL_VALIDATOR_ADDRESSES[@]} total addresses so far${NC}"

        # Небольшая задержка между батчами чтобы не перегружать RPC
        if [ $CURRENT_BATCH -lt $TOTAL_BATCHES ]; then
            sleep 1
        fi
    done

    # Сохраняем результаты в глобальный массив (перезаписываем его)
    VALIDATOR_ADDRESSES=("${ALL_VALIDATOR_ADDRESSES[@]}")

    echo -e "${GREEN}$(t "contract_found_validators") ${#VALIDATOR_ADDRESSES[@]}${NC}"

    if [ ${#VALIDATOR_ADDRESSES[@]} -eq 0 ]; then
        echo -e "${RED}Error: No valid validator addresses found${NC}"
        return 1
    fi

    return 0
}

fast_load_validators() {
    local network="$1"
    local ROLLUP_ADDRESS="$2"

    echo -e "\n${YELLOW}$(t "loading_validators")${NC}"

    # Используем правильный RPC URL в зависимости от сети
    local current_rpc="$RPC_URL"
    if [[ "$network" == "mainnet" && -n "$ALT_RPC" ]]; then
        current_rpc="$ALT_RPC"
    fi

    echo -e "${YELLOW}Using RPC: $current_rpc${NC}"

    # Обрабатываем валидаторов последовательно
    for ((i=0; i<VALIDATOR_COUNT; i++)); do
        local validator="${VALIDATOR_ADDRESSES[i]}"
        echo -e "${GRAY}Processing: $validator${NC}"

        # Получаем данные getAttesterView
        response=$(cast call "$ROLLUP_ADDRESS" "getAttesterView(address)" "$validator" --rpc-url "$current_rpc" 2>/dev/null)

        if [[ $? -ne 0 || -z "$response" || ${#response} -lt 130 ]]; then
            echo -e "${RED}Error getting data for: $validator${NC}"
            continue
        fi

        # Парсим данные из getAttesterView
        data=${response:2}  # Убираем префикс 0x

        # Извлекаем статус (первые 64 символа)
        status_hex=${data:0:64}

        # Извлекаем стейк (следующие 64 символа)
        stake_hex=${data:64:64}

        # Извлекаем withdrawer из конца ответа (последние 64 символа)
        withdrawer_hex=${data: -64}  # Последние 64 символа
        withdrawer="0x${withdrawer_hex:24:40}"  # Берем последние 20 bytes (40 символов)

        # Проверяем валидность адреса withdrawer
        if [[ ! "$withdrawer" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            echo -e "${YELLOW}Warning: Invalid withdrawer format for $validator, using zero address${NC}"
            withdrawer="0x0000000000000000000000000000000000000000"
        fi

        # Получаем информацию о ревардах
        rewards_response=$(cast call "$ROLLUP_ADDRESS" "getSequencerRewards(address)" "$validator" --rpc-url "$current_rpc" 2>/dev/null)
        if [[ $? -eq 0 && -n "$rewards_response" ]]; then
            rewards_decimal=$(echo "$rewards_response" | cast --to-dec 2>/dev/null)
            rewards_wei=$(echo "$rewards_decimal" | cast --from-wei 2>/dev/null)
            # Оставляем только целую часть
            rewards=$(echo "$rewards_wei" | cut -d. -f1)
        else
            rewards="0"
        fi

        # Преобразуем hex в decimal с использованием вспомогательных функций
        status=$(hex_to_dec "$status_hex")
        # Убираем пробелы и лишние символы из статуса
        status=$(echo "$status" | tr -d '[:space:]')
        stake_decimal=$(hex_to_dec "$stake_hex")
        stake=$(wei_to_token "$stake_decimal")

        # Безопасное получение статуса и цвета
        # Проверяем, что STATUS_MAP доступен и содержит нужный ключ
        if [[ -n "${STATUS_MAP[$status]:-}" ]]; then
            local status_text="${STATUS_MAP[$status]}"
        else
            # Если STATUS_MAP не доступен или ключ не найден, используем дефолтные значения
            case "$status" in
                0) local status_text="NONE - The validator is not in the validator set" ;;
                1) local status_text="VALIDATING - The validator is currently in the validator set" ;;
                2) local status_text="ZOMBIE - Not participating as validator, but have funds in setup" ;;
                3) local status_text="EXITING - In the process of exiting the system" ;;
                *) local status_text="UNKNOWN (status=$status)" ;;
            esac
        fi

        if [[ -n "${STATUS_COLOR[$status]:-}" ]]; then
            local status_color="${STATUS_COLOR[$status]}"
        else
            # Дефолтные цвета для статусов
            case "$status" in
                0) local status_color="$GRAY" ;;
                1) local status_color="$GREEN" ;;
                2) local status_color="$YELLOW" ;;
                3) local status_color="$RED" ;;
                *) local status_color="$NC" ;;
            esac
        fi

        # Добавляем в результаты
        RESULTS+=("$validator|$stake|$withdrawer|$rewards|$status|$status_text|$status_color")
    done

    echo -e "${GREEN}Successfully loaded: ${#RESULTS[@]}/$VALIDATOR_COUNT validators${NC}"
}

# Функция для удаления мониторинга очереди валидаторов
remove_monitor_scripts() {
    local MONITOR_DIR="$1"
    local scripts=($(ls "$MONITOR_DIR"/monitor_*.sh 2>/dev/null))

    if [ ${#scripts[@]} -eq 0 ]; then
        echo -e "${YELLOW}$(t "no_notifications")${NC}"
        return
    fi

    echo -e "\n${YELLOW}$(t "select_monitor_to_remove")${NC}"
    echo -e "1. $(t "remove_all")"

    local i=2
    declare -A script_map
    for script in "${scripts[@]}"; do
        local address=$(grep -oP 'VALIDATOR_ADDRESS="\K[^"]+' "$script")
        echo -e "$i. $address"
        script_map[$i]="$script|$address"
        ((i++))
    done

    echo ""
    read -p "$(t "enter_choice"): " choice

    case $choice in
        1)
            # Удаление всех скриптов мониторинга
            for script in "${scripts[@]}"; do
                local address=$(grep -oP 'VALIDATOR_ADDRESS="\K[^"]+' "$script")
                local base_name=$(basename "$script" .sh)
                local log_file="$MONITOR_DIR/${base_name}.log"
                local position_file="$MONITOR_DIR/last_position_${base_name#monitor_}.txt"

                # Удаляем из crontab
                (crontab -l | grep -v "$script" | crontab - 2>/dev/null) || true

                # Удаляем файлы
                rm -f "$script" "$log_file" "$position_file"

                printf -v message "$(t "monitor_removed")" "$address"
                echo -e "${GREEN}${message}${NC}"
            done
            echo -e "${GREEN}$(t "all_monitors_removed")${NC}"
            ;;
        [2-9]|1[0-9])
            # Удаление конкретного монитора
            if [[ -n "${script_map[$choice]}" ]]; then
                IFS='|' read -r script address <<< "${script_map[$choice]}"
                local base_name=$(basename "$script" .sh)
                local log_file="$MONITOR_DIR/${base_name}.log"
                local position_file="$MONITOR_DIR/last_position_${base_name#monitor_}.txt"

                # Удаляем из crontab
                (crontab -l | grep -v "$script" | crontab - 2>/dev/null) || true

                # Удаляем файлы
                rm -f "$script" "$log_file" "$position_file"

                printf -v message "$(t "monitor_removed")" "$address"
                echo -e "${GREEN}${message}${NC}"
            else
                echo -e "${RED}$(t "invalid_choice")${NC}"
            fi
            ;;
        *)
            echo -e "${RED}$(t "invalid_choice")${NC}"
            ;;
    esac
}

# Основная функция для запуска check-validator (merged from check-validator.sh main code)
check_validator_main() {
    local network=$(get_network_for_validator)

    # Выбор адресов в зависимости от сети
    local ROLLUP_ADDRESS
    local GSE_ADDRESS
    local QUEUE_URL
    if [[ "$network" == "mainnet" ]]; then
        ROLLUP_ADDRESS="$CONTRACT_ADDRESS_MAINNET"
        GSE_ADDRESS="$GSE_ADDRESS_MAINNET"
        QUEUE_URL="https://dashtec.xyz/api/sequencers/queue"
    else
        ROLLUP_ADDRESS="$CONTRACT_ADDRESS"
        GSE_ADDRESS="$GSE_ADDRESS_TESTNET"
        QUEUE_URL="https://${network}.dashtec.xyz/api/sequencers/queue"
    fi

    local MONITOR_DIR="$HOME/aztec-monitor-agent"

    # Загружаем конфигурацию RPC
    if ! load_rpc_config; then
        return 1
    fi

    # Глобальная переменная для отслеживания использования резервного RPC
    USING_BACKUP_RPC=false

    # Глобальная переменная для хранения количества найденных в очереди валидаторов
    QUEUE_FOUND_COUNT=0

    # Глобальный массив для хранения адресов валидаторов, найденных в очереди
    declare -a QUEUE_FOUND_ADDRESSES=()

    # Заполняем глобальные массивы статусов (объявлены на уровне скрипта)
    STATUS_MAP[0]=$(t "status_0")
    STATUS_MAP[1]=$(t "status_1")
    STATUS_MAP[2]=$(t "status_2")
    STATUS_MAP[3]=$(t "status_3")

    STATUS_COLOR[0]="$GRAY"
    STATUS_COLOR[1]="$GREEN"
    STATUS_COLOR[2]="$YELLOW"
    STATUS_COLOR[3]="$RED"

    echo -e "${BOLD}$(t "fetching_validators") ${CYAN}$ROLLUP_ADDRESS${NC}..."

    # Используем функцию для получения списка валидаторов через GSE контракт
    if ! get_validators_via_gse "$network" "$ROLLUP_ADDRESS" "$GSE_ADDRESS"; then
        echo -e "${RED}Error: Failed to fetch validators using GSE contract method${NC}"
        return 1
    fi

    echo "----------------------------------------"

    # Запрашиваем адреса валидаторов для проверки
    echo ""
    echo -e "${BOLD}Enter validator addresses to check (comma separated):${NC}"
    read -p "> " input_addresses

    # Парсим введенные адреса
    IFS=',' read -ra INPUT_ADDRESSES <<< "$input_addresses"

    # Очищаем адреса от пробелов и проверяем их наличие в общем списке
    declare -a VALIDATOR_ADDRESSES_TO_CHECK=()
    declare -a QUEUE_VALIDATORS=()
    declare -a NOT_FOUND_ADDRESSES=()
    found_count=0
    not_found_count=0

    # Сначала проверяем все адреса в активных валидаторах
    for address in "${INPUT_ADDRESSES[@]}"; do
        # Очищаем адрес от пробелов
        clean_address=$(echo "$address" | tr -d ' ')

        # Проверяем, есть ли адрес в общем списке
        found=false
        for validator in "${VALIDATOR_ADDRESSES[@]}"; do
            if [[ "${validator,,}" == "${clean_address,,}" ]]; then
                VALIDATOR_ADDRESSES_TO_CHECK+=("$validator")
                found=true
                found_count=$((found_count + 1))
                echo -e "${GREEN}✓ Found in active validators: $validator${NC}"
                break
            fi
        done

        if ! $found; then
            NOT_FOUND_ADDRESSES+=("$clean_address")
        fi
    done

    # Теперь проверяем не найденные адреса в очереди (пакетно)
    found_in_queue_count=0
    if [ ${#NOT_FOUND_ADDRESSES[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}$(t "validator_not_in_set")${NC}"

        # Используем новую функцию для пакетной проверки в очереди
        check_validator_queue "${NOT_FOUND_ADDRESSES[@]}"
        # Функция устанавливает глобальную переменную QUEUE_FOUND_COUNT
        found_in_queue_count=$QUEUE_FOUND_COUNT

        not_found_count=$((${#NOT_FOUND_ADDRESSES[@]} - found_in_queue_count))
    fi

    # Показываем общую сводку
    echo -e "\n${CYAN}=== Search Summary ===${NC}"
    echo -e "Found in active validators: ${GREEN}$found_count${NC}"
    echo -e "Found in queue: ${YELLOW}$found_in_queue_count${NC}"
    echo -e "Not found anywhere: ${RED}$not_found_count${NC}"

    # Обрабатываем активных валидаторов
    if [[ ${#VALIDATOR_ADDRESSES_TO_CHECK[@]} -gt 0 ]]; then
        echo -e "\n${GREEN}=== Active Validators Details ===${NC}"

        # Запускаем быструю загрузку для активных валидаторов
        declare -a RESULTS

        # Временно заменяем массив для обработки только выбранных валидаторов
        ORIGINAL_VALIDATOR_ADDRESSES=("${VALIDATOR_ADDRESSES[@]}")
        ORIGINAL_VALIDATOR_COUNT=$VALIDATOR_COUNT
        VALIDATOR_ADDRESSES=("${VALIDATOR_ADDRESSES_TO_CHECK[@]}")
        VALIDATOR_COUNT=${#VALIDATOR_ADDRESSES_TO_CHECK[@]}

        # Запускаем быструю загрузку
        fast_load_validators "$network" "$ROLLUP_ADDRESS"

        # Восстанавливаем оригинальный массив
        VALIDATOR_ADDRESSES=("${ORIGINAL_VALIDATOR_ADDRESSES[@]}")
        VALIDATOR_COUNT=$ORIGINAL_VALIDATOR_COUNT

        # Показываем результат
        echo ""
        echo -e "${BOLD}Validator results (${#RESULTS[@]} total):${NC}"
        echo "----------------------------------------"
        local validator_num=1
        for line in "${RESULTS[@]}"; do
            IFS='|' read -r validator stake withdrawer rewards status status_text status_color <<< "$line"
            echo -e "${BOLD}Validator #$validator_num${NC}"
            echo -e "  ${BOLD}$(t "address"):${NC} $validator"
            echo -e "  ${BOLD}$(t "stake"):${NC} $stake STK"
            echo -e "  ${BOLD}$(t "withdrawer"):${NC} $withdrawer"
            echo -e "  ${BOLD}$(t "rewards"):${NC} $rewards STK"
            echo -e "  ${BOLD}$(t "status"):${NC} ${status_color}$status - $status_text${NC}"
            echo -e ""
            echo "----------------------------------------"
            validator_num=$((validator_num + 1))
        done
    fi

    # Обрабатываем валидаторов из очереди (только если они не были уже показаны)
    if [[ ${#QUEUE_FOUND_ADDRESSES[@]} -gt 0 ]]; then
        echo -e "\n${YELLOW}=== $(t "queue_validators_available") ===${NC}"

        # Предлагаем добавить в мониторинг
        echo -e "${BOLD}$(t "add_validators_to_queue_prompt")${NC}"
        read -p "$(t "enter_yes_to_add") " add_to_monitor

        if [[ "$add_to_monitor" == "yes" || "$add_to_monitor" == "y" ]]; then
            # Создаем мониторы для всех валидаторов из очереди
            for validator in "${QUEUE_FOUND_ADDRESSES[@]}"; do
                printf -v message "$(t "processing_address")" "$validator"
                echo -e "\n${YELLOW}${message}${NC}"
                create_monitor_script "$validator" "$network" "$MONITOR_DIR" "$QUEUE_URL"
            done
            echo -e "\n${GREEN}$(t "queue_validators_added")${NC}"
        else
            echo -e "${YELLOW}$(t "skipping_queue_setup")${NC}"
        fi
    fi

    if [[ ${#VALIDATOR_ADDRESSES_TO_CHECK[@]} -eq 0 && ${#QUEUE_FOUND_ADDRESSES[@]} -eq 0 ]]; then
        echo -e "${RED}$(t "no_valid_addresses")${NC}"
    fi
}

# === Validator submenu ===
validator_submenu() {
    local MONITOR_DIR="$HOME/aztec-monitor-agent"
    local network=$(get_network_for_validator)

    # Выбор адресов в зависимости от сети
    local QUEUE_URL
    if [[ "$network" == "mainnet" ]]; then
        QUEUE_URL="https://dashtec.xyz/api/sequencers/queue"
    else
        QUEUE_URL="https://${network}.dashtec.xyz/api/sequencers/queue"
    fi

    while true; do
        echo ""
        echo -e "${BOLD}$(t "select_action")${NC}"
        echo -e "${CYAN}$(t "validator_submenu_option1")${NC}"
        echo -e "${CYAN}$(t "validator_submenu_option2")${NC}"
        echo -e "${CYAN}$(t "validator_submenu_option3")${NC}"
        echo -e "${CYAN}$(t "validator_submenu_option4")${NC}"
        echo -e "${CYAN}$(t "validator_submenu_option5")${NC}"
        echo -e "${RED}$(t "option0")${NC}"
        read -p "$(t "enter_option") " choice

        case $choice in
            1)
                # Check another set of validators
                check_validator_main
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${NC}"
                read -r
                ;;
            2)
                # Set up queue position notification for validator
                echo -e "\n${BOLD}$(t "queue_notification_title")${NC}"
                list_monitor_scripts "$MONITOR_DIR"
                echo ""
                read -p "$(t "enter_multiple_addresses") " validator_addresses

                # Создаем скрипты для всех указанных адресов
                IFS=',' read -ra ADDRESSES_TO_MONITOR <<< "$validator_addresses"
                for address in "${ADDRESSES_TO_MONITOR[@]}"; do
                    clean_address=$(echo "$address" | tr -d ' ')
                    printf -v message "$(t "processing_address")" "$clean_address"
                    echo -e "${YELLOW}${message}${NC}"

                    # Проверяем, есть ли валидатор хотя бы в очереди
                    if check_validator_queue "$clean_address"; then
                        create_monitor_script "$clean_address" "$network" "$MONITOR_DIR" "$QUEUE_URL"
                    else
                        echo -e "${RED}$(t "validator_not_in_queue")${NC}"
                    fi
                done
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${NC}"
                read -r
                ;;
            3)
                # Check validator in queue
                read -p "$(t "enter_address") " validator_address
                check_validator_queue "$validator_address"
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${NC}"
                read -r
                ;;
            4)
                # List active monitors
                list_monitor_scripts "$MONITOR_DIR"
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${NC}"
                read -r
                ;;
            5)
                # Remove existing monitoring
                remove_monitor_scripts "$MONITOR_DIR"
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${NC}"
                read -r
                ;;
            0)
                echo -e "\n${CYAN}$(t "exiting")${NC}"
                break
                ;;
            *)
                echo -e "\n${RED}$(t "invalid_input")${NC}"
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${NC}"
                read -r
                ;;
        esac
    done
}

# === Check validator ===
function check_validator {
  echo -e ""
  echo -e "${CYAN}$(t "running_validator_script")${NC}"
  echo -e ""

  validator_submenu
}
