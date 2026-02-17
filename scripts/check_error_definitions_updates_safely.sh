# === Safe error definitions update check ===
# Security: Optional update check with hash verification to prevent supply chain attacks
check_error_definitions_updates_safely() {
  echo -e "\n${BLUE}=== $(t "safe_error_def_update_check") ===${NC}"
  echo -e "\n${YELLOW}$(t "error_def_update_warning")${NC}"
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

  REMOTE_ERROR_DEF_URL="https://raw.githubusercontent.com/pittpv/aztec-monitoring-script/main/other/error_definitions.json"
  TEMP_ERROR_FILE=$(mktemp)

  echo -e "\n${CYAN}$(t "downloading_error_definitions")${NC}"
  if ! curl -fsSL "$REMOTE_ERROR_DEF_URL" -o "$TEMP_ERROR_FILE"; then
    echo -e "${RED}$(t "failed_download_error_definitions")${NC}"
    rm -f "$TEMP_ERROR_FILE"
    return 1
  fi

  # Вычисляем SHA256 хеш загруженного файла
  if command -v sha256sum >/dev/null 2>&1; then
    DOWNLOADED_HASH=$(sha256sum "$TEMP_ERROR_FILE" | cut -d' ' -f1)
    echo -e "${GREEN}$(t "downloaded_file_sha256") ${DOWNLOADED_HASH}${NC}"
    echo -e "${YELLOW}$(t "verify_hash_match")${NC}"
  elif command -v shasum >/dev/null 2>&1; then
    DOWNLOADED_HASH=$(shasum -a 256 "$TEMP_ERROR_FILE" | cut -d' ' -f1)
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
    rm -f "$TEMP_ERROR_FILE"
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
