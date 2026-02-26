# === Create agent and systemd task ===
create_systemd_agent() {
  local env_file
  env_file=$(_ensure_env_file)
  source "$env_file"

  # Function to validate Telegram bot token
  validate_telegram_token() {
    local token=$1
    if [[ ! "$token" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
      return 1
    fi
    # Test token by making API call
    local response=$(curl -s "https://api.telegram.org/bot${token}/getMe")
    if [[ "$response" == *"ok\":true"* ]]; then
      return 0
    else
      return 1
    fi
  }

  # Function to validate Telegram chat ID (updated version)
  validate_telegram_chat() {
    local token=$1
    local chat_id=$2
    # Test chat ID by trying to send a test message
    local response=$(curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
      -d chat_id="${chat_id}" \
      -d text="$(t "chatid_linked")" \
      -d parse_mode="Markdown")

    if [[ "$response" == *"ok\":true"* ]]; then
      return 0
    else
      return 1
    fi
  }

  # === Проверка и получение TELEGRAM_BOT_TOKEN ===
  if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    while true; do
      echo -e "\n${BLUE}$(t "token_prompt")${NC}"
      read -p "> " TELEGRAM_BOT_TOKEN

      if validate_telegram_token "$TELEGRAM_BOT_TOKEN"; then
        echo "TELEGRAM_BOT_TOKEN=\"$TELEGRAM_BOT_TOKEN\"" >> "$env_file"
        break
      else
        echo -e "${RED}$(t "invalid_token")${NC}"
        echo -e "${YELLOW}$(t "token_format")${NC}"
      fi
    done
  fi

  # === Проверка и получение TELEGRAM_CHAT_ID ===
  if [ -z "$TELEGRAM_CHAT_ID" ]; then
    while true; do
      echo -e "\n${BLUE}$(t "chatid_prompt")${NC}"
      read -p "> " TELEGRAM_CHAT_ID

      if [[ "$TELEGRAM_CHAT_ID" =~ ^-?[0-9]+$ ]]; then
        if validate_telegram_chat "$TELEGRAM_BOT_TOKEN" "$TELEGRAM_CHAT_ID"; then
          echo "TELEGRAM_CHAT_ID=\"$TELEGRAM_CHAT_ID\"" >> "$env_file"
          break
        else
          echo -e "${RED}$(t "invalid_chatid")${NC}"
        fi
      else
        echo -e "${RED}$(t "chatid_number")${NC}"
      fi
    done
  fi

  # === Запрос о дополнительных уведомлениях ===
  if [ -z "$NOTIFICATION_TYPE" ]; then
    echo -e "\n${BLUE}$(t "notifications_prompt")${NC}"
    echo -e "$(t "notifications_option1")"
    echo -e "$(t "notifications_option2")"
    echo -e "\n${YELLOW}$(t "notifications_debug_warning")${NC}"
    while true; do
      read -p "$(t "choose_option_prompt") (1/2): " NOTIFICATION_TYPE
      if [[ "$NOTIFICATION_TYPE" =~ ^[12]$ ]]; then
        if ! grep -q "NOTIFICATION_TYPE" "$env_file"; then
          echo "NOTIFICATION_TYPE=\"$NOTIFICATION_TYPE\"" >> "$env_file"
        else
          sed -i "s/^NOTIFICATION_TYPE=.*/NOTIFICATION_TYPE=\"$NOTIFICATION_TYPE\"/" "$env_file"
        fi
        break
      else
        echo -e "${RED}$(t "notifications_input_error")${NC}"
      fi
    done
  fi

  # === Проверка и получение VALIDATORS (если NOTIFICATION_TYPE == 2) ===
  if [ "$NOTIFICATION_TYPE" -eq 2 ] && [ ! -f "$HOME/.env-aztec-agent" ] || ! grep -q "^VALIDATORS=" "$HOME/.env-aztec-agent"; then
    echo -e "\n${BLUE}$(t "validators_prompt")${NC}"
    echo -e "${YELLOW}$(t "validators_format")${NC}"
    while true; do
      read -p "> " VALIDATORS
      if [[ -n "$VALIDATORS" ]]; then
        if [ -f "$HOME/.env-aztec-agent" ]; then
          if grep -q "^VALIDATORS=" "$HOME/.env-aztec-agent"; then
            sed -i "s/^VALIDATORS=.*/VALIDATORS=\"$VALIDATORS\"/" "$HOME/.env-aztec-agent"
          else
            printf 'VALIDATORS="%s"\n' "$VALIDATORS" >> "$HOME/.env-aztec-agent"
          fi
        else
          printf 'VALIDATORS="%s"\n' "$VALIDATORS" > "$HOME/.env-aztec-agent"
        fi
        break
      else
        echo -e "${RED}$(t "validators_empty")${NC}"
      fi
    done
  fi

  mkdir -p "$AGENT_SCRIPT_PATH"

  # Security: Copy local error_definitions.json to agent directory to avoid remote downloads
  if [ -f "$SCRIPT_DIR/error_definitions.json" ]; then
    # Проверяем, что файлы разные перед копированием (избегаем копирования файла сам в себя)
    source_file="$SCRIPT_DIR/error_definitions.json"
    dest_file="$HOME/error_definitions.json"

    # Получаем абсолютные пути для сравнения
    source_abs=$(cd "$(dirname "$source_file")" && pwd)/$(basename "$source_file")
    dest_abs=$(cd "$(dirname "$dest_file")" && pwd)/$(basename "$dest_file")

    if [ "$source_abs" != "$dest_abs" ]; then
      cp "$source_file" "$dest_file"
    fi
  fi

  # Генерация скрипта агента
  cat > "$AGENT_SCRIPT_PATH/agent.sh" <<EOF
#!/bin/bash
export PATH="\$PATH:\$HOME/.foundry/bin"
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

source \$HOME/.env-aztec-agent
CONTRACT_ADDRESS="$CONTRACT_ADDRESS"
CONTRACT_ADDRESS_MAINNET="$CONTRACT_ADDRESS_MAINNET"
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
LOG_FILE="$LOG_FILE"
LANG="$LANG"

# === Helper function to get network and RPC settings ===
get_network_settings() {
    local env_file="\$HOME/.env-aztec-agent"
    local network="testnet"
    local rpc_url=""

    if [[ -f "\$env_file" ]]; then
        source "\$env_file"
        [[ -n "\$NETWORK" ]] && network="\$NETWORK"
        if [[ -n "\$ALT_RPC" ]]; then
            rpc_url="\$ALT_RPC"
        elif [[ -n "\$RPC_URL" ]]; then
            rpc_url="\$RPC_URL"
        fi
    fi

    # Determine contract address based on network
    local contract_address="\$CONTRACT_ADDRESS"
    if [[ "\$network" == "mainnet" ]]; then
        contract_address="\$CONTRACT_ADDRESS_MAINNET"
    fi

    echo "\$network|\$rpc_url|\$contract_address"
}

# Получаем настройки сети
NETWORK_SETTINGS=\$(get_network_settings)
NETWORK=\$(echo "\$NETWORK_SETTINGS" | cut -d'|' -f1)
RPC_URL=\$(echo "\$NETWORK_SETTINGS" | cut -d'|' -f2)
CONTRACT_ADDRESS=\$(echo "\$NETWORK_SETTINGS" | cut -d'|' -f3)

# Security: Use local error definitions file instead of remote download to prevent supply chain attacks
ERROR_DEFINITIONS_FILE="\$HOME/error_definitions.json"

# Функция перевода
t() {
  local key=\$1
  local value1=\$2
  local value2=\$3

  case \$key in
    "log_cleaned") echo "$(t "agent_log_cleaned")" ;;
    "container_not_found") echo "$(t "agent_container_not_found")" ;;
    "block_fetch_error") echo "$(t "agent_block_fetch_error")" ;;
    "no_block_in_logs") echo "$(t "agent_no_block_in_logs")" ;;
    "failed_extract_block") echo "$(t "agent_failed_extract_block")" ;;
    "node_behind") printf "$(t "agent_node_behind")" "\$value1" ;;
    "agent_started") echo "$(t "agent_started")" ;;
    "log_size_warning") echo "$(t "agent_log_size_warning")" ;;
    "server_info") printf "$(t "agent_server_info")" "\$value1" ;;
    "file_info") printf "$(t "agent_file_info")" "\$value1" ;;
    "size_info") printf "$(t "agent_size_info")" "\$value1" ;;
    "rpc_info") printf "$(t "agent_rpc_info")" "\$value1" ;;
    "error_info") printf "$(t "agent_error_info")" "\$value1" ;;
    "block_info") printf "$(t "agent_block_info")" "\$value1" ;;
    "log_block_info") printf "$(t "agent_log_block_info")" "\$value1" ;;
    "time_info") printf "$(t "agent_time_info")" "\$value1" ;;
    "line_info") printf "$(t "agent_line_info")" "\$value1" ;;
    "notifications_info") echo "$(t "agent_notifications_info")" ;;
    "node_synced") printf "$(t "agent_node_synced")" "\$value1" ;;
    "critical_error_found") echo "$(t "critical_error_found")" ;;
    "error_prefix") echo "$(t "error_prefix")" ;;
    "solution_prefix") echo "$(t "solution_prefix")" ;;
    "notifications_full_info") echo "$(t "agent_notifications_full_info")" ;;
    "committee_selected") echo "$(t "committee_selected")" ;;
    "epoch_info") printf "$(t "epoch_info")" "\$value1" ;;
    "block_built") printf "$(t "block_built")" "\$value1" ;;
    "slot_info") printf "$(t "slot_info")" "\$value1" ;;
    "found_validators") printf "$(t "found_validators")" "\$value1" ;;
    "validators_prompt") echo "$(t "validators_prompt")" ;;
    "validators_format") echo "$(t "validators_format")" ;;
    "validators_empty") echo "$(t "validators_empty")" ;;
    "attestation_status") echo "$(t "attestation_status")" ;;
    "status_legend") echo "$(t "status_legend")" ;;
    "status_empty") echo "$(t "status_empty")" ;;
    "status_attestation_sent") echo "$(t "status_attestation_sent")" ;;
    "status_attestation_missed") echo "$(t "status_attestation_missed")" ;;
    "status_block_mined") echo "$(t "status_block_mined")" ;;
    "status_block_missed") echo "$(t "status_block_missed")" ;;
    "status_block_proposed") echo "$(t "status_block_proposed")" ;;
    "current_slot") printf "$(t "current_slot")" "\$value1" ;;
    "publisher_balance_warning") echo "$(t "publisher_balance_warning")" ;;
    *) echo "\$key" ;;
  esac
}

# === Создание файла лога, если его нет ===
if [ ! -f "\$LOG_FILE" ]; then
  touch "\$LOG_FILE" 2>/dev/null || {
    echo "Error: Could not create log file \$LOG_FILE"
    exit 1
  }
fi

if [ ! -w "\$LOG_FILE" ]; then
  echo "Error: No write permission for \$LOG_FILE"
  exit 1
fi

# === Проверка размера файла и очистка, если больше 1 МБ ===
# Устанавливаем MAX_SIZE в зависимости от DEBUG
# Если DEBUG=true, то MAX_SIZE=10 МБ (10485760 байт)
# Если DEBUG=false или не установлен, то MAX_SIZE=1 МБ (1048576 байт)
if [ -n "\$DEBUG" ]; then
  debug_value=\$(echo "\$DEBUG" | tr '[:upper:]' '[:lower:]' | tr -d '"' | tr -d "'")
  if [ "\$debug_value" = "true" ] || [ "\$debug_value" = "1" ] || [ "\$debug_value" = "yes" ]; then
    MAX_SIZE=10485760  # 10 МБ
  else
    MAX_SIZE=1048576   # 1 МБ
  fi
else
  MAX_SIZE=1048576    # 1 МБ по умолчанию
fi

current_size=\$(stat -c%s "\$LOG_FILE")

if [ "\$current_size" -gt "\$MAX_SIZE" ]; then
  temp_file=\$(mktemp)
  if grep -q "INITIALIZED" "\$LOG_FILE"; then
    awk '/INITIALIZED/ {print; exit} {print}' "\$LOG_FILE" > "\$temp_file"
  else
    head -n 8 "\$LOG_FILE" > "\$temp_file"
  fi
  mv "\$temp_file" "\$LOG_FILE"
  chmod 644 "\$LOG_FILE"

  {
    echo ""
    echo "\$(t "log_cleaned")"
    echo "Cleanup completed: \$(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
  } >> "\$LOG_FILE"

  ip=\$(curl -s https://api.ipify.org || echo "unknown-ip")
  current_time=\$(date '+%Y-%m-%d %H:%M:%S')
  message="\$(t "log_size_warning")%0A\$(t "server_info" "\$ip")%0A\$(t "file_info" "\$LOG_FILE")%0A\$(t "size_info" "\$current_size")%0A\$(t "time_info" "\$current_time")"

  curl -s -X POST "https://api.telegram.org/bot\$TELEGRAM_BOT_TOKEN/sendMessage" \\
    -d chat_id="\$TELEGRAM_CHAT_ID" \\
    -d text="\$message" \\
    -d parse_mode="Markdown" >/dev/null
else
  {
    echo "="
    echo "Log size check"
    echo "Current size: \$current_size bytes (within limit)."
    echo "Check timestamp: \$(date '+%Y-%m-%d %H:%M:%S')"
    echo "="
  } >> "\$LOG_FILE"
fi

# === Функция для записи в лог-файл ===
log() {
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" >> "\$LOG_FILE"
}

# === Функция для отправки уведомлений в Telegram ===
send_telegram_message() {
  local message="\$1"
  curl -s -X POST "https://api.telegram.org/bot\$TELEGRAM_BOT_TOKEN/sendMessage" \\
    -d chat_id="\$TELEGRAM_CHAT_ID" \\
    -d text="\$message" \\
    -d parse_mode="Markdown" >/dev/null
}

# === Helper: send Telegram message and return message_id ===
send_telegram_message_get_id() {
  local message="\$1"
  local resp
  resp=\$(curl -s -X POST "https://api.telegram.org/bot\$TELEGRAM_BOT_TOKEN/sendMessage" \\
    -d chat_id="\$TELEGRAM_CHAT_ID" \\
    -d text="\$message" \\
    -d parse_mode="Markdown")
  echo "\$resp" | jq -r '.result.message_id'
}

# === Helper: edit Telegram message by message_id ===
edit_telegram_message() {
  local message_id="\$1"
  local text="\$2"
  curl -s -X POST "https://api.telegram.org/bot\$TELEGRAM_BOT_TOKEN/editMessageText" \\
    -d chat_id="\$TELEGRAM_CHAT_ID" \\
    -d message_id="\$message_id" \\
    -d text="\$text" \\
    -d parse_mode="Markdown" >/dev/null
}

# === Helper: build a 32-slot board (8 per line) ===
build_slots_board() {
  # expects 32 items passed as args (each is an emoji)
  local slots=("\$@")
  local out=""
  for i in {0..31}; do
    out+="\${slots[\$i]}"
    if [ \$(((i+1)%8)) -eq 0 ]; then
      out+="%0A"
    fi
  done
  echo "\$out"
}

# === Получаем свой публичный IP для включения в уведомления ===
get_ip_address() {
  curl -s https://api.ipify.org || echo "unknown-ip"
}
ip=\$(get_ip_address)

# === Переводим hex -> decimal ===
hex_to_dec() {
  local hex=\$1
  hex=\${hex#0x}
  hex=\$(echo \$hex | sed 's/^0*//')
  [ -z "\$hex" ] && echo 0 && return
  echo \$((16#\$hex))
}

# === Проверка критических ошибок в логах ===
check_critical_errors() {
  local container_id=\$1
  local clean_logs=\$(docker logs "\$container_id" --tail 10000 2>&1 | sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g')

  # Используем локальный JSON файл с определениями ошибок (безопасность: избегаем удалённых загрузок)
  if [ ! -f "\$ERROR_DEFINITIONS_FILE" ]; then
    log "Error definitions file not found at \$ERROR_DEFINITIONS_FILE"
    return
  fi

  # Парсим JSON с ошибками
  if command -v jq >/dev/null 2>&1; then
    # Используем jq для парсинга новой структуры JSON (объект с массивом errors)
    errors_count=\$(jq '.errors | length' "\$ERROR_DEFINITIONS_FILE")
    for ((i=0; i<\$errors_count; i++)); do
      pattern=\$(jq -r ".errors[\$i].pattern" "\$ERROR_DEFINITIONS_FILE")
      message=\$(jq -r ".errors[\$i].message" "\$ERROR_DEFINITIONS_FILE")
      solution=\$(jq -r ".errors[\$i].solution" "\$ERROR_DEFINITIONS_FILE")

      if echo "\$clean_logs" | grep -q "\$pattern"; then
        log "Critical error detected: \$pattern"
        current_time=\$(date '+%Y-%m-%d %H:%M:%S')
        full_message="\$(t "critical_error_found")%0A\$(t "server_info" "\$ip")%0A\$(t "error_prefix") \$message%0A\$(t "solution_prefix")%0A\$solution%0A\$(t "time_info" "\$current_time")"
        send_telegram_message "\$full_message"
        exit 1
      fi
    done
  else
    # Fallback парсинг без jq (ограниченная функциональность)
    # Извлекаем содержимое массива errors из новой структуры JSON
    errors_section=\$(sed -n '/"errors":\s*\[/,/\]/{ /"errors":\s*\[/d; /\]/d; p; }' "\$ERROR_DEFINITIONS_FILE" 2>/dev/null)

    # Парсим объекты из массива errors
    current_obj=""
    brace_level=0

    while IFS= read -r line || [ -n "\$line" ]; do
      # Удаляем ведущие/замыкающие пробелы и запятые
      line=\$(echo "\$line" | sed 's/^[[:space:],]*//;s/[[:space:],]*$//')

      # Пропускаем пустые строки
      [ -z "\$line" ] && continue

      # Подсчитываем фигурные скобки в строке
      open_count=\$(echo "\$line" | tr -cd '{' | wc -c)
      close_count=\$(echo "\$line" | tr -cd '}' | wc -c)
      brace_level=\$((brace_level + open_count - close_count))

      # Добавляем строку к текущему объекту
      if [ -z "\$current_obj" ]; then
        current_obj="\$line"
      else
        current_obj="\${current_obj} \${line}"
      fi

      # Когда объект завершён (brace_level вернулся к 0 и есть закрывающая скобка)
      if [ "\$brace_level" -eq 0 ] && [ "\$close_count" -gt 0 ]; then
        # Извлекаем pattern, message и solution из объекта
        pattern=\$(echo "\$current_obj" | sed -n 's/.*"pattern"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        message=\$(echo "\$current_obj" | sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        solution=\$(echo "\$current_obj" | sed -n 's/.*"solution"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

        if [ -n "\$pattern" ] && [ -n "\$message" ] && [ -n "\$solution" ]; then
          if echo "\$clean_logs" | grep -q "\$pattern"; then
            log "Critical error detected: \$pattern"
            current_time=\$(date '+%Y-%m-%d %H:%M:%S')
            full_message="\$(t "critical_error_found")%0A\$(t "server_info" "\$ip")%0A\$(t "error_prefix") \$message%0A\$(t "solution_prefix")%0A\$solution%0A\$(t "time_info" "\$current_time")"
            send_telegram_message "\$full_message"
            exit 1
          fi
        fi

        current_obj=""
      fi
    done <<< "\$errors_section"
  fi
}

# === Оптимизированная функция для поиска строк в логах ===
find_last_log_line() {
  local container_id=\$1
  local temp_file=\$(mktemp)

  # Получаем логи с ограничением по объему и сразу фильтруем нужные строки
  # -i: нечувствительность к регистру; checkpointNumber — на случай разбиения длинной строки
  docker logs "\$container_id" --tail 20000 2>&1 | \
    sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g' | \
    grep -iE 'Sequencer sync check succeeded|Downloaded L2 block|Downloaded checkpoint|"checkpointNumber":[0-9]+' | \
    tail -100 > "\$temp_file"

  # Сначала ищем Sequencer sync check succeeded
  local line=\$(tac "\$temp_file" | grep -m1 'Sequencer sync check succeeded')

  # Если не нашли, ищем Downloaded L2 block / Downloaded checkpoint или строку с checkpointNumber
  if [ -z "\$line" ]; then
    line=\$(tac "\$temp_file" | grep -m1 -iE 'Downloaded L2 block|Downloaded checkpoint|"checkpointNumber":[0-9]+')
  fi

  rm -f "\$temp_file"
  echo "\$line"
}

# === Функция для проверки и добавления переменной DEBUG ===
ensure_debug_variable() {
  local env_file="\$HOME/.env-aztec-agent"
  if [ ! -f "\$env_file" ]; then
    return
  fi

  # Проверяем, существует ли уже переменная DEBUG
  if ! grep -q "^DEBUG=" "\$env_file"; then
    # Добавляем DEBUG переменную в конец файла
    echo "DEBUG=false" >> "\$env_file"
    log "Added DEBUG variable to \$env_file"
  fi
}

# Вызываем функцию при загрузке скрипта
ensure_debug_variable

# === Функция для проверки отладочного режима ===
is_debug_enabled() {
  if [ ! -f "\$HOME/.env-aztec-agent" ]; then
    return 1
  fi

  # Загружаем только переменную DEBUG
  debug_value=\$(grep "^DEBUG=" "\$HOME/.env-aztec-agent" | cut -d'=' -f2 | tr -d '"' | tr -d "'" | tr '[:upper:]' '[:lower:]')

  if [ "\$debug_value" = "true" ] || [ "\$debug_value" = "1" ] || [ "\$debug_value" = "yes" ]; then
    return 0
  else
    return 1
  fi
}

# === Функция для отладочного логирования ===
debug_log() {
  if is_debug_enabled; then
    log "DEBUG: \$1"
  fi
}

# === Новая версия функции для проверки комитета и статусов ===
check_committee() {
  debug_log "check_committee started. NOTIFICATION_TYPE=\$NOTIFICATION_TYPE"

  if [ "\$NOTIFICATION_TYPE" -ne 2 ]; then
    debug_log "NOTIFICATION_TYPE != 2, skipping committee check"
    return
  fi

  # Загружаем список валидаторов
  if [ ! -f "\$HOME/.env-aztec-agent" ]; then
    log "Validator file \$HOME/.env-aztec-agent not found"
    return
  fi

  source \$HOME/.env-aztec-agent
  if [ -z "\$VALIDATORS" ]; then
    log "No validators defined in VALIDATORS variable"
    return
  fi

  IFS=',' read -ra VALIDATOR_ARRAY <<< "\$VALIDATORS"
  debug_log "Validators loaded: \${VALIDATOR_ARRAY[*]}"

  container_id=\$(docker ps --format "{{.ID}} {{.Names}}" | grep aztec | grep -vE 'watchtower|otel|prometheus|grafana' | head -n 1 | awk '{print \$1}')
  if [ -z "\$container_id" ]; then
    debug_log "No aztec container found"
    return
  fi
  debug_log "Container ID: \$container_id"

  # --- Получаем данные о комитете ---
  committee_line=\$(docker logs "\$container_id" --tail 20000 2>&1 | grep -a "Computing stats for slot" | tail -n 1)
  [ -z "\$committee_line" ] && { debug_log "No committee line found in logs"; return; }
  debug_log "Committee line found: \$committee_line"

  json_part=\$(echo "\$committee_line" | sed -n 's/.*\({.*}\).*/\1/p')
  [ -z "\$json_part" ] && { debug_log "No JSON part extracted"; return; }
  debug_log "JSON part: \$json_part"

  epoch=\$(echo "\$json_part" | jq -r '.epoch')
  slot=\$(echo "\$json_part" | jq -r '.slot')
  committee=\$(echo "\$json_part" | jq -r '.committee[]')

  if [ -z "\$epoch" ] || [ -z "\$slot" ] || [ -z "\$committee" ]; then
    debug_log "Missing epoch/slot/committee data. epoch=\$epoch, slot=\$slot, committee=\$committee"
    return
  fi
  debug_log "Epoch=\$epoch, Slot=\$slot, Committee=\$committee"

  found_validators=()
  committee_validators=()
  for validator in "\${VALIDATOR_ARRAY[@]}"; do
    validator_lower=\$(echo "\$validator" | tr '[:upper:]' '[:lower:]')
    if echo "\$committee" | grep -qi "\$validator_lower"; then
      # Формируем ссылку в зависимости от сети
      if [[ "\$NETWORK" == "mainnet" ]]; then
        validator_link="[\$validator](https://dashtec.xyz/validators/\$validator)"
      else
        validator_link="[\$validator](https://\${NETWORK}.dashtec.xyz/validators/\$validator)"
      fi
      found_validators+=("\$validator_link")
      committee_validators+=("\$validator_lower")
      debug_log "Validator \$validator found in committee"
    fi
  done

  # Если не нашли валидаторов в комитете - выходим
  if [ \${#found_validators[@]} -eq 0 ]; then
    debug_log "No validators found in committee"
    return
  fi
  debug_log "Found validators: \${found_validators[*]}"

  # === Уведомление о включении в комитет (раз за эпоху) ===
  last_epoch_file="$AGENT_SCRIPT_PATH/aztec_last_committee_epoch"
  if [ ! -f "\$last_epoch_file" ] || ! grep -q "\$epoch" "\$last_epoch_file"; then
    current_time=\$(date '+%Y-%m-%d %H:%M:%S')
    echo "\$epoch" > "\$last_epoch_file"
    # Для каждого валидатора создаём отдельное сообщение и отдельное состояние из 32 слотов
    for idx in "\${!committee_validators[@]}"; do
      v_lower="\${committee_validators[\$idx]}"
      v_link="\${found_validators[\$idx]}"
      epoch_state_file="$AGENT_SCRIPT_PATH/epoch_\${epoch}_\${v_lower}_slots_state"
      epoch_msg_file="$AGENT_SCRIPT_PATH/epoch_\${epoch}_\${v_lower}_message_id"
      # initialize 32 empty slots
      slots_arr=()
      for i in {0..31}; do slots_arr+=("⬜️"); done
      board=\$(build_slots_board "\${slots_arr[@]}")
      committee_message="\$(t "committee_selected") (\$(t "epoch_info" "\$epoch"))!%0A"
      committee_message+="%0A\$(t "found_validators" "\$v_link")%0A"
      committee_message+="%0A\$(t "current_slot" "0")%0A"
      committee_message+="%0ASlots:%0A\${board}%0A"
      committee_message+="%0A\$(t "status_legend")%0A"
      committee_message+="\$(t "status_empty")%0A"
      committee_message+="\$(t "status_attestation_sent")%0A"
      committee_message+="\$(t "status_attestation_missed")%0A"
      committee_message+="\$(t "status_block_mined")%0A"
      committee_message+="\$(t "status_block_missed")%0A"
      committee_message+="\$(t "status_block_proposed")%0A"
      committee_message+="%0A\$(t "server_info" "\$ip")%0A"
      committee_message+="\$(t "time_info" "\$current_time")"

      debug_log "Sending committee message for validator \$v_lower: \$committee_message"
      message_id=\$(send_telegram_message_get_id "\$committee_message")
      if [ -n "\$message_id" ] && [ "\$message_id" != "null" ]; then
        echo "\$message_id" > "\$epoch_msg_file"
      fi
      printf "%s " "\${slots_arr[@]}" > "\$epoch_state_file"
      # Очистим файл учета слотов для этого валидатора
      : > "$AGENT_SCRIPT_PATH/aztec_last_committee_slot_\${v_lower}"
    done
    log "Committee selection notification sent for epoch \$epoch: found validators \${found_validators[*]}"
  else
    debug_log "Already notified for epoch \$epoch"
  fi

  # === Уведомление о статусах аттестаций (обновление отдельных сообщений по каждому валидатору) ===
  last_slot_key="\${epoch}_\${slot}"

  # Проверяем, что слот принадлежит текущей эпохе (очищенной при смене эпохи)
  current_epoch=\$(cat "\$last_epoch_file" 2>/dev/null)
  if [ -n "\$current_epoch" ] && [ "\$epoch" != "\$current_epoch" ]; then
    debug_log "Slot \$slot belongs to epoch \$epoch, but current epoch is \$current_epoch - skipping"
    return
  fi

  activity_line=\$(docker logs "\$container_id" --tail 20000 2>&1 | grep -a "Updating L2 slot \$slot observed activity" | tail -n 1)
  if [ -n "\$activity_line" ]; then
    debug_log "Activity line found: \$activity_line"
    activity_json=\$(echo "\$activity_line" | sed 's/.*observed activity //')

    # Обрабатываем каждого валидатора отдельно
    for idx in "\${!committee_validators[@]}"; do
      v_lower="\${committee_validators[\$idx]}"
      v_link="\${found_validators[\$idx]}"

      last_slot_file="$AGENT_SCRIPT_PATH/aztec_last_committee_slot_\${v_lower}"
      # Пропускаем если уже обработали этот слот для данного валидатора
      if [ -f "\$last_slot_file" ] && grep -q "\$last_slot_key" "\$last_slot_file"; then
        debug_log "Already processed slot \$last_slot_key for \$v_lower"
        continue
      fi

      epoch_state_file="$AGENT_SCRIPT_PATH/epoch_\${epoch}_\${v_lower}_slots_state"
      epoch_msg_file="$AGENT_SCRIPT_PATH/epoch_\${epoch}_\${v_lower}_message_id"
      if [ ! -f "\$epoch_state_file" ]; then
        slots_arr=()
        for i in {0..31}; do slots_arr+=("⬜️"); done
        printf "%s " "\${slots_arr[@]}" > "\$epoch_state_file"
      fi
      read -ra slots_arr < "\$epoch_state_file"

      slot_idx=\$((slot % 32))
      slot_icon=""
      if [ -n "\$activity_json" ]; then
        status=\$(echo "\$activity_json" | jq -r ".\"\$v_lower\"")
        if [ "\$status" != "null" ] && [ -n "\$status" ]; then
          case "\$status" in
            block-proposed) slot_icon="🟪" ;;
            block-mined)    slot_icon="🟦" ;;
            block-missed)   slot_icon="🟨" ;;
            attestation-missed) slot_icon="🟥" ;;
            attestation-sent)   slot_icon="🟩" ;;
          esac
        fi
      fi

      if [ -n "\$slot_icon" ]; then
        slots_arr[\$slot_idx]="\$slot_icon"
        printf "%s " "\${slots_arr[@]}" > "\$epoch_state_file"

        board=\$(build_slots_board "\${slots_arr[@]}")
        current_time=\$(date '+%Y-%m-%d %H:%M:%S')
        updated_message="\$(t "committee_selected") (\$(t "epoch_info" "\$epoch"))!%0A"
        updated_message+="%0A\$(t "found_validators" "\$v_link")%0A"
        updated_message+="%0A\$(t "current_slot" "\$slot")%0A"
        updated_message+="%0ASlots:%0A\${board}%0A"
        updated_message+="%0A\$(t "status_legend")%0A"
        updated_message+="\$(t "status_empty")%0A"
        updated_message+="\$(t "status_attestation_sent")%0A"
        updated_message+="\$(t "status_attestation_missed")%0A"
        updated_message+="\$(t "status_block_mined")%0A"
        updated_message+="\$(t "status_block_missed")%0A"
        updated_message+="\$(t "status_block_proposed")%0A"
        updated_message+="%0A\$(t "server_info" "\$ip")%0A"
        updated_message+="\$(t "time_info" "\$current_time")"

        if [ -f "\$epoch_msg_file" ]; then
          message_id=\$(cat "\$epoch_msg_file")
          if [ -n "\$message_id" ]; then
            debug_log "Editing committee message (id=\$message_id) for epoch \$epoch, slot \$slot, validator \$v_lower"
            edit_telegram_message "\$message_id" "\$updated_message"
          else
            debug_log "Message id missing; sending a fallback message"
            send_telegram_message "\$updated_message"
          fi
        else
          debug_log "Message id file not found; sending a fallback message"
          send_telegram_message "\$updated_message"
        fi

        echo "\$last_slot_key" >> "\$last_slot_file"
        debug_log "Updated slot \$slot_idx for epoch \$epoch with icon \$slot_icon for \$v_lower"
        log "Updated committee stats for epoch \$epoch, slot \$slot, validator \$v_lower"
      else
        debug_log "No mapped status for slot \$slot for \$v_lower"
      fi
    done
  else
    debug_log "No activity line found for slot \$slot"
  fi
}

# === Основная функция: проверка контейнера и сравнение блоков ===
check_blocks() {
  debug_log "check_blocks started at \$(date)"

  container_id=\$(docker ps --format "{{.ID}} {{.Names}}" | grep aztec | grep -vE 'watchtower|otel|prometheus|grafana' | head -n 1 | awk '{print \$1}')
  if [ -z "\$container_id" ]; then
    log "Container 'aztec' not found."
    current_time=\$(date '+%Y-%m-%d %H:%M:%S')
    message="\$(t "container_not_found")%0A\$(t "server_info" "\$ip")%0A\$(t "time_info" "\$current_time")"
    debug_log "Sending container not found message"
    send_telegram_message "\$message"
    exit 1
  fi
  debug_log "Container found: \$container_id"

  # Проверка критических ошибок
  check_critical_errors "\$container_id"

  # Получаем текущий блок из контракта
  # Получаем текущий блок из контракта (совместимость: getPendingBlockNumber для mainnet, getPendingCheckpointNumber для старых контрактов)
  debug_log "Getting block from contract: \$CONTRACT_ADDRESS"
  debug_log "Using RPC: \$RPC_URL"
  block_hex=\$(cast call "\$CONTRACT_ADDRESS" "getPendingBlockNumber()" --rpc-url "\$RPC_URL" 2>&1 | grep -vE '^Warning:' | grep -oE '0x[0-9a-fA-F]+' | head -1)
  [[ "\$block_hex" == *"Error"* || -z "\$block_hex" ]] && block_hex=\$(cast call "\$CONTRACT_ADDRESS" "getPendingCheckpointNumber()" --rpc-url "\$RPC_URL" 2>&1 | grep -vE '^Warning:' | grep -oE '0x[0-9a-fA-F]+' | head -1)
  if [[ "\$block_hex" == *"Error"* || -z "\$block_hex" ]]; then
    log "Block Fetch Error. Check RPC or cast: \$block_hex"
    current_time=\$(date '+%Y-%m-%d %H:%M:%S')
    message="\$(t "block_fetch_error")%0A\$(t "server_info" "\$ip")%0A\$(t "rpc_info" "\$RPC_URL")%0A\$(t "error_info" "\$block_hex")%0A\$(t "time_info" "\$current_time")"
    debug_log "Sending block fetch error message"
    send_telegram_message "\$message"
    exit 1
  fi

  # Конвертируем hex-значение в десятичный
  block_number=\$(hex_to_dec "\$block_hex")
  log "Contract block: \$block_number"

  # Получаем последнюю релевантную строку из логов
  latest_log_line=\$(find_last_log_line "\$container_id")
  debug_log "Latest log line: \$latest_log_line"

  if [ -z "\$latest_log_line" ]; then
    log "No suitable block line found in logs"
    current_time=\$(date '+%Y-%m-%d %H:%M:%S')
    message="\$(t "no_block_in_logs")%0A\$(t "server_info" "\$ip")%0A\$(t "block_info" "\$block_number")%0A\$(t "time_info" "\$current_time")"
    debug_log "Sending no block in logs message"
    send_telegram_message "\$message"
    exit 1
  fi

  # Извлекаем номер блока из найденной строки
  if grep -q 'Sequencer sync check succeeded' <<<"\$latest_log_line"; then
    # формат: ..."worldState":{"number":18254,...
    log_block_number=\$(echo "\$latest_log_line" | grep -o '"worldState":{"number":[0-9]\+' | grep -o '[0-9]\+$')
    debug_log "Extracted from worldState: \$log_block_number"
  else
    # формат: ..."checkpointNumber":59973,... или ..."blockNumber":18254,...
    log_block_number=\$(echo "\$latest_log_line" | grep -oE '"checkpointNumber":[0-9]+|"blockNumber":[0-9]+' | head -n1 | grep -oE '[0-9]+')
    debug_log "Extracted from checkpointNumber/blockNumber: \$log_block_number"
  fi

  if [ -z "\$log_block_number" ]; then
    log "Failed to extract blockNumber from line: \$latest_log_line"
    current_time=\$(date '+%Y-%m-%d %H:%M:%S')
    message="\$(t "failed_extract_block")%0A\$(t "server_info" "\$ip")%0A\$(t "line_info" "\$latest_log_line")%0A\$(t "time_info" "\$current_time")"
    debug_log "Sending failed extract block message"
    send_telegram_message "\$message"
    exit 1
  fi

  log "Latest log block: \$log_block_number"

  # Сравниваем блоки
  if [ "\$log_block_number" -eq "\$block_number" ]; then
    status="\$(t "node_synced" "\$block_number")"
  else
    blocks_diff=\$((block_number - log_block_number))
    status="\$(t "node_behind" "\$blocks_diff")"
    if [ "\$blocks_diff" -gt 3 ]; then
      current_time=\$(date '+%Y-%m-%d %H:%M:%S')
      message="\$(t "node_behind" "\$blocks_diff")%0A\$(t "server_info" "\$ip")%0A\$(t "block_info" "\$block_number")%0A\$(t "log_block_info" "\$log_block_number")%0A\$(t "time_info" "\$current_time")"
      debug_log "Sending node behind message, diff=\$blocks_diff"
      send_telegram_message "\$message"
    fi
  fi

  log "Status: \$status (logs: \$log_block_number, contract: \$block_number)"

  if [ ! -f "\$LOG_FILE.initialized" ]; then
    current_time=\$(date '+%Y-%m-%d %H:%M:%S')

    if [ "\$NOTIFICATION_TYPE" -eq 2 ]; then
      # Полные уведомления (все включено)
      message="\$(t "agent_started")%0A\$(t "server_info" "\$ip")%0A\$status%0A\$(t "notifications_full_info")%0A\$(t "time_info" "\$current_time")"
    else
      # Только критические уведомления
      message="\$(t "agent_started")%0A\$(t "server_info" "\$ip")%0A\$status%0A\$(t "notifications_info")%0A\$(t "time_info" "\$current_time")"
    fi

    debug_log "Sending initialization message"
    send_telegram_message "\$message"
    touch "\$LOG_FILE.initialized"
    echo "v.\$VERSION" >> "\$LOG_FILE"
    echo "INITIALIZED" >> "\$LOG_FILE"
  fi

   # Дополнительные проверки (только если NOTIFICATION_TYPE == 2)
  if [ "\$NOTIFICATION_TYPE" -eq 2 ]; then
    debug_log "Starting committee check"
    check_committee
  else
    debug_log "Skipping committee check (NOTIFICATION_TYPE=\$NOTIFICATION_TYPE)"
  fi

  debug_log "check_blocks completed at \$(date)"
}

# === Function to check publisher balances ===
check_publisher_balances() {
  # Check if monitoring is enabled
  if [ ! -f "\$HOME/.env-aztec-agent" ]; then
    return
  fi

  source \$HOME/.env-aztec-agent

  # Check if monitoring is enabled
  if [ -z "\$MONITORING_PUBLISHERS" ] || [ "\$MONITORING_PUBLISHERS" != "true" ]; then
    debug_log "Publisher balance monitoring is disabled"
    return
  fi

  # Check if publishers are defined
  if [ -z "\$PUBLISHERS" ]; then
    debug_log "No publishers defined for balance monitoring"
    return
  fi

  # Get minimum balance threshold (default 0.15 ETH)
  local min_balance="0.15"
  if [ -n "\$MIN_BALANCE_FOR_WARNING" ]; then
    min_balance="\$MIN_BALANCE_FOR_WARNING"
  fi

  # Get RPC URL from environment
  if [ -z "\$RPC_URL" ]; then
    debug_log "RPC_URL not set, cannot check publisher balances"
    return
  fi

  debug_log "Checking publisher balances (threshold: \$min_balance ETH)"

  # Parse publisher addresses
  IFS=',' read -ra PUBLISHER_ARRAY <<< "\$PUBLISHERS"
  local low_balance_addresses=()
  local low_balance_values=()

  for publisher in "\${PUBLISHER_ARRAY[@]}"; do
    publisher=\$(echo "\$publisher" | xargs | tr '[:upper:]' '[:lower:]') # trim and lowercase
    if [ -z "\$publisher" ]; then
      continue
    fi

    debug_log "Checking balance for publisher: \$publisher"

    # Get balance using cast
    local balance_wei=\$(cast balance "\$publisher" --rpc-url "\$RPC_URL" 2>/dev/null)
    if [ -z "\$balance_wei" ] || [[ "\$balance_wei" == *"Error"* ]]; then
      log "Failed to get balance for publisher \$publisher: \$balance_wei"
      continue
    fi

    # Convert wei to ETH (1 ETH = 10^18 wei)
    # Use awk for reliable formatting with leading zero
    local balance_eth=\$(awk -v wei="\$balance_wei" "BEGIN {printf \"%.6f\", wei / 1000000000000000000}")

    debug_log "Publisher \$publisher balance: \$balance_eth ETH"

    # Compare with threshold
    if awk -v balance="\$balance_eth" -v threshold="\$min_balance" "BEGIN {exit !(balance < threshold)}"; then
      low_balance_addresses+=("\$publisher")
      low_balance_values+=("\$balance_eth")
      log "Low balance detected for publisher \$publisher: \$balance_eth ETH (threshold: \$min_balance ETH)"
    fi
  done

  # Send notification if any addresses have low balance
  if [ \${#low_balance_addresses[@]} -gt 0 ]; then
    current_time=\$(date '+%Y-%m-%d %H:%M:%S')
    # Define backtick character for Markdown formatting
    BT='\`'
    message="\$(t "publisher_balance_warning")%0A%0A"
    for idx in "\${!low_balance_addresses[@]}"; do
      addr="\${low_balance_addresses[\$idx]}"
      bal="\${low_balance_values[\$idx]}"
      # Format: Address in monospace (copyable), Balance on new line
      # Use backticks for Markdown monospace formatting in Telegram
      message+="\${BT}\$addr\${BT}%0ABalance: \$bal ETH%0A%0A"
    done
    message+="\$(t "server_info" "\$ip")%0A"
    message+="\$(t "time_info" "\$current_time")"
    send_telegram_message "\$message"
  else
    debug_log "All publisher balances are above threshold"
  fi
}

# Check publisher balances if monitoring is enabled
check_publisher_balances

check_blocks
EOF

  chmod +x "$AGENT_SCRIPT_PATH/agent.sh"

  # Функция для валидации и очистки файла окружения для systemd
  validate_and_clean_env_file() {
    local env_file="$1"
    local temp_file=$(mktemp)

    sed 's/\r$//' "$env_file" | \
      sed 's/\r/\n/g' | \
      sed 's/\.\([A-Z_]\)/\n\1/g' | \
      sed 's/\.$/\n/' > "${temp_file}.normalized"

    while IFS= read -r line || [ -n "$line" ]; do

      line=$(printf '%s\n' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\r' | sed 's/\.$//' | sed 's/^\.//')

      [[ -z "$line" ]] && continue

      [[ "$line" =~ ^# ]] && continue

      if [[ "$line" =~ = ]]; then
        local key=$(printf '%s\n' "$line" | cut -d'=' -f1 | sed 's/[[:space:]]*$//' | tr -d '\r')
        local value=$(printf '%s\n' "$line" | cut -d'=' -f2- | sed 's/^[[:space:]]*//' | tr -d '\r')

        [[ -z "$key" ]] && continue

        if [[ "$key" =~ ^[A-Za-z_] ]]; then
          if [[ -z "$value" ]]; then
            printf '%s\n' "${key}=" >> "$temp_file"
          else
            if [[ "$value" =~ ^\".*\"$ ]] || [[ "$value" =~ ^\'.*\'$ ]]; then
              printf '%s\n' "${key}=${value}" >> "$temp_file"
            elif [[ "$value" =~ [[:space:]] ]] || [[ "$value" =~ [^A-Za-z0-9_./-] ]] || [[ "$value" =~ ^[0-9] ]]; then
              value=$(printf '%s\n' "$value" | sed 's/"/\\"/g')
              printf '%s\n' "${key}=\"${value}\"" >> "$temp_file"
            else
              printf '%s\n' "${key}=${value}" >> "$temp_file"
            fi
          fi
        fi
      fi
    done < "${temp_file}.normalized"

    if [ -s "$temp_file" ]; then
      sed 's/\r$//' "$temp_file" | sed -e '$a\' > "${temp_file}.final"
      mv "${temp_file}.final" "$temp_file"
    fi

    mv "$temp_file" "$env_file"
    chmod 600 "$env_file"
    rm -f "${temp_file}.normalized"
  }

  validate_and_clean_env_file "$env_file"

  if [ ! -s "$env_file" ]; then
    echo -e "\n${RED}Error: Environment file is empty or invalid${NC}"
    return 1
  fi

  if ! grep -qE '^[A-Za-z_][A-Za-z0-9_]*=' "$env_file"; then
    echo -e "\n${RED}Error: Environment file does not contain valid variables${NC}"
    return 1
  fi

  env_file=$(readlink -f "$env_file" 2>/dev/null || realpath "$env_file" 2>/dev/null || echo "$env_file")
  if [[ ! "$env_file" =~ ^/ ]]; then
    env_file="$HOME/.env-aztec-agent"
  fi

  if [ ! -r "$env_file" ]; then
    echo -e "\n${RED}Error: Environment file $env_file does not exist or is not readable${NC}"
    return 1
  fi

  local agent_script_path=$(readlink -f "$AGENT_SCRIPT_PATH/agent.sh" 2>/dev/null || realpath "$AGENT_SCRIPT_PATH/agent.sh" 2>/dev/null || echo "$AGENT_SCRIPT_PATH/agent.sh")
  if [[ ! "$agent_script_path" =~ ^/ ]]; then
    agent_script_path="$HOME/aztec-monitor-agent/agent.sh"
  fi

  local working_dir=$(readlink -f "$AGENT_SCRIPT_PATH" 2>/dev/null || realpath "$AGENT_SCRIPT_PATH" 2>/dev/null || echo "$AGENT_SCRIPT_PATH")
  if [[ ! "$working_dir" =~ ^/ ]]; then
    working_dir="$HOME/aztec-monitor-agent"
  fi

  if [ ! -f "$agent_script_path" ]; then
    echo -e "\n${RED}Error: Agent script $agent_script_path does not exist${NC}"
    return 1
  fi

  # Определяем пользователя для systemd сервиса
  # Предпочтительно используем SUDO_USER (если скрипт запущен с sudo)
  # Иначе используем USER, иначе whoami как fallback
  local service_user="${SUDO_USER:-${USER:-$(whoami)}}"

  {
    printf '[Unit]\n'
    printf 'Description=Aztec Monitoring Agent\n'
    printf 'After=network.target\n'
    printf '\n'
    printf '[Service]\n'
    printf 'Type=oneshot\n'
    printf 'EnvironmentFile=%s\n' "$env_file"
    printf 'ExecStart=%s\n' "$agent_script_path"
    printf 'User=%s\n' "$service_user"
    printf 'WorkingDirectory=%s\n' "$working_dir"
    printf 'LimitNOFILE=65535\n'
    printf '\n'
    printf '[Install]\n'
    printf 'WantedBy=multi-user.target\n'
  } > /etc/systemd/system/aztec-agent.service

  sed -i 's/\r$//' /etc/systemd/system/aztec-agent.service

  {
    printf '[Unit]\n'
    printf 'Description=Run Aztec Agent every 37 seconds\n'
    printf 'Requires=aztec-agent.service\n'
    printf '\n'
    printf '[Timer]\n'
    printf 'OnBootSec=37\n'
    printf 'OnUnitActiveSec=37\n'
    printf 'AccuracySec=1us\n'
    printf '\n'
    printf '[Install]\n'
    printf 'WantedBy=timers.target\n'
  } > /etc/systemd/system/aztec-agent.timer

  sed -i 's/\r$//' /etc/systemd/system/aztec-agent.timer

  if ! systemd-analyze verify /etc/systemd/system/aztec-agent.service 2>/dev/null; then
    echo -e "\n${YELLOW}Warning: systemd-analyze verify failed, but continuing...${NC}"
  fi

  # Активируем и запускаем timer
  if ! systemctl daemon-reload; then
    echo -e "\n${RED}Error: Failed to reload systemd daemon${NC}"
    return 1
  fi

  # Проверяем, что сервис может быть загружен
  if ! systemctl show aztec-agent.service &>/dev/null; then
    echo -e "\n${RED}Error: Failed to load aztec-agent.service${NC}"
    echo -e "${YELLOW}Checking service file syntax...${NC}"
    systemctl cat aztec-agent.service 2>&1 | head -20
    return 1
  fi

  if ! systemctl enable aztec-agent.timer; then
    echo -e "\n${RED}Error: Failed to enable aztec-agent.timer${NC}"
    return 1
  fi

  if ! systemctl start aztec-agent.timer; then
    echo -e "\n${RED}Error: Failed to start aztec-agent.timer${NC}"
    systemctl status aztec-agent.timer --no-pager
    return 1
  fi

  # Проверяем статус
  if systemctl is-active --quiet aztec-agent.timer; then
    echo -e "\n${GREEN}$(t "agent_systemd_added")${NC}"
    echo -e "${GREEN}$(t "agent_timer_status")$(systemctl status aztec-agent.timer --no-pager -q | grep Active)${NC}"
  else
    echo -e "\n${RED}$(t "agent_timer_error")${NC}"
    systemctl status aztec-agent.timer --no-pager
    return 1
  fi
}
