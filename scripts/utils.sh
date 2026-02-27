# Color codes
# === hex_to_dec: convert a hex string (with or without 0x prefix) to decimal ===
hex_to_dec() {
  local hex=$1
  hex=${hex#0x}
  hex=$(echo "$hex" | sed 's/^0*//')
  [ -z "$hex" ] && echo 0 && return
  echo $((16#$hex))
}

# === Spinner function ===
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'

  while kill -0 "$pid" 2>/dev/null; do
    for i in $(seq 0 3); do
      printf "\r${CYAN}$(t "searching") %c${NC}" "${spinstr:i:1}"
      sleep $delay
    done
  done

  printf "\r                 \r"
}
# Function to get a yes/no answer
# Usage: get_yes_no "Prompt message"
# Returns 0 for yes, 1 for no
get_yes_no() {
    local prompt="$1"
    local answer
    while true; do
        read -p "$prompt" answer
        case "$answer" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}
# Function to read and validate a URL
read_and_validate_url() {
  local prompt="$1"
  local url
  while true; do
    read -p "$prompt" url
    if [[ $url =~ ^(https?|ftp)://[^\s/$.?#].[^\s]*$ ]]; then
      echo "$url"
      break
    else
      echo -e "${RED}Invalid URL format. Please enter a valid URL.${NC}"
    fi
  done
}
# Function to read and validate a number
read_and_validate_number() {
  local prompt="$1"
  local num
  while true; do
    read -p "$prompt" num
    if [[ $num =~ ^[0-9]+$ ]]; then
      echo "$num"
      break
    else
      echo -e "${RED}Invalid input. Please enter a positive number.${NC}"
    fi
  done
}
# === Helper function to get network and RPC settings ===
get_network_settings() {
    local env_file="$HOME/.env-aztec-agent"
    local network="testnet"
    local rpc_url="$RPC_URL"

    if [[ -f "$env_file" ]]; then
        source "$env_file"
        [[ -n "$NETWORK" ]] && network="$NETWORK"
        [[ -n "$ALT_RPC" ]] && rpc_url="$ALT_RPC"
    fi

    # Determine contract address based on network
    local contract_address="$CONTRACT_ADDRESS"
    if [[ "$network" == "mainnet" ]]; then
        contract_address="$CONTRACT_ADDRESS_MAINNET"
    fi

    echo "$network|$rpc_url|$contract_address"
}

# === Get network for validator ===
get_network_for_validator() {
    local network="testnet"
    if [[ -f "$HOME/.env-aztec-agent" ]]; then
        source "$HOME/.env-aztec-agent"
        [[ -n "$NETWORK" ]] && network="$NETWORK"
    fi
    echo "$network"
}

# ========= HTTP via curl_cffi =========
# cffi_http_get <url> <network>
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
