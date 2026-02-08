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
            echo -e "\n${CYAN}Foundry is not installed. Please install it manually.${NC}"
            echo -e "For more information, visit https://book.getfoundry.sh/getting-started/installation"
            exit 1
            ;;

          curl)
            echo -e "\n${CYAN}curl is not installed. Please install it manually.${NC}"
            exit 1
            ;;

          grep|sed)
            echo -e "\n${CYAN}grep or sed is not installed. Please install it manually.${NC}"
            exit 1
            ;;

          jq)
            echo -e "\n${CYAN}jq is not installed. Please install it manually.${NC}"
            exit 1
            ;;

          bc)
            echo -e "\n${CYAN}bc is not installed. Please install it manually.${NC}"
            exit 1
            ;;

          python3)
            echo -e "\n${CYAN}python3 is not installed. Please install it manually.${NC}"
            exit 1
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
  if [ ! -f .env-aztec-agent ]; then
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
      } > .env-aztec-agent
      chmod 600 .env-aztec-agent 2>/dev/null || true
