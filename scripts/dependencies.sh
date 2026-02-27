# === Dependency check ===
check_dependencies() {
  missing=()
  echo -e "\n${BLUE}$(t "checking_deps")${NC}\n"

  # Создаем ассоциативный массив для отображения имен
  declare -A tool_names=(
    ["cast"]="foundry"
    ["curl"]="curl"
    ["grep"]="grep"
    ["sed"]="sed"
    ["jq"]="jq"
    ["bc"]="bc"
    ["python3"]="python3"
  )

  # Проверяем основные утилиты
  for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
      display_name=${tool_names[$tool]:-$tool}
      echo -e "${RED}❌ $display_name $(t "not_installed")${NC}"
      missing+=("$tool")
    else
      display_name=${tool_names[$tool]:-$tool}
      echo -e "${GREEN}✅ $display_name $(t "installed")${NC}"
    fi
  done

  # Отдельная проверка для curl_cffi
  if command -v python3 &>/dev/null; then
    if python3 -c "import curl_cffi" 2>/dev/null; then
      echo -e "${GREEN}✅ curl_cffi $(t "installed")${NC}"
    else
      echo -e "${YELLOW}⚠️  curl_cffi $(t "not_installed")${NC}"
      # Добавляем python3 в missing только если нужно установить curl_cffi
      if [[ ! " ${missing[@]} " =~ " python3 " ]]; then
        missing+=("python3_curl_cffi")
      fi
    fi
  else
    # python3 не установлен, это уже обрабатывается выше
    echo -e "${YELLOW}⚠️  curl_cffi $(t "not_installed") (requires python3)${NC}"
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    # Преобразуем имена для отображения в списке отсутствующих инструментов
    missing_display=()
    for tool in "${missing[@]}"; do
      if [ "$tool" == "python3_curl_cffi" ]; then
        missing_display+=("curl_cffi")
      else
        missing_display+=("${tool_names[$tool]:-$tool}")
      fi
    done

    echo -e "\n${YELLOW}$(t "missing_tools") ${missing_display[*]}${NC}"
    echo -e "${YELLOW}The script needs to use sudo to install the missing dependencies.${NC}"
    while true; do
      read -p "$(t "install_prompt") " confirm
      confirm=${confirm:-Y}
      if [[ "$confirm" =~ ^[YyNn]$ ]]; then
        break
      else
        echo -e "${RED}Invalid choice. Please enter Y or n.${NC}"
      fi
    done

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      for tool in "${missing[@]}"; do
        case "$tool" in
          cast)
            echo -e "\n${CYAN}$(t "installing_foundry")${NC}"
            # Security warning: This is a third-party script execution. Consider pinning to a specific version
            # or verifying checksums in production environments to prevent supply chain attacks.
            curl -L https://foundry.paradigm.xyz | bash

            if ! grep -q 'foundry/bin'  ~/.bash_profile; then
              echo 'export PATH="$PATH:$HOME/.foundry/bin"' >> ~/.bash_profile
            fi

            export PATH="$PATH:$HOME/.foundry/bin"
            foundryup
            ;;

          curl)
            echo -e "\n${CYAN}$(t "installing_curl")${NC}"
            sudo apt-get install -y curl || brew install curl
            ;;

          grep|sed)
            echo -e "\n${CYAN}$(t "installing_utils")${NC}"
            sudo apt-get install -y grep sed || brew install grep gnu-sed
            ;;

          jq)
            echo -e "\n${CYAN}$(t "installing_jq")${NC}"
            sudo apt-get install -y jq || brew install jq
            ;;

          bc)
            echo -e "\n${CYAN}$(t "installing_bc")${NC}"
            sudo apt-get install -y bc || brew install bc
            ;;

          python3)
            echo -e "\n${CYAN}$(t "installing_python3")${NC}"
            # Устанавливаем python3 и pip отдельно
            if command -v apt-get &>/dev/null; then
              sudo apt-get install -y python3 python3-pip
            elif command -v brew &>/dev/null; then
              brew install python3
            fi

            # Устанавливаем curl_cffi с обходом externally-managed-environment
            echo -e "\n${CYAN}$(t "installing_curl_cffi")${NC}"
            # Сначала проверяем доступность pip
            if python3 -m pip --version &>/dev/null; then
              python3 -m pip install --break-system-packages --quiet curl_cffi 2>/dev/null || \
              python3 -m pip install --quiet curl_cffi
            else
              # Если pip недоступен, устанавливаем через ensurepip
              python3 -m ensurepip --user 2>/dev/null || true
              python3 -m pip install --user --quiet curl_cffi 2>/dev/null || \
              curl -sSL https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
              python3 get-pip.py --user && \
              python3 -m pip install --user --quiet curl_cffi
              rm -f get-pip.py
            fi
            ;;

          python3_curl_cffi)
            # Устанавливаем только curl_cffi с обходом externally-managed-environment
            echo -e "\n${CYAN}$(t "installing_curl_cffi")${NC}"
            # Сначала проверяем доступность pip
            if python3 -m pip --version &>/dev/null; then
              python3 -m pip install --break-system-packages --quiet curl_cffi 2>/dev/null || \
              python3 -m pip install --quiet curl_cffi
            else
              # Если pip недоступен, устанавливаем через ensurepip
              python3 -m ensurepip --user 2>/dev/null || true
              python3 -m pip install --user --quiet curl_cffi 2>/dev/null || \
              curl -sSL https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
              python3 get-pip.py --user && \
              python3 -m pip install --user --quiet curl_cffi
              rm -f get-pip.py
            fi
            ;;
        esac
      done
    else
      echo -e "\n${RED}$(t "missing_required")${NC}"
      exit 1
    fi
  fi

  # Дополнительная проверка curl_cffi на случай, если пользователь пропустил установку
  if command -v python3 &>/dev/null; then
    if ! python3 -c "import curl_cffi" 2>/dev/null; then
      echo -e "\n${YELLOW}$(t "curl_cffi_not_installed")${NC}"
      read -p "$(t "install_curl_cffi_prompt") " confirm
      confirm=${confirm:-Y}

      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "\n${CYAN}$(t "installing_curl_cffi")${NC}"
        # Сначала проверяем доступность pip
        if python3 -m pip --version &>/dev/null; then
          python3 -m pip install --break-system-packages --quiet curl_cffi 2>/dev/null || \
          python3 -m pip install --quiet curl_cffi
        else
          # Если pip недоступен, устанавливаем через ensurepip
          python3 -m ensurepip --user 2>/dev/null || true
          python3 -m pip install --user --quiet curl_cffi 2>/dev/null || \
          curl -sSL https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
          python3 get-pip.py --user && \
          python3 -m pip install --user --quiet curl_cffi
          rm -f get-pip.py
        fi
      else
        echo -e "\n${YELLOW}$(t "curl_cffi_optional")${NC}"
      fi
    fi
  fi

  # Request RPC URL from user and create .env file
  if [ ! -f "$HOME/.env-aztec-agent" ]; then
      echo -e "\n${BLUE}$(t "rpc_prompt")${NC}"

      # Запрос RPC URL с проверкой
      while true; do
          RPC_URL=$(read_and_validate_url "> ")
          if [ -n "$RPC_URL" ]; then
              break
          else
              echo -e "${RED}$(t "rpc_empty_error")${NC}"
          fi
      done

      echo -e "\n${BLUE}$(t "network_prompt")${NC}"

      # Запрос сети с проверкой
      while true; do
          read -p "> " NETWORK
          if [ -n "$NETWORK" ]; then
              break
          else
              echo -e "${RED}$(t "network_empty_error")${NC}"
          fi
      done

      # Создание файла с обеими переменными
      {
          printf 'RPC_URL=%s\n' "$RPC_URL"
          printf 'NETWORK=%s\n' "$NETWORK"
      } > "$HOME/.env-aztec-agent"
      chmod 600 "$HOME/.env-aztec-agent" 2>/dev/null || true

      echo -e "\n${GREEN}$(t "env_created")${NC}"
  else
      source "$HOME/.env-aztec-agent"
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
