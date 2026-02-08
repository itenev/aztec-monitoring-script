source scripts/dependencies.sh
source scripts/check_updates_safely.sh
source scripts/check_error_definitions_updates_safely.sh
source scripts/check_aztec_container_logs.sh
source scripts/view_container_logs.sh
source scripts/find_rollup_address.sh
source scripts/find_peer_id.sh
source scripts/find_governance_proposer_payload.sh
source scripts/create_systemd_agent.sh
source scripts/remove_systemd_agent.sh
source scripts/check_proven_block.sh
source scripts/change_rpc_url.sh
source scripts/install_aztec.sh
source scripts/delete_aztec.sh
source scripts/update_aztec.sh
source scripts/downgrade_aztec.sh
source scripts/check_validator.sh
source scripts/stop_aztec_containers.sh
source scripts/start_aztec_containers.sh
source scripts/check_aztec_version.sh
source scripts/generate_bls_keys.sh
source scripts/approve.sh
source scripts/stake.sh
source scripts/claim_rewards.sh
source scripts/manage_publisher_balance_monitoring.sh
source scripts/utils.sh
source scripts/translations.sh
#!/bin/bash



# === Language settings ===
LANG=""


# Translation function
t() {
  local key=$1
  echo "${TRANSLATIONS[$LANG,$key]}"
}

# Initialize languages

SCRIPT_VERSION="2.8.0"
ERROR_DEFINITIONS_VERSION="1.0.0"

# Function to load configuration from config.json
load_config() {
  CONFIG_FILE="$SCRIPT_DIR/config.json"
  if [ -f "$CONFIG_FILE" ]; then
    CONTRACT_ADDRESS=$(jq -r '.CONTRACT_ADDRESS' "$CONFIG_FILE")
    CONTRACT_ADDRESS_MAINNET=$(jq -r '.CONTRACT_ADDRESS_MAINNET' "$CONFIG_FILE")
    GSE_ADDRESS_TESTNET=$(jq -r '.GSE_ADDRESS_TESTNET' "$CONFIG_FILE")
    GSE_ADDRESS_MAINNET=$(jq -r '.GSE_ADDRESS_MAINNET' "$CONFIG_FILE")
    FEE_RECIPIENT_ZERO=$(jq -r '.FEE_RECIPIENT_ZERO' "$CONFIG_FILE")
  else
    echo -e "${RED}Error: config.json not found. Please create it in the same directory as the script.${NC}"
    exit 1
  fi
}


# Determine script directory for local file access (security: avoid remote code execution)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
load_config



# Function signature for contract calls
FUNCTION_SIG="getPendingCheckpointNumber()"

# Required tools
REQUIRED_TOOLS=("cast" "curl" "grep" "sed" "jq" "bc" "python3")

# Agent paths
AGENT_SCRIPT_PATH="$HOME/aztec-monitor-agent"
LOG_FILE="$AGENT_SCRIPT_PATH/agent.log"

function show_logo() {
    # Inline logo function (merged from logo.sh)
    local b=$'\033[34m' # Blue
    local y=$'\033[33m' # Yellow
    local r=$'\033[0m'  # Reset

    echo
    echo
    echo -e "${NC}$(t "welcome")${NC}"
    echo
    echo "${b}$(echo "  █████╗ ███████╗████████╗███████╗ ██████╗" | sed -E "s/(█+)/${y}\1${b}/g")${r}"
    echo "${b}$(echo " ██╔══██╗╚══███╔╝╚══██╔══╝██╔════╝██╔════╝" | sed -E "s/(█+)/${y}\1${b}/g")${r}"
    echo "${b}$(echo " ███████║  ███╔╝    ██║   █████╗  ██║" | sed -E "s/(█+)/${y}\1${b}/g")${r}"
    echo "${b}$(echo " ██╔══██║ ███╔╝     ██║   ██╔══╝  ██║" | sed -E "s/(█+)/${y}\1${b}/g")${r}"
    echo "${b}$(echo " ██║  ██║███████╗   ██║   ███████╗╚██████╗" | sed -E "s/(█+)/${y}\1${b}/g")${r}"
    echo "${b}$(echo " ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚══════╝ ╚═════╝" | sed -E "s/(█+)/${y}\1${b}/g")${r}"
    echo

    # Information in frame
    local info_lines=(
      " Made by Pittpv"
      " Feedback & Support in Tg: https://t.me/+DLsyG6ol3SFjM2Vk"
      " Donate"
      "  EVM: 0x4FD5eC033BA33507E2dbFE57ca3ce0A6D70b48Bf"
      "  SOL: C9TV7Q4N77LrKJx4njpdttxmgpJ9HGFmQAn7GyDebH4R"
    )

    # Calculate maximum line length (accounting for Unicode, without colors)
    local max_len=0
    for line in "${info_lines[@]}"; do
      local clean_line=$(echo "$line" | sed -E 's/\x1B\[[0-9;]*[mK]//g')
      local line_length=$(echo -n "$clean_line" | wc -m)
      (( line_length > max_len )) && max_len=$line_length
    done

    # Frames
    local top_border="╔$(printf '═%.0s' $(seq 1 $((max_len + 2))))╗"
    local bottom_border="╚$(printf '═%.0s' $(seq 1 $((max_len + 2))))╝"

    # Print frame
    echo -e "${b}${top_border}${r}"
    for line in "${info_lines[@]}"; do
      local clean_line=$(echo "$line" | sed -E 's/\x1B\[[0-9;]*[mK]//g')
      local line_length=$(echo -n "$clean_line" | wc -m)
      local padding=$((max_len - line_length))
      printf "${b}║ ${y}%s%*s ${b}║\n" "$line" "$padding" ""
    done
    echo -e "${b}${bottom_border}${r}"
    echo
}



      echo -e "\n${GREEN}$(t "env_created")${NC}"
  else
      source .env-aztec-agent
      DISPLAY_NETWORK="${NETWORK:-testnet}"
      echo -e "\n${GREEN}$(t "env_exists") $RPC_URL, NETWORK: $DISPLAY_NETWORK${NC}"
  fi

  # === Проверяем и добавляем ключ VERSION в ~/.env-aztec-agent ===
  # Если ключа VERSION в .env-aztec-agent нет – дописать его, не затронув остальные переменные
  INSTALLED_VERSION=$(grep '^VERSION=' ~/.env-aztec-agent | cut -d'=' -f2)

  if [ -z "$INSTALLED_VERSION" ]; then
    printf 'VERSION=%s\n' "$SCRIPT_VERSION" >> ~/.env-aztec-agent
    INSTALLED_VERSION="$SCRIPT_VERSION"
  elif [ "$INSTALLED_VERSION" != "$SCRIPT_VERSION" ]; then
  # Обновляем строку VERSION в .env-aztec-agent
    sed -i "s/^VERSION=.*/VERSION=$SCRIPT_VERSION/" ~/.env-aztec-agent
    INSTALLED_VERSION="$SCRIPT_VERSION"
  fi

  # === Используем локальный version_control.json для определения последней версии ===
  # Security: Use local file instead of remote download to prevent supply chain attacks
  # По умолчанию показываем только локальную версию. Для проверки обновлений используйте опциональную функцию check_updates_safely()
  LOCAL_VC_FILE="$SCRIPT_DIR/version_control.json"
  # Читаем локальный JSON, отбираем массив .[].VERSION, сортируем, берём последний
  if [ -f "$LOCAL_VC_FILE" ] && local_data=$(cat "$LOCAL_VC_FILE"); then
    LOCAL_LATEST_VERSION=$(echo "$local_data" | jq -r '.[].VERSION' | sort -V | tail -n1)
  else
    LOCAL_LATEST_VERSION=""
  fi

  # === Выводим текущую версию из локального файла ===
  echo -e "\n${CYAN}$(t "current_script_version") ${INSTALLED_VERSION}${NC}"
  if [ -n "$LOCAL_LATEST_VERSION" ]; then
    if [ "$LOCAL_LATEST_VERSION" != "$INSTALLED_VERSION" ]; then
      echo -e "${YELLOW}$(t "new_version_available") ${LOCAL_LATEST_VERSION}. $(t "new_version_update")${NC}"
      echo -e "${BLUE}$(t "note_check_updates_safely")${NC}"
    else
      echo -e "${GREEN}$(t "local_version_up_to_date")${NC}"
    fi
  fi
}

# === Безопасная проверка обновлений с подтверждением и проверкой хешей ===
# Security: Optional update check with hash verification to prevent supply chain attacks
check_updates_safely() {
  echo -e "\n${BLUE}=== $(t "safe_update_check") ===${NC}"
  echo -e "\n${YELLOW}$(t "update_check_warning")${NC}"
  echo -e "${YELLOW}$(t "file_not_executed_auto")${NC}"
  while true; do
    read -p "$(t "continue_prompt"): " confirm
    if [[ "$confirm" =~ ^[YyNn]$ ]]; then
      break
    else
      echo -e "${RED}Invalid choice. Please enter Y or n.${NC}"
    fi
  done
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}$(t "update_check_cancelled")${NC}"
    return 0
  fi

  # Функция для сравнения версий (возвращает 0 если версия1 > версия2)
  version_gt() {
    if [ "$1" = "$2" ]; then
      return 1
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    for ((i=0; i<${#ver1[@]}; i++)); do
      if [[ -z ${ver2[i]} ]]; then
        ver2[i]=0
      fi
      if ((10#${ver1[i]} > 10#${ver2[i]})); then
        return 0
      fi
      if ((10#${ver1[i]} < 10#${ver2[i]})); then
        return 1
      fi
    done
    return 1
  }

  # Функция для показа обновлений из данных файла
  show_updates_from_data() {
    local data="$1"
    local base_version="$2"
    local updates_shown=0

    echo "$data" | jq -c '.[]' | while read -r update; do
      version=$(echo "$update" | jq -r '.VERSION')
      date=$(echo "$update" | jq -r '.UPDATE_DATE')
      notice=$(echo "$update" | jq -r '.NOTICE // empty')
      color_name=$(echo "$update" | jq -r '.COLOR // empty' | tr '[:upper:]' '[:lower:]')

      # Получаем цвет по имени
      color_code=""
      case "$color_name" in
        red) color_code="$RED" ;;
        green) color_code="$GREEN" ;;
        yellow) color_code="$YELLOW" ;;
        blue) color_code="$BLUE" ;;
        cyan) color_code="$CYAN" ;;
        violet) color_code="$VIOLET" ;;
      esac

      if [ -n "$base_version" ] && version_gt "$version" "$base_version"; then
        echo -e "\n${GREEN}$(t "version_label") $version (${date})${NC}"
        echo "$update" | jq -r '.CHANGES[]' | while read -r change; do
          echo -e "  • ${YELLOW}$change${NC}"
        done
        # Выводим NOTICE если он есть
        if [ -n "$notice" ] && [ "$notice" != "null" ] && [ "$notice" != "" ]; then
          if [ -n "$color_code" ]; then
            echo -e "\n  ${color_code}NOTICE: $notice${NC}"
          else
            echo -e "\n  NOTICE: $notice"
          fi
        fi
        updates_shown=1
      elif [ -z "$base_version" ]; then
        # Если базовая версия не указана, показываем все обновления новее скрипта
        if version_gt "$version" "$INSTALLED_VERSION"; then
          echo -e "\n${GREEN}$(t "version_label") $version (${date})${NC}"
          echo "$update" | jq -r '.CHANGES[]' | while read -r change; do
            echo -e "  • ${YELLOW}$change${NC}"
          done
          # Выводим NOTICE если он есть
          if [ -n "$notice" ] && [ "$notice" != "null" ] && [ "$notice" != "" ]; then
            if [ -n "$color_code" ]; then
              echo -e "\n  ${color_code}NOTICE: $notice${NC}"
            else
              echo -e "\n  NOTICE: $notice"
            fi
          fi
          updates_shown=1
        fi
      fi
    done

    return $updates_shown
  }

  LOCAL_VC_FILE="$SCRIPT_DIR/version_control.json"
  REMOTE_VC_URL="https://raw.githubusercontent.com/pittpv/aztec-monitoring-script/main/other/version_control.json"
  TEMP_VC_FILE=$(mktemp)

  # === Шаг 1: Проверка локального файла ===
  echo -e "\n${CYAN}$(t "current_installed_version") ${INSTALLED_VERSION}${NC}"

  LOCAL_LATEST_VERSION=""
  local_data=""
  if [ -f "$LOCAL_VC_FILE" ] && local_data=$(cat "$LOCAL_VC_FILE" 2>/dev/null); then
    LOCAL_LATEST_VERSION=$(echo "$local_data" | jq -r '.[].VERSION' | sort -V | tail -n1 2>/dev/null)
    echo -e "${CYAN}$(t "local_version") ${LOCAL_LATEST_VERSION}${NC}"
  fi

  # === Шаг 2: Загрузка удаленного файла ===
  echo -e "\n${CYAN}$(t "downloading_version_control")${NC}"
  if ! curl -fsSL "$REMOTE_VC_URL" -o "$TEMP_VC_FILE"; then
    echo -e "${RED}$(t "failed_download_version_control")${NC}"
    rm -f "$TEMP_VC_FILE"
    return 1
  fi

  # Вычисляем SHA256 хеш загруженного файла
  if command -v sha256sum >/dev/null 2>&1; then
    DOWNLOADED_HASH=$(sha256sum "$TEMP_VC_FILE" | cut -d' ' -f1)
    echo -e "${GREEN}$(t "downloaded_file_sha256") ${DOWNLOADED_HASH}${NC}"
    echo -e "${YELLOW}$(t "verify_hash_match")${NC}"
  elif command -v shasum >/dev/null 2>&1; then
    DOWNLOADED_HASH=$(shasum -a 256 "$TEMP_VC_FILE" | cut -d' ' -f1)
    echo -e "${GREEN}$(t "downloaded_file_sha256") ${DOWNLOADED_HASH}${NC}"
    echo -e "${YELLOW}$(t "verify_hash_match")${NC}"
  fi

  # Запрашиваем подтверждение проверки хеша
  while true; do
    read -p "$(t "hash_verified_prompt"): " hash_verified
    if [[ "$hash_verified" =~ ^[YyNn]$ ]]; then
      break
    else
      echo -e "${RED}Invalid choice. Please enter Y or n.${NC}"
    fi
  done
  if [[ ! "$hash_verified" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}$(t "update_check_cancelled")${NC}"
    rm -f "$TEMP_VC_FILE"
    return 0
  fi

  # Парсим удаленный файл
  if ! remote_data=$(cat "$TEMP_VC_FILE" 2>/dev/null); then
    echo -e "${RED}$(t "failed_download_version_control")${NC}"
    rm -f "$TEMP_VC_FILE"
    return 1
  fi

  REMOTE_LATEST_VERSION=$(echo "$remote_data" | jq -r '.[].VERSION' | sort -V | tail -n1 2>/dev/null)
  echo -e "${CYAN}$(t "remote_version") ${REMOTE_LATEST_VERSION}${NC}"

  # === Шаг 3: Обработка файла version_control.json ===
  if [ -z "$LOCAL_LATEST_VERSION" ] || [ ! -f "$LOCAL_VC_FILE" ]; then
    # Случай 1: Локального файла нет - сохраняем удаленный файл
    echo -e "\n${CYAN}$(t "version_control_saving")${NC}"
    if cp "$TEMP_VC_FILE" "$LOCAL_VC_FILE"; then
      echo -e "${GREEN}$(t "version_control_saved")${NC}"
    else
      echo -e "${RED}$(t "version_control_save_failed")${NC}"
      rm -f "$TEMP_VC_FILE"
      return 1
    fi
  else
    # Локальный файл существует - сравниваем версии файлов
    if [ "$LOCAL_LATEST_VERSION" = "$REMOTE_LATEST_VERSION" ]; then
      # Версии файлов совпадают - файл не сохраняем
      echo -e "\n${GREEN}$(t "local_version_up_to_date")${NC}"
    elif [ -n "$REMOTE_LATEST_VERSION" ] && [ -n "$LOCAL_LATEST_VERSION" ] && version_gt "$REMOTE_LATEST_VERSION" "$LOCAL_LATEST_VERSION"; then
      # Удаленная версия новее локальной - сохраняем обновленный файл
      echo -e "\n${CYAN}$(t "version_control_saving")${NC}"
      if cp "$TEMP_VC_FILE" "$LOCAL_VC_FILE"; then
        echo -e "${GREEN}$(t "version_control_saved")${NC}"
      else
        echo -e "${RED}$(t "version_control_save_failed")${NC}"
        rm -f "$TEMP_VC_FILE"
        return 1
      fi
    else
      # Локальная версия новее удаленной или версии не удалось сравнить
      echo -e "\n${YELLOW}$(t "local_remote_versions_differ")${NC}"
      if [ -n "$LOCAL_LATEST_VERSION" ] && [ -n "$REMOTE_LATEST_VERSION" ] && version_gt "$LOCAL_LATEST_VERSION" "$REMOTE_LATEST_VERSION"; then
        echo -e "${BLUE}$(t "error_def_local_newer")${NC}"
      fi
    fi
  fi

  # === Шаг 4: Проверка обновлений для скрипта ===
  # Используем актуальную версию (удаленную, если она новее, иначе локальную)
  if [ -n "$REMOTE_LATEST_VERSION" ] && [ -n "$LOCAL_LATEST_VERSION" ] && version_gt "$REMOTE_LATEST_VERSION" "$LOCAL_LATEST_VERSION"; then
    ACTUAL_LATEST_VERSION="$REMOTE_LATEST_VERSION"
    ACTUAL_DATA="$remote_data"
  elif [ -n "$LOCAL_LATEST_VERSION" ]; then
    ACTUAL_LATEST_VERSION="$LOCAL_LATEST_VERSION"
    ACTUAL_DATA="$local_data"
  elif [ -n "$REMOTE_LATEST_VERSION" ]; then
    ACTUAL_LATEST_VERSION="$REMOTE_LATEST_VERSION"
    ACTUAL_DATA="$remote_data"
  else
    ACTUAL_LATEST_VERSION=""
    ACTUAL_DATA=""
  fi

  if [ -n "$ACTUAL_LATEST_VERSION" ] && [ -n "$INSTALLED_VERSION" ]; then
    if version_gt "$ACTUAL_LATEST_VERSION" "$INSTALLED_VERSION"; then
      # Версия скрипта устарела - показываем обновления
      echo -e "\n${YELLOW}$(t "new_version_available") ${ACTUAL_LATEST_VERSION}${NC}"
      echo -e "${BLUE}=== $(t "update_changes") ===${NC}"
      show_updates_from_data "$ACTUAL_DATA" "$INSTALLED_VERSION"
      echo -e "\n${BLUE}$(t "note_update_manually")${NC}"
    elif [ "$ACTUAL_LATEST_VERSION" = "$INSTALLED_VERSION" ]; then
      # Версия скрипта актуальна
      echo -e "\n${GREEN}$(t "version_up_to_date")${NC}"
    fi
  fi

  # Удаляем временный файл
  rm -f "$TEMP_VC_FILE"
}


  # Сравниваем с локальным файлом
  LOCAL_ERROR_FILE="$SCRIPT_DIR/error_definitions.json"

  # Извлекаем версию из удалённого файла
  if command -v jq >/dev/null 2>&1; then
    REMOTE_VERSION=$(jq -r '.version // "unknown"' "$TEMP_ERROR_FILE" 2>/dev/null)
  else
    REMOTE_VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$TEMP_ERROR_FILE" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "unknown")
  fi

  if [ ! -f "$LOCAL_ERROR_FILE" ]; then
    # Случай 1: Локального файла нет - сохраняем удалённый файл
    echo -e "\n${YELLOW}$(t "local_error_def_not_found")${NC}"
    echo -e "${BLUE}$(t "remote_version") ${REMOTE_VERSION}${NC}"
    echo -e "${BLUE}$(t "expected_version") ${ERROR_DEFINITIONS_VERSION}${NC}"

    echo -e "\n${CYAN}$(t "error_def_saving")${NC}"
    if cp "$TEMP_ERROR_FILE" "$LOCAL_ERROR_FILE"; then
      echo -e "${GREEN}$(t "error_def_saved")${NC}"
      echo -e "${BLUE}$(t "local_version") ${REMOTE_VERSION}${NC}"
    else
      echo -e "${RED}$(t "error_def_save_failed")${NC}"
      rm -f "$TEMP_ERROR_FILE"
      return 1
    fi
  else
    # Локальный файл существует - сравниваем версии
    if command -v sha256sum >/dev/null 2>&1; then
      LOCAL_HASH=$(sha256sum "$LOCAL_ERROR_FILE" | cut -d' ' -f1)
    elif command -v shasum >/dev/null 2>&1; then
      LOCAL_HASH=$(shasum -a 256 "$LOCAL_ERROR_FILE" | cut -d' ' -f1)
    fi

    # Извлекаем версию из локального файла
    if command -v jq >/dev/null 2>&1; then
      LOCAL_VERSION=$(jq -r '.version // "unknown"' "$LOCAL_ERROR_FILE" 2>/dev/null)
    else
      LOCAL_VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$LOCAL_ERROR_FILE" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "unknown")
    fi

    # Показываем версии
    echo -e "\n${CYAN}$(t "version_label")${NC}"
    echo -e "${BLUE}$(t "local_version") ${LOCAL_VERSION}${NC}"
    echo -e "${BLUE}$(t "remote_version") ${REMOTE_VERSION}${NC}"
    echo -e "${BLUE}$(t "expected_version") ${ERROR_DEFINITIONS_VERSION}${NC}"

    # Проверяем хеши
    if [ "$DOWNLOADED_HASH" = "$LOCAL_HASH" ]; then
      # Хеши совпадают - файлы идентичны
      if [ "$LOCAL_VERSION" = "$REMOTE_VERSION" ]; then
        # Случай 2: Версии одинаковые
        up_to_date_msg=$(t "error_def_version_up_to_date")
        up_to_date_msg=$(echo "$up_to_date_msg" | sed "s/%s/$LOCAL_VERSION/")
        echo -e "\n${GREEN}${up_to_date_msg}${NC}"
      else
        echo -e "\n${YELLOW}$(t "version_mismatch_warning")${NC}"
      fi
    else
      # Хеши различаются - проверяем версии
      if [ "$LOCAL_VERSION" = "$REMOTE_VERSION" ]; then
        echo -e "\n${YELLOW}$(t "local_remote_versions_differ")${NC}"
        echo -e "${BLUE}$(t "local_hash") ${LOCAL_HASH}${NC}"
        echo -e "${BLUE}$(t "remote_hash") ${DOWNLOADED_HASH}${NC}"
        echo -e "${YELLOW}$(t "error_def_hash_mismatch")${NC}"
      elif [ "$REMOTE_VERSION" != "unknown" ] && [ "$LOCAL_VERSION" != "unknown" ] && version_gt "$REMOTE_VERSION" "$LOCAL_VERSION"; then
        # Случай 3: Удалённая версия выше - обновляем файл
        newer_version_msg=$(t "error_def_newer_version_available")
        newer_version_msg=$(echo "$newer_version_msg" | sed "s/%s/$REMOTE_VERSION/" | sed "s/%s/$LOCAL_VERSION/")
        echo -e "\n${YELLOW}${newer_version_msg}${NC}"
        echo -e "${BLUE}$(t "local_hash") ${LOCAL_HASH}${NC}"
        echo -e "${BLUE}$(t "remote_hash") ${DOWNLOADED_HASH}${NC}"

        echo -e "\n${CYAN}$(t "error_def_updating")${NC}"
        if cp "$TEMP_ERROR_FILE" "$LOCAL_ERROR_FILE"; then
          echo -e "${GREEN}$(t "error_def_updated")${NC}"
          echo -e "${BLUE}$(t "local_version") ${REMOTE_VERSION}${NC}"
        else
          echo -e "${RED}$(t "error_def_update_failed")${NC}"
          rm -f "$TEMP_ERROR_FILE"
          return 1
        fi
      else
        # Удалённая версия ниже или равна, или версии неизвестны - не обновляем
        echo -e "\n${YELLOW}$(t "local_remote_versions_differ")${NC}"
        echo -e "${BLUE}$(t "local_hash") ${LOCAL_HASH}${NC}"
        echo -e "${BLUE}$(t "remote_hash") ${DOWNLOADED_HASH}${NC}"
        if [ "$LOCAL_VERSION" != "unknown" ] && [ "$REMOTE_VERSION" != "unknown" ]; then
          version_diff_msg=$(t "version_difference")
          version_diff_msg=$(echo "$version_diff_msg" | sed "s/%s/$LOCAL_VERSION/" | sed "s/%s/$REMOTE_VERSION/")
          echo -e "${YELLOW}${version_diff_msg}${NC}"
        fi
        if [ "$LOCAL_VERSION" = "unknown" ] || [ "$REMOTE_VERSION" = "unknown" ]; then
          echo -e "${YELLOW}$(t "error_def_version_unknown")${NC}"
        else
          echo -e "${BLUE}$(t "error_def_local_newer")${NC}"
        fi
      fi
    fi

    # Проверяем соответствие версии скрипта
    if [ "$REMOTE_VERSION" != "$ERROR_DEFINITIONS_VERSION" ]; then
      version_mismatch_msg=$(t "version_script_mismatch")
      version_mismatch_msg=$(echo "$version_mismatch_msg" | sed "s/%s/$REMOTE_VERSION/" | sed "s/%s/$ERROR_DEFINITIONS_VERSION/")
      echo -e "\n${YELLOW}${version_mismatch_msg}${NC}"
    fi
  fi

  # Удаляем временный файл
  rm -f "$TEMP_ERROR_FILE"
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
            # Используем sed для извлечения содержимого между "errors": [ и ]
            errors_section=$(sed -n '/"errors":\s*\[/,/\]/{ /"errors":\s*\[/d; /\]/d; p; }' "$ERROR_DEFINITIONS_FILE" 2>/dev/null)

            # Парсим объекты из массива errors
            # Собираем объекты по фигурным скобкам, учитывая многострочность
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
                    # Используем sed для более надёжного извлечения значений
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
            ["ERROR: cli Error: World state trees are out of sync, please delete your data directory and re-sync"]="1. Stop the node container. Use option 14\n2. Delete data from the folder: rm -rf $HOME/.aztec/testnet/data/\n3. Run the container. Use option 13"
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
    block_hex=$(cast call "$contract_address" "$FUNCTION_SIG" --rpc-url "$rpc_url" 2>/dev/null)
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





  _find_peer_id_worker &
  worker_pid=$!
  spinner $worker_pid
  wait $worker_pid

  if [ ! -s /tmp/peer_id.tmp ]; then
    echo -e "${RED}$(t "peer_not_found")${NC}"
    rm -f /tmp/peer_id.tmp
    return 1
  fi

  peer_id=$(< /tmp/peer_id.tmp)
  rm -f /tmp/peer_id.tmp

  if [ -z "$peer_id" ]; then
    echo -e "${RED}$(t "peer_not_found")${NC}"
    return 1
  else
    echo -e "\n${GREEN}$(t "peer_found")${NC}: $peer_id"
    return 0
  fi
}


  # Запускаем поиск в фоне и спиннер
  _find_payloads_worker &
  worker_pid=$!
  spinner $worker_pid
  wait $worker_pid

  if [ ! -s /tmp/gov_payloads.tmp ]; then
    echo -e "\n${RED}$(t "gov_not_found")${NC}"
    rm -f /tmp/gov_payloads.tmp
    return 1
  fi

  mapfile -t payloads_array < /tmp/gov_payloads.tmp
  rm -f /tmp/gov_payloads.tmp

  echo -e "\n${GREEN}$(t "gov_found_results")${NC}"
  for p in "${payloads_array[@]}"; do
    echo "• $p"
  done

  if [ "${#payloads_array[@]}" -gt 1 ]; then
    echo -e "\n${RED}$(t "gov_changed")${NC}"
    for ((i = 1; i < ${#payloads_array[@]}; i++)); do
      echo -e "${YELLOW}$(t "gov_was") ${payloads_array[i-1]} → $(t "gov_now") ${payloads_array[i]}${NC}"
    done
  else
    echo -e "\n${GREEN}$(t "gov_no_changes")${NC}"
  fi

  return 0
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
FUNCTION_SIG="$FUNCTION_SIG"
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
LOG_FILE="$LOG_FILE"
LANG="$LANG"


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
  debug_log "Getting block from contract: \$CONTRACT_ADDRESS"
  debug_log "Using RPC: \$RPC_URL"
  debug_log "Using RPC: \$FUNCTION_SIG"
  debug_log "Command: \$(cast call "\$CONTRACT_ADDRESS" "\$FUNCTION_SIG" --rpc-url "\$RPC_URL" 2>&1)"
  # Выполняем cast call и фильтруем предупреждения, оставляя только hex-значение
  # Фильтруем строки, начинающиеся с "Warning:", и извлекаем hex-значение (0x...)
  block_hex=\$(cast call "\$CONTRACT_ADDRESS" "\$FUNCTION_SIG" --rpc-url "\$RPC_URL" 2>&1 | grep -vE '^Warning:' | grep -oE '0x[0-9a-fA-F]+' | head -1)
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

# === Remove cron task and agent ===
remove_cron_agent() {
  echo -e "\n${BLUE}$(t "removing_agent")${NC}"
  crontab -l 2>/dev/null | grep -v "$AGENT_SCRIPT_PATH/agent.sh" | crontab -
  rm -rf "$AGENT_SCRIPT_PATH"
  echo -e "\n${GREEN}$(t "agent_removed")${NC}"
}






install_aztec_node_main() {
    set -e

    # Вызываем проверку портов
    check_and_set_ports || return 2

    echo -e "\n${GREEN}$(t "installing_deps")${NC}"
    sudo apt update
    sudo apt install curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev -y

    echo -e "\n${GREEN}$(t "deps_installed")${NC}"

    echo -e "\n${GREEN}$(t "checking_docker")${NC}"

    if ! command -v docker &>/dev/null; then
        echo -e "\n${RED}$(t "docker_not_found")${NC}"
        echo -e "Please install Docker manually and run the script again."
        return 1
    fi

    if ! docker compose version &>/dev/null; then
        echo -e "\n${RED}$(t "docker_compose_not_found")${NC}"
        echo -e "Please install Docker Compose manually and run the script again."
        return 1
    fi

delete_aztec_node() {
    echo -e "\n${RED}=== $(t "delete_node") ===${NC}"

    # Основной запрос
    while :; do
        read -p "$(t "delete_confirm") " -n 1 -r
        [[ $REPLY =~ ^[YyNn]$ ]] && break
        echo -e "\n${YELLOW}$(t "enter_yn")${NC}"
    done
    echo  # Фиксируем окончательный перевод строки

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}$(t "stopping_containers")${NC}"
        docker compose -f "$HOME/aztec/docker-compose.yml" down || true

        echo -e "${YELLOW}$(t "removing_node_data")${NC}"
        if [ -d "$HOME/.aztec" ] && [ -O "$HOME/.aztec" ]; then
            rm -rf "$HOME/.aztec"
        else
            sudo rm -rf "$HOME/.aztec"
        fi
        if [ -d "$HOME/aztec" ] && [ -O "$HOME/aztec" ]; then
            rm -rf "$HOME/aztec"
        else
            sudo rm -rf "$HOME/aztec"
        fi

        echo -e "${GREEN}$(t "node_deleted")${NC}"

        # Проверяем Watchtower
        if [ -d "$HOME/watchtower" ] || docker ps -a --format '{{.Names}}' | grep -q 'watchtower'; then
            while :; do
                read -p "$(t "delete_watchtower_confirm") " -n 1 -r
                [[ $REPLY =~ ^[YyNn]$ ]] && break
                echo -e "\n${YELLOW}$(t "enter_yn")${NC}"
            done
            echo

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}$(t "stopping_watchtower")${NC}"
                docker stop watchtower 2>/dev/null || true
                docker rm watchtower 2>/dev/null || true
                [ -f "$HOME/watchtower/docker-compose.yml" ] && docker compose -f "$HOME/watchtower/docker-compose.yml" down || true

                echo -e "${YELLOW}$(t "removing_watchtower_data")${NC}"
                if [ -d "$HOME/watchtower" ] && [ -O "$HOME/watchtower" ]; then
                    rm -rf "$HOME/watchtower"
                else
                    sudo rm -rf "$HOME/watchtower"
                fi
                echo -e "${GREEN}$(t "watchtower_deleted")${NC}"
            else
                echo -e "${GREEN}$(t "watchtower_kept")${NC}"
            fi
        fi

        # Проверяем web3signer
        if docker ps -a --format '{{.Names}}' | grep -q 'web3signer'; then
            while :; do
                read -p "$(t "delete_web3signer_confirm") " -n 1 -r
                [[ $REPLY =~ ^[YyNn]$ ]] && break
                echo -e "\n${YELLOW}$(t "enter_yn")${NC}"
            done
            echo

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}$(t "stopping_web3signer")${NC}"
                docker stop web3signer 2>/dev/null || true
                docker rm web3signer 2>/dev/null || true

                echo -e "${YELLOW}$(t "removing_web3signer_data")${NC}"
                # Данные web3signer находятся в $HOME/aztec/keys, который уже удален выше
                echo -e "${GREEN}$(t "web3signer_deleted")${NC}"
            else
                echo -e "${GREEN}$(t "web3signer_kept")${NC}"
            fi
        fi

        return 0
    else
        echo -e "${YELLOW}$(t "delete_canceled")${NC}"
        return 1
    fi
}

# Функция для обновления ноды Aztec до последней версии
update_aztec_node() {
    echo -e "\n${GREEN}=== $(t "update_title") ===${NC}"

    # Переходим в папку с нодой
    cd "$HOME/aztec" || {
        echo -e "${RED}$(t "update_folder_error")${NC}"
        return 1
    }

    # Проверяем текущий тег в docker-compose.yml
    CURRENT_TAG=$(grep -oP 'image: aztecprotocol/aztec:\K[^\s]+' docker-compose.yml || echo "")

    if [[ "$CURRENT_TAG" != "latest" ]]; then
        echo -e "${YELLOW}$(printf "$(t "tag_check")" "$CURRENT_TAG")${NC}"
        sed -i 's|image: aztecprotocol/aztec:.*|image: aztecprotocol/aztec:latest|' docker-compose.yml
    fi

    # Обновляем образ
    echo -e "${YELLOW}$(t "update_pulling")${NC}"
    docker pull aztecprotocol/aztec:latest || {
        echo -e "${RED}$(t "update_pull_error")${NC}"
        return 1
    }

    # Останавливаем контейнеры
    echo -e "${YELLOW}$(t "update_stopping")${NC}"
    docker compose down || {
        echo -e "${RED}$(t "update_stop_error")${NC}"
        return 1
    }

    # Запускаем контейнеры
    echo -e "${YELLOW}$(t "update_starting")${NC}"
    docker compose up -d || {
        echo -e "${RED}$(t "update_start_error")${NC}"
        return 1
    }

    echo -e "${GREEN}$(t "update_success")${NC}"
}

# Функция для даунгрейда ноды Aztec
downgrade_aztec_node() {
    echo -e "\n${GREEN}=== $(t "downgrade_title") ===${NC}"

    # Получаем список доступных тегов с Docker Hub с обработкой пагинации
    echo -e "${YELLOW}$(t "downgrade_fetching")${NC}"

    # Собираем все теги с нескольких страниц
    ALL_TAGS=""
    PAGE=1
    while true; do
        PAGE_TAGS=$(curl -s "https://hub.docker.com/v2/repositories/aztecprotocol/aztec/tags/?page=$PAGE&page_size=100" | jq -r '.results[].name' 2>/dev/null)

        if [ -z "$PAGE_TAGS" ] || [ "$PAGE_TAGS" = "null" ] || [ "$PAGE_TAGS" = "" ]; then
            break
        fi

        ALL_TAGS="$ALL_TAGS"$'\n'"$PAGE_TAGS"
        PAGE=$((PAGE + 1))

        # Ограничим максимальное количество страниц для безопасности
        if [ $PAGE -gt 10 ]; then
            break
        fi
    done

    if [ -z "$ALL_TAGS" ]; then
        echo -e "${RED}$(t "downgrade_fetch_error")${NC}"
        return 1
    fi

    # Фильтруем теги: оставляем только latest и стабильные версии (формат X.Y.Z)
    FILTERED_TAGS=$(echo "$ALL_TAGS" | grep -E '^(latest|[0-9]+\.[0-9]+\.[0-9]+)$' | grep -v -E '.*-(rc|night|alpha|beta|dev|test|unstable|preview).*' | sort -Vr | uniq)

    # Выводим список тегов с нумерацией
    if [ -z "$FILTERED_TAGS" ]; then
        echo -e "${RED}$(t "downgrade_no_stable_versions")${NC}"
        return 1
    fi

    echo -e "\n${CYAN}$(t "downgrade_available")${NC}"
    select TAG in $FILTERED_TAGS; do
        if [ -n "$TAG" ]; then
            break
        else
            echo -e "${RED}$(t "downgrade_invalid_choice")${NC}"
        fi
    done

    echo -e "\n${YELLOW}$(t "downgrade_selected") $TAG${NC}"

    # Переходим в папку с нодой
    cd "$HOME/aztec" || {
        echo -e "${RED}$(t "downgrade_folder_error")${NC}"
        return 1
    }

    # Обновляем образ до выбранной версии
    echo -e "${YELLOW}$(t "downgrade_pulling")$TAG...${NC}"
    docker pull aztecprotocol/aztec:"$TAG" || {
        echo -e "${RED}$(t "downgrade_pull_error")${NC}"
        return 1
    }

    # Останавливаем контейнеры
    echo -e "${YELLOW}$(t "downgrade_stopping")${NC}"
    docker compose down || {
        echo -e "${RED}$(t "downgrade_stop_error")${NC}"
        return 1
    }

    # Изменяем версию в docker-compose.yml
    echo -e "${YELLOW}$(t "downgrade_updating")${NC}"
    sed -i "s|image: aztecprotocol/aztec:.*|image: aztecprotocol/aztec:$TAG|" docker-compose.yml || {
        echo -e "${RED}$(t "downgrade_update_error")${NC}"
        return 1
    }

    # Запускаем контейнеры
    echo -e "${YELLOW}$(t "downgrade_starting") $TAG...${NC}"
    docker compose up -d || {
        echo -e "${RED}$(t "downgrade_start_error")${NC}"
        return 1
    }

    echo -e "${GREEN}$(t "downgrade_success") $TAG!${NC}"
}


# === Адреса контрактов в зависимости от сети ===
# Note: Contract addresses are now defined in the Configuration section above
# ROLLUP_ADDRESS_TESTNET = CONTRACT_ADDRESS
# ROLLUP_ADDRESS_MAINNET = CONTRACT_ADDRESS_MAINNET

# ========= HTTP via curl_cffi =========
# cffi_http_get <url>
cffi_http_get() {
  local url="$1"
  local network="$2"
  python3 - "$url" "$network" <<'PY'
import sys, json
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
  "referer": base_url + "/",
}
try:
    r = requests.get(u, headers=headers, impersonate="chrome131", timeout=30)
    ct = (r.headers.get("content-type") or "").lower()
    txt = r.text
    if "application/json" in ct:
        sys.stdout.write(txt)
    else:
        i, j = txt.find("{"), txt.rfind("}")
        if i != -1 and j != -1 and j > i:
            sys.stdout.write(txt[i:j+1])
        else:
            sys.stdout.write(txt)
except Exception as e:
    sys.stdout.write("")
    sys.stderr.write(f"{e}")
PY
}

# Функция загрузки RPC URL с обработкой ошибок
load_rpc_config() {
    if [ -f "$HOME/.env-aztec-agent" ]; then
        source "$HOME/.env-aztec-agent"
        if [ -z "$RPC_URL" ]; then
            echo -e "${RED}$(t "error_rpc_missing")${NC}"
            return 1
        fi
        if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
            echo -e "${YELLOW}Warning: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not found in $HOME/.env-aztec-agent${NC}"
        fi

        # Если есть резервный RPC, используем его
        if [ -n "$ALT_RPC" ]; then
            echo -e "${YELLOW}Using backup RPC to load the list of validators: $ALT_RPC${NC}"
            USING_BACKUP_RPC=true
        else
            USING_BACKUP_RPC=false
        fi
    else
        echo -e "${RED}$(t "error_file_missing")${NC}"
        return 1
    fi
}

# Функция для получения нового RPC URL
get_new_rpc_url() {
    local network="$1"
    echo -e "${YELLOW}$(t "getting_new_rpc")${NC}"

    # Список возможных RPC провайдеров в зависимости от сети
    local rpc_providers=()

    if [[ "$network" == "mainnet" ]]; then
        rpc_providers=(
            "https://ethereum-rpc.publicnode.com"
            "https://eth.llamarpc.com"
        )
    else
        rpc_providers=(
            "https://ethereum-sepolia-rpc.publicnode.com"
            "https://1rpc.io/sepolia"
            "https://sepolia.drpc.org"
        )
    fi

    # Пробуем каждый RPC пока не найдем рабочий
    for rpc_url in "${rpc_providers[@]}"; do
        echo -e "${YELLOW}Trying RPC: $rpc_url${NC}"

        # Проверяем доступность RPC
        if curl -s --head --connect-timeout 5 "$rpc_url" >/dev/null; then
            echo -e "${GREEN}RPC is available: $rpc_url${NC}"

            # Проверяем, что RPC может отвечать на запросы
            if cast block latest --rpc-url "$rpc_url" >/dev/null 2>&1; then
                echo -e "${GREEN}RPC is working properly: $rpc_url${NC}"

                # Добавляем новый RPC в файл конфигурации
                if grep -q "ALT_RPC=" "$HOME/.env-aztec-agent"; then
                    sed -i "s|ALT_RPC=.*|ALT_RPC=$rpc_url|" "$HOME/.env-aztec-agent"
                else
                    printf 'ALT_RPC=%s\n' "$rpc_url" >> "$HOME/.env-aztec-agent"
                fi

                # Обновляем текущую переменную
                ALT_RPC="$rpc_url"
                USING_BACKUP_RPC=true

                # Перезагружаем конфигурацию, чтобы обновить переменные
                source "$HOME/.env-aztec-agent"

                return 0
            else
                echo -e "${RED}RPC is not responding properly: $rpc_url${NC}"
            fi
        else
            echo -e "${RED}RPC is not available: $rpc_url${NC}"
        fi
    done

    echo -e "${RED}Failed to find a working RPC URL${NC}"
    return 1
}

## Функция для выполнения cast call с обработкой ошибок RPC
cast_call_with_fallback() {
    local contract_address=$1
    local function_signature=$2
    local max_retries=3
    local retry_count=0
    local use_validator_rpc=${3:-false}  # По умолчанию используем основной RPC
    local network="$4"

    while [ $retry_count -lt $max_retries ]; do
        # Определяем какой RPC использовать
        local current_rpc
        if [ "$use_validator_rpc" = true ] && [ -n "$ALT_RPC" ]; then
            current_rpc="$ALT_RPC"
            echo -e "${YELLOW}Using validator RPC: $current_rpc (attempt $((retry_count + 1))/$max_retries)${NC}"
        else
            current_rpc="$RPC_URL"
            echo -e "${YELLOW}Using main RPC: $current_rpc (attempt $((retry_count + 1))/$max_retries)${NC}"
        fi

        local response=$(cast call "$contract_address" "$function_signature" --rpc-url "$current_rpc" 2>&1)

        # Проверяем на ошибки RPC (но игнорируем успешные ответы, которые могут содержать текст)
        if echo "$response" | grep -q -E "^(Error|error|timed out|connection refused|connection reset)"; then
            echo -e "${RED}RPC error: $response${NC}"

            # Если это запрос валидаторов, получаем новый RPC URL
            if [ "$use_validator_rpc" = true ]; then
                if get_new_rpc_url "$network"; then
                    retry_count=$((retry_count + 1))
                    sleep 2
                    continue
                else
                    echo -e "${RED}All RPC attempts failed${NC}"
                    return 1
                fi
            else
                # Для других запросов просто увеличиваем счетчик попыток
                retry_count=$((retry_count + 1))
                sleep 2
                continue
            fi
        fi

        # Если нет ошибки, возвращаем ответ
        echo "$response"
        return 0
    done

    echo -e "${RED}Maximum retries exceeded${NC}"
    return 1
}

hex_to_dec() {
    local hex=${1^^}
    echo "ibase=16; $hex" | bc
}

wei_to_token() {
    local wei_value=$1
    local int_part=$(echo "$wei_value / 1000000000000000000" | bc)
    local frac_part=$(echo "$wei_value % 1000000000000000000" | bc)
    local frac_str=$(printf "%018d" $frac_part)
    frac_str=$(echo "$frac_str" | sed 's/0*$//')
    if [[ -z "$frac_str" ]]; then
        echo "$int_part"
    else
        echo "$int_part.$frac_str"
    fi
}

# Функция для отправки уведомления в Telegram
send_telegram_notification() {
    local message="$1"
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo -e "${YELLOW}Telegram notification not sent: missing TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID${NC}"
        return 1
    fi

    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$message" \
        -d parse_mode="Markdown" > /dev/null
}

# Функция для проверки очереди валидаторов (пакетная обработка)
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

# === Main installation function (merged from install_aztec.sh) ===
install_aztec_node_main() {
    set -e

    # Вызываем проверку портов
    check_and_set_ports || return 2



    echo -e "\n${GREEN}$(t "deps_installed")${NC}"

    echo -e "\n${GREEN}$(t "checking_docker")${NC}"

    if ! command -v docker &>/dev/null; then
        echo -e "\n${RED}$(t "docker_not_found")${NC}"
        echo -e "Please install Docker manually and run the script again."
        return 1
    fi

    if ! docker compose version &>/dev/null; then
        echo -e "\n${RED}$(t "docker_compose_not_found")${NC}"
        echo -e "Please install Docker Compose manually and run the script again."
        return 1
    fi

    echo -e "\n${GREEN}$(t "docker_found")${NC}"

    echo -e "\n${GREEN}$(t "installing_aztec")${NC}"
    echo -e "${YELLOW}$(t "warn_orig_install") ${NC}$(t "warn_orig_install_2")${NC}"
    sleep 5
    curl -L https://install.aztec.network -o install-aztec.sh
    chmod +x install-aztec.sh
    bash install-aztec.sh

    echo 'export PATH="$HOME/.aztec/bin:$PATH"' >> ~/.bash_profile
    source ~/.bash_profile

    if ! command -v aztec &>/dev/null; then
        echo -e "\n${RED}$(t "aztec_not_installed")${NC}"
        return 1
    fi

    echo -e "\n${GREEN}$(t "aztec_installed")${NC}"

    # Обновляем настройки firewall
    # Проверяем, установлен ли ufw
    if ! command -v ufw >/dev/null 2>&1; then
      echo -e "\n${YELLOW}$(t "ufw_not_installed")${NC}"
    else
      # Проверяем, активен ли ufw
      if sudo ufw status | grep -q "inactive"; then
        echo -e "\n${YELLOW}$(t "ufw_not_active")${NC}"
      else
        # Обновляем настройки firewall
        echo -e "\n${GREEN}$(t "opening_ports")${NC}"
        echo -e "${YELLOW}The script needs to use sudo to configure the firewall.${NC}"
        echo -e "The following commands will be executed:"
        echo -e "sudo ufw allow "$p2p_port""
        echo -e "sudo ufw allow "$http_port""
        read -p "Do you want to continue? (Y/n): " confirm
        confirm=${confirm:-Y}
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${RED}Firewall configuration aborted by user.${NC}"
        else
            sudo ufw allow "$p2p_port"
            sudo ufw allow "$http_port"
            echo -e "\n${GREEN}$(t "ports_opened")${NC}"
        fi
      fi
    fi

    # Create Aztec node folder and files
    echo -e "\n${GREEN}$(t "creating_folder")${NC}"
    mkdir -p "$HOME/aztec"
    cd "$HOME/aztec"

    # Ask if user wants to run single or multiple validators
    echo -e "\n${CYAN}$(t "validator_setup_header")${NC}"
    read -p "$(t "multiple_validators_prompt")" -n 1 -r
    echo

    # Store the response for validator mode selection
    VALIDATOR_MODE_REPLY=$REPLY

    # Initialize arrays for keys and addresses
    VALIDATOR_PRIVATE_KEYS_ARRAY=()
    VALIDATOR_ADDRESSES_ARRAY=()
    VALIDATOR_BLS_PRIVATE_KEYS_ARRAY=()
    VALIDATOR_BLS_PUBLIC_KEYS_ARRAY=()
    USE_FIRST_AS_PUBLISHER=false
    HAS_BLS_KEYS=false

    # Ask if user has BLS keys
    read -p "$(t "has_bls_keys") " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        HAS_BLS_KEYS=true
        echo -e "${GREEN}BLS keys will be added to configuration${NC}"
    fi

    # Use the stored response for validator mode selection
    if [[ $VALIDATOR_MODE_REPLY =~ ^[Yy]$ ]]; then
        echo -e "\n${GREEN}$(t "multi_validator_mode")${NC}"

        if [ "$HAS_BLS_KEYS" = true ]; then
            # Get multiple validator key-address-bls data
            echo -e "${YELLOW}$(t "multi_validator_format")${NC}"
            for i in {1..10}; do
                read -p "Validator $i (or press Enter to finish): " KEY_ADDRESS_BLS_PAIR
                if [ -z "$KEY_ADDRESS_BLS_PAIR" ]; then
                    break
                fi

                # Split the input into private key, address, private bls, and public bls
                IFS=',' read -r PRIVATE_KEY ADDRESS PRIVATE_BLS PUBLIC_BLS <<< "$KEY_ADDRESS_BLS_PAIR"

                # Remove any spaces and ensure private key starts with 0x
                PRIVATE_KEY=$(echo "$PRIVATE_KEY" | tr -d ' ')
                if [[ ! "$PRIVATE_KEY" =~ ^0x ]]; then
                    PRIVATE_KEY="0x$PRIVATE_KEY"
                fi

                # Remove any spaces from address
                ADDRESS=$(echo "$ADDRESS" | tr -d ' ')

                # Remove any spaces from BLS keys
                PRIVATE_BLS=$(echo "$PRIVATE_BLS" | tr -d ' ')
                PUBLIC_BLS=$(echo "$PUBLIC_BLS" | tr -d ' ')

                VALIDATOR_PRIVATE_KEYS_ARRAY+=("$PRIVATE_KEY")
                VALIDATOR_ADDRESSES_ARRAY+=("$ADDRESS")
                VALIDATOR_BLS_PRIVATE_KEYS_ARRAY+=("$PRIVATE_BLS")
                VALIDATOR_BLS_PUBLIC_KEYS_ARRAY+=("$PUBLIC_BLS")

                echo -e "${GREEN}Added validator $i with BLS keys${NC}"
            done
        else
            # Get multiple validator key-address pairs (original logic)
            echo -e "${YELLOW}Enter validator private keys and addresses (up to 10, format: private_key,address):${NC}"
            for i in {1..10}; do
                read -p "Validator $i (or press Enter to finish): " KEY_ADDRESS_PAIR
                if [ -z "$KEY_ADDRESS_PAIR" ]; then
                    break
                fi

                # Split the input into private key and address
                IFS=',' read -r PRIVATE_KEY ADDRESS <<< "$KEY_ADDRESS_PAIR"

                # Remove any spaces and ensure private key starts with 0x
                PRIVATE_KEY=$(echo "$PRIVATE_KEY" | tr -d ' ')
                if [[ ! "$PRIVATE_KEY" =~ ^0x ]]; then
                    PRIVATE_KEY="0x$PRIVATE_KEY"
                fi

                # Remove any spaces from address
                ADDRESS=$(echo "$ADDRESS" | tr -d ' ')

                VALIDATOR_PRIVATE_KEYS_ARRAY+=("$PRIVATE_KEY")
                VALIDATOR_ADDRESSES_ARRAY+=("$ADDRESS")
                # Add empty BLS keys for consistency
                VALIDATOR_BLS_PRIVATE_KEYS_ARRAY+=("")
                VALIDATOR_BLS_PUBLIC_KEYS_ARRAY+=("")
            done
        fi

        # Ask if user wants to use first address as publisher for all validators
        echo ""
        read -p "Use first address as publisher for all validators? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            USE_FIRST_AS_PUBLISHER=true
            echo -e "${GREEN}Using first address as publisher for all validators${NC}"
        else
            echo -e "${GREEN}Each validator will use their own address as publisher${NC}"
        fi

    else
        echo -e "\n${GREEN}$(t "single_validator_mode")${NC}"

        # Get single validator key-address pair
        read -p "$(t "enter_validator_key") " PRIVATE_KEY
        read -p "Enter validator address: " ADDRESS

        # Remove any spaces and ensure private key starts with 0x
        PRIVATE_KEY=$(echo "$PRIVATE_KEY" | tr -d ' ')
        if [[ ! "$PRIVATE_KEY" =~ ^0x ]]; then
            PRIVATE_KEY="0x$PRIVATE_KEY"
        fi

        # Remove any spaces from address
        ADDRESS=$(echo "$ADDRESS" | tr -d ' ')

        VALIDATOR_PRIVATE_KEYS_ARRAY+=("$PRIVATE_KEY")
        VALIDATOR_ADDRESSES_ARRAY+=("$ADDRESS")

        if [ "$HAS_BLS_KEYS" = true ]; then
            # Get BLS keys for single validator
            read -p "$(t "single_validator_bls_private") " PRIVATE_BLS
            read -p "$(t "single_validator_bls_public") " PUBLIC_BLS

            # Remove any spaces from BLS keys
            PRIVATE_BLS=$(echo "$PRIVATE_BLS" | tr -d ' ')
            PUBLIC_BLS=$(echo "$PUBLIC_BLS" | tr -d ' ')

            VALIDATOR_BLS_PRIVATE_KEYS_ARRAY+=("$PRIVATE_BLS")
            VALIDATOR_BLS_PUBLIC_KEYS_ARRAY+=("$PUBLIC_BLS")
            echo -e "${GREEN}$(t "bls_keys_added")${NC}"
        else
            # Add empty BLS keys for consistency
            VALIDATOR_BLS_PRIVATE_KEYS_ARRAY+=("")
            VALIDATOR_BLS_PUBLIC_KEYS_ARRAY+=("")
        fi

        USE_FIRST_AS_PUBLISHER=true  # For single validator, always use own address
    fi

    # Ask for Aztec L2 Address for feeRecipient и COINBASE
    echo -e "\n${YELLOW}Enter Aztec L2 Address to use as feeRecipient for all validators:${NC}"
    read -p "Aztec L2 Address: " FEE_RECIPIENT_ADDRESS
    FEE_RECIPIENT_ADDRESS=$(echo "$FEE_RECIPIENT_ADDRESS" | tr -d ' ')

    # Добавляем запрос COINBASE сразу после Aztec L2 Address
    echo -e "\n${YELLOW}Enter COINBASE eth address:${NC}"
    read -p "COINBASE: " COINBASE
    COINBASE=$(echo "$COINBASE" | tr -d ' ')

    # Create keys directory and separate YML files
    echo -e "\n${GREEN}Creating key files...${NC}"
    mkdir -p "$HOME/aztec/keys"

    for i in "${!VALIDATOR_PRIVATE_KEYS_ARRAY[@]}"; do
        # Create SECP256K1 YML file for validator
        KEY_FILE="$HOME/aztec/keys/validator_$((i+1)).yml"
        cat > "$KEY_FILE" <<EOF
type: "file-raw"
keyType: "SECP256K1"
privateKey: "${VALIDATOR_PRIVATE_KEYS_ARRAY[$i]}"
EOF
        echo -e "${GREEN}Created SECP256K1 key file: $KEY_FILE${NC}"

        if [ "$HAS_BLS_KEYS" = true ] && [ -n "${VALIDATOR_BLS_PRIVATE_KEYS_ARRAY[$i]}" ]; then
            # Create separate BLS YML file
            BLS_KEY_FILE="$HOME/aztec/keys/bls_validator_$((i+1)).yml"
            cat > "$BLS_KEY_FILE" <<EOF
type: "file-raw"
keyType: "BLS"
privateKey: "${VALIDATOR_BLS_PRIVATE_KEYS_ARRAY[$i]}"
EOF
            echo -e "${GREEN}Created BLS key file: $BLS_KEY_FILE${NC}"
        fi
    done

    # Create config directory and keystore.json
    echo -e "\n${GREEN}Creating keystore configuration...${NC}"
    mkdir -p "$HOME/aztec/config"

    # Prepare validators array for keystore.json
    VALIDATORS_JSON_ARRAY=()
    for i in "${!VALIDATOR_ADDRESSES_ARRAY[@]}"; do
        address="${VALIDATOR_ADDRESSES_ARRAY[$i]}"

        if [ "$USE_FIRST_AS_PUBLISHER" = true ] && [ $i -gt 0 ]; then
            # Use first address as publisher for all other validators
            publisher="${VALIDATOR_ADDRESSES_ARRAY[0]}"
        else
            # Use own address as publisher
            publisher="${VALIDATOR_ADDRESSES_ARRAY[$i]}"
        fi

        if [ "$HAS_BLS_KEYS" = true ] && [ -n "${VALIDATOR_BLS_PUBLIC_KEYS_ARRAY[$i]}" ]; then
            # Create validator JSON with BLS key
            VALIDATOR_JSON=$(cat <<EOF
{
      "attester": {
        "eth": "$address",
        "bls": "${VALIDATOR_BLS_PUBLIC_KEYS_ARRAY[$i]}"
      },
      "publisher": ["$publisher"],
      "coinbase": "$COINBASE",
      "feeRecipient": "$FEE_RECIPIENT_ADDRESS"
    }
EOF
            )
        else
            # Create validator JSON without BLS key (original format)
            VALIDATOR_JSON=$(cat <<EOF
{
      "attester": {
        "eth": "$address"
      },
      "publisher": ["$publisher"],
      "coinbase": "$COINBASE",
      "feeRecipient": "$FEE_RECIPIENT_ADDRESS"
    }
EOF
            )
        fi
        VALIDATORS_JSON_ARRAY+=("$VALIDATOR_JSON")
    done

    # Join validators array with commas
    VALIDATORS_JSON_STRING=$(IFS=,; echo "${VALIDATORS_JSON_ARRAY[*]}")

    # Create keystore.json with updated schema
    cat > "$HOME/aztec/config/keystore.json" <<EOF
{
  "schemaVersion": 1,
  "remoteSigner": "http://web3signer:10500",
  "validators": [
    $VALIDATORS_JSON_STRING
  ]
}
EOF

    echo -e "${GREEN}Created keystore.json configuration${NC}"

    DEFAULT_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)

    echo -e "\n${GREEN}$(t "creating_env")${NC}"
    ETHEREUM_RPC_URL=$(read_and_validate_url "ETHEREUM_RPC_URL: ")
    CONSENSUS_BEACON_URL=$(read_and_validate_url "CONSENSUS_BEACON_URL: ")

    # Create .env file без COINBASE
    cat > .env <<EOF
ETHEREUM_RPC_URL=${ETHEREUM_RPC_URL}
CONSENSUS_BEACON_URL=${CONSENSUS_BEACON_URL}
P2P_IP=${DEFAULT_IP}
EOF

    # Запрашиваем выбор сети
    echo -e "\n${GREEN}$(t "select_network")${NC}"
    echo "1) $(t "mainnet")"
    echo "2) $(t "testnet")"
    read -p "$(t "enter_choice") " network_choice

    case $network_choice in
        1)
            NETWORK="mainnet"
            DATA_DIR="$HOME/.aztec/mainnet/data/"
            ;;
        2)
            NETWORK="testnet"
            DATA_DIR="$HOME/.aztec/testnet/data/"
            ;;
        *)
            echo -e "\n${RED}$(t "invalid_choice")${NC}"
            return 1
            ;;
    esac

    echo -e "\n${GREEN}$(t "selected_network")${NC}: ${YELLOW}$NETWORK${NC}"

    # Сохраняем/обновляем NETWORK в файле .env-aztec-agent
    ENV_FILE="$HOME/.env-aztec-agent"

    # Если файл существует, обновляем переменную NETWORK
    if [ -f "$ENV_FILE" ]; then
        # Если NETWORK уже существует в файле, заменяем её значение
        if grep -q "^NETWORK=" "$ENV_FILE"; then
            sed -i "s/^NETWORK=.*/NETWORK=$NETWORK/" "$ENV_FILE"
        else
            # Если NETWORK нет, добавляем в конец файла
            printf 'NETWORK=%s\n' "$NETWORK" >> "$ENV_FILE"
        fi
    else
        # Если файла нет, создаем его с переменной NETWORK
        printf 'NETWORK=%s\n' "$NETWORK" > "$ENV_FILE"
    fi

    echo -e "${GREEN}Network saved to $ENV_FILE${NC}"

    # Создаем docker-compose.yml
    echo -e "\n${GREEN}$(t "creating_compose")${NC}"

    cat > docker-compose.yml <<EOF
services:
  aztec-node:
    container_name: aztec-sequencer
    networks:
      - aztec
    image: aztecprotocol/aztec:latest
    restart: unless-stopped
    environment:
      ETHEREUM_HOSTS: \${ETHEREUM_RPC_URL}
      L1_CONSENSUS_HOST_URLS: \${CONSENSUS_BEACON_URL}
      DATA_DIRECTORY: /data
      KEY_STORE_DIRECTORY: /config
      P2P_IP: \${P2P_IP}
      LOG_LEVEL: info;debug:node:sentinel
      AZTEC_PORT: ${http_port}
      AZTEC_ADMIN_PORT: 8880
    entrypoint: >
      sh -c 'node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js start --node --archiver --sequencer --network $NETWORK'
    ports:
      - ${p2p_port}:${p2p_port}/tcp
      - ${p2p_port}:${p2p_port}/udp
      - ${http_port}:${http_port}
    volumes:
      - $DATA_DIR:/data
      - $HOME/aztec/config:/config
    labels:
      - com.centurylinklabs.watchtower.enable=true
networks:
  aztec:
    name: aztec
    external: true
EOF

    echo -e "\n${GREEN}$(t "compose_created")${NC}"

    # Check if Watchtower is already installed
    if [ -d "$HOME/watchtower" ]; then
        echo -e "\n${GREEN}$(t "watchtower_exists")${NC}"
    else
        # Create Watchtower folder and files
        echo -e "\n${GREEN}$(t "installing_watchtower")${NC}"
        mkdir -p "$HOME/watchtower"
        cd "$HOME/watchtower"

        # Ask for Telegram notification settings
        echo -e "\n${YELLOW}Telegram notification settings for Watchtower:${NC}"
        read -p "$(t "enter_tg_token") " TG_TOKEN
        read -p "$(t "enter_tg_chat_id") " TG_CHAT_ID

        # Create .env file for Watchtower
        cat > .env <<EOF
TG_TOKEN=${TG_TOKEN}
TG_CHAT_ID=${TG_CHAT_ID}
WATCHTOWER_NOTIFICATION_URL=telegram://${TG_TOKEN}@telegram?channels=${TG_CHAT_ID}&parseMode=html
EOF

        echo -e "\n${GREEN}$(t "env_created")${NC}"

        echo -e "\n${GREEN}$(t "creating_watchtower_compose")${NC}"
        cat > docker-compose.yml <<EOF
services:
  watchtower:
    image: nickfedor/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    env_file:
      - .env
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_POLL_INTERVAL=3600
      - WATCHTOWER_NOTIFICATIONS=shoutrrr
      - WATCHTOWER_NOTIFICATION_URL
      - WATCHTOWER_INCLUDE_RESTARTING=true
      - WATCHTOWER_LABEL_ENABLE=true
EOF

        echo -e "\n${GREEN}$(t "compose_created")${NC}"
    fi

    # Create aztec network before starting web3signer (needed for web3signer to connect)
    echo -e "\n${GREEN}Creating aztec network...${NC}"
    docker network create aztec 2>/dev/null || echo -e "${YELLOW}Network aztec already exists${NC}"

    # Download and run web3signer before starting the node
    echo -e "\n${GREEN}Downloading and starting web3signer...${NC}"
    docker pull consensys/web3signer:latest

    # Stop and remove existing web3signer container if it exists
    docker stop web3signer 2>/dev/null || true
    docker rm web3signer 2>/dev/null || true

    # Run web3signer container
    docker run -d \
      --name web3signer \
      --restart unless-stopped \
      --network aztec \
      -p 10500:10500 \
      -v $HOME/aztec/keys:/keys \
      consensys/web3signer:latest \
      --http-listen-host=0.0.0.0 \
      --http-listen-port=10500 \
      --http-host-allowlist="*" \
      --key-store-path=/keys \
      eth1 --chain-id=11155111

    echo -e "${GREEN}web3signer started successfully${NC}"

    # Wait a moment for web3signer to initialize
    echo -e "${YELLOW}Waiting for web3signer to initialize...${NC}"
    sleep 5

    echo -e "\n${GREEN}$(t "starting_node")${NC}"
    cd "$HOME/aztec"
    docker compose up -d

    # Start Watchtower if it exists
    if [ -d "$HOME/watchtower" ]; then
        cd "$HOME/watchtower"
        docker compose up -d
    fi

    echo -e "\n${YELLOW}$(t "showing_logs")${NC}"
    echo -e "${YELLOW}$(t "logs_starting")${NC}"
    sleep 5
    echo -e ""
    cd "$HOME/aztec"
    docker compose logs -fn 200

    set +e
}

# === Install Aztec node ===
function install_aztec {
  echo -e ""
  echo -e "${CYAN}$(t "running_install_node")${NC}"
  echo -e ""

  # Запускаем с обработкой Ctrl+C и других кодов возврата
  install_aztec_node_main
  EXIT_CODE=$?

  case $EXIT_CODE in
    0)
      # Успешное выполнение
      echo -e "${GREEN}$(t "install_completed_successfully")${NC}"
      ;;
    1)
      # Ошибка установки
      echo -e "${RED}$(t "failed_running_install_node")${NC}"
      ;;
    130)
      # Ctrl+C - не считаем ошибкой
      echo -e "${YELLOW}$(t "logs_stopped_by_user")${NC}"
      ;;
    2)
      # Пользователь отменил установку из-за занятых портов
      echo -e "${YELLOW}$(t "installation_cancelled_by_user")${NC}"
      ;;
    *)
      # Неизвестная ошибка
      echo -e "${RED}$(t "unknown_error_occurred")${NC}"
      ;;
  esac

  return $EXIT_CODE
}





# === Common helper functions ===
function _ensure_env_file() {
  local env_file="$HOME/.env-aztec-agent"
  [[ ! -f "$env_file" ]] && touch "$env_file"
  echo "$env_file"
}

function _update_env_var() {
  local env_file="$1" key="$2" value="$3"
  if grep -q "^$key=" "$env_file"; then
    sed -i "s|^$key=.*|$key=$value|" "$env_file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$env_file"
  fi
}

function _read_env_var() {
  local env_file="$1" key="$2"
  grep "^$key=" "$env_file" | cut -d '=' -f2-
}

function _validate_compose_path() {
  local path="$1"
  [[ -d "$path" && -f "$path/docker-compose.yml" ]]
}





# === Add BLS private keys to keystore.json ===
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


# === Main menu ===
main_menu() {
  show_logo
  while true; do
    echo -e "\n${BLUE}$(t "title")${NC}"
    echo -e "${CYAN}$(t "option1")${NC}"
    echo -e "${GREEN}$(t "option2")${NC}"
    echo -e "${RED}$(t "option3")${NC}"
    echo -e "${CYAN}$(t "option4")${NC}"
    echo -e "${CYAN}$(t "option5")${NC}"
    echo -e "${CYAN}$(t "option6")${NC}"
    echo -e "${CYAN}$(t "option7")${NC}"
    echo -e "${CYAN}$(t "option8")${NC}"
    echo -e "${CYAN}$(t "option9")${NC}"
    echo -e "${CYAN}$(t "option10")${NC}"
    echo -e "${GREEN}$(t "option11")${NC}"
    echo -e "${RED}$(t "option12")${NC}"
    echo -e "${CYAN}$(t "option13")${NC}"
    echo -e "${CYAN}$(t "option14")${NC}"
    echo -e "${CYAN}$(t "option15")${NC}"
    echo -e "${YELLOW}$(t "option16")${NC}"
    echo -e "${CYAN}$(t "option17")${NC}"
    echo -e "${NC}$(t "option18")${NC}"
    echo -e "${NC}$(t "option19")${NC}"
    echo -e "${NC}$(t "option20")${NC}"
    echo -e "${NC}$(t "option21")${NC}"
    echo -e "${CYAN}$(t "option22")${NC}"
    echo -e "${CYAN}$(t "option23")${NC}"
    echo -e "${CYAN}$(t "option24")${NC}"
    echo -e "${RED}$(t "option0")${NC}"
    echo -e "${BLUE}================================${NC}"

    read -p "$(t "choose_option") " choice

    # Flag to track if a valid command was executed
    command_executed=false

    case "$choice" in
      1) check_aztec_container_logs; command_executed=true ;;
      2) create_systemd_agent; command_executed=true ;;
      3) remove_systemd_agent; command_executed=true ;;
      4) view_container_logs; command_executed=true ;;
      5) find_rollup_address; command_executed=true ;;
      6) find_peer_id; command_executed=true ;;
      7) find_governance_proposer_payload; command_executed=true ;;
      8) check_proven_block; command_executed=true ;;
      9) check_validator; command_executed=true ;;
      10) manage_publisher_balance_monitoring; command_executed=true ;;
      11) install_aztec; command_executed=true ;;
      12) delete_aztec; command_executed=true ;;
      13) start_aztec_containers; command_executed=true ;;
      14) stop_aztec_containers; command_executed=true ;;
      15) update_aztec; command_executed=true ;;
      16) downgrade_aztec; command_executed=true ;;
      17) check_aztec_version; command_executed=true ;;
      18) generate_bls_keys; command_executed=true ;;
      19) approve_with_all_keys; command_executed=true ;;
      20) stake_validators; command_executed=true ;;
      21) claim_rewards; command_executed=true ;;
      22) change_rpc_url; command_executed=true ;;
      23) check_updates_safely; command_executed=true ;;
      24) check_error_definitions_updates_safely; command_executed=true ;;
      0) echo -e "\n${GREEN}$(t "goodbye")${NC}"; exit 0 ;;
      *) echo -e "\n${RED}$(t "invalid_choice")${NC}" ;;
    esac

    # Wait for Enter before showing menu again (only for valid commands)
    if [ "$command_executed" = true ]; then
      echo ""
      echo -e "${YELLOW}Press Enter to continue...${NC}"
      read -r
      clear
      show_logo
    fi
  done
}

# === Script launch ===
init_languages
check_dependencies
main_menu
