# Color codes
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
