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
