# === Install Aztec node module ===
# === Functions from install_aztec.sh (merged) ===
# Инициализация портов по умолчанию
http_port=8080
p2p_port=40400

check_and_set_ports() {
    local new_http_port
    local new_p2p_port

    echo -e "\n${CYAN}=== $(t "checking_ports") ===${NC}"
    echo -e "${GRAY}$(t "checking_ports_desc")${NC}\n"

    # Установка iproute2 (если не установлен) - содержит утилиту ss
    if ! command -v ss &> /dev/null; then
        echo -e "${YELLOW}$(t "installing_ss")...${NC}"
        sudo apt update -q > /dev/null 2>&1
        sudo apt install -y iproute2 > /dev/null 2>&1
        echo -e "${GREEN}$(t "ss_installed") ✔${NC}\n"
    fi

    while true; do
        ports=("$http_port" "$p2p_port")
        ports_busy=()

        echo -e "${CYAN}$(t "scanning_ports")...${NC}"

        # Проверка каждого порта с визуализацией (используем ss вместо lsof)
        for port in "${ports[@]}"; do
            echo -n -e "  ${YELLOW}Port $port:${NC} "
            if sudo ss -tuln | grep -q ":${port}\b"; then
                echo -e "${RED}$(t "busy") ✖${NC}"
                ports_busy+=("$port")
            else
                echo -e "${GREEN}$(t "free") ✔${NC}"
            fi
            sleep 0.1  # Уменьшенная задержка, так как ss работает быстрее
        done

        # Все порты свободны → выход из цикла
        if [ ${#ports_busy[@]} -eq 0 ]; then
            echo -e "\n${GREEN}✓ $(t "ports_free_success")${NC}"
            echo -e "  HTTP: ${GREEN}$http_port${NC}, P2P: ${GREEN}$p2p_port${NC}\n"
            break
        else
            # Показать занятые порты
            echo -e "\n${RED}⚠ $(t "ports_busy_error")${NC}"
            echo -e "  ${RED}${ports_busy[*]}${NC}\n"

            # Предложить изменить порты
            read -p "$(t "change_ports_prompt") " -n 1 -r
            echo

            if [[ $REPLY =~ ^[Yy]$ || -z "$REPLY" ]]; then
                echo -e "\n${YELLOW}$(t "enter_new_ports_prompt")${NC}"

                # Запрос нового HTTP-порта
                read -p "  $(t "enter_http_port") [${GRAY}by default: $http_port${NC}]: " new_http_port
                http_port=${new_http_port:-$http_port}

                # Запрос нового P2P-порта
                read -p "  $(t "enter_p2p_port") [${GRAY}by default: $p2p_port${NC}]: " new_p2p_port
                p2p_port=${new_p2p_port:-$p2p_port}

                echo -e "\n${CYAN}$(t "ports_updated")${NC}"
                echo -e "  HTTP: ${YELLOW}$http_port${NC}, P2P: ${YELLOW}$p2p_port${NC}\n"
            else
                # Отмена установки
                return 2
            fi
        fi
    done
}

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
