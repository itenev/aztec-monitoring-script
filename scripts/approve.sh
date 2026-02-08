# === Approve ===
approve_with_all_keys() {
    # Get network settings
    local settings
    settings=$(get_network_settings)
    local network=$(echo "$settings" | cut -d'|' -f1)
    local rpc_url=$(echo "$settings" | cut -d'|' -f2)
    local contract_address=$(echo "$settings" | cut -d'|' -f3)

    local rpc_providers=(
        "$rpc_url"
        "https://ethereum-sepolia-rpc.publicnode.com"
        "https://sepolia.drpc.org"
        "https://rpc.sepolia.org"
        "https://1rpc.io/sepolia"
    )
    local key_files
    local private_key
    local current_rpc_url
    local key_index=0
    local rpc_count=${#rpc_providers[@]}

    # Find all YML key files and sort so order is fixed (e.g. validator_1 then validator_2)
    key_files=$(find $HOME/aztec/keys/ -name "*.yml" -type f | sort)
    if [ -z "$key_files" ]; then
        echo "Error: No YML key files found in $HOME/aztec/keys/"
        return 1
    fi

    # Execute command for each private key sequentially
    for key_file in $key_files; do
        # Skip files with 'bls' in the name
        if [[ "$key_file" == *"bls"* ]]; then
            continue
        fi

        echo ""
        echo "Processing key file: $key_file"

        # Extract private key from YML file
        private_key=$(grep "privateKey:" "$key_file" | awk -F'"' '{print $2}')

        if [ -n "$private_key" ]; then
            echo "Executing with private key from $key_file"

            # Use different RPC for each validator to avoid "replacement transaction underpriced"
            # on the same node when sending several txs in a row
            current_rpc_url="${rpc_providers[$((key_index % rpc_count))]}"
            echo "Using RPC URL: $current_rpc_url"

            # Get address and current nonce for this key so each tx uses correct nonce (no duplicate nonce)
            local eth_address
            eth_address=$(cast wallet address --private-key "$private_key" 2>/dev/null | tr '[:upper:]' '[:lower:]')
            local nonce
            # Use pending block to include already pending txs, so we always get the next free nonce
            nonce=$(cast nonce "$eth_address" --rpc-url "$current_rpc_url" --block pending 2>/dev/null)
            if [ -z "$nonce" ]; then
                nonce=0
            fi
            echo "Address: $eth_address, nonce: $nonce"

            # Gas price 50% above current, minimum 10 gwei; retry with doubled gas if "replacement transaction underpriced"
            local base_gas
            base_gas=$(cast gas-price --rpc-url "$current_rpc_url" 2>/dev/null)
            if [ -z "$base_gas" ] || [ "$base_gas" -lt 1000000000 ]; then
                base_gas=1000000000
            fi
            local gas_price=$(( base_gas * 150 / 100 ))
            if [ "$gas_price" -lt 10000000000 ]; then
                gas_price=10000000000
            fi

            local max_attempts=4
            local attempt=1
            local send_output
            local send_exit
            local try_rpc_url

            while [ "$attempt" -le "$max_attempts" ]; do
                # On retry use next RPC — your node may have different mempool view
                try_rpc_url="${rpc_providers[$(((key_index + attempt - 1) % rpc_count))]}"
                echo "Gas price: $gas_price wei, RPC: $try_rpc_url (attempt $attempt/$max_attempts)"
                send_output=$(cast send 0x5595cb9ed193cac2c0bc5393313bc6115817954b \
                    "approve(address,uint256)" \
                    "$contract_address" \
                    200000ether \
                    --private-key "$private_key" \
                    --rpc-url "$try_rpc_url" \
                    --gas-price "$gas_price" 2>&1)
                send_exit=$?
                if [ "$send_exit" -eq 0 ]; then
                    echo "$send_output"
                    break
                fi
                if echo "$send_output" | grep -qi "replacement transaction underpriced\|underpriced"; then
                    echo "Underpriced, retrying with next RPC and higher gas..."
                    gas_price=$(( gas_price * 2 ))
                    attempt=$(( attempt + 1 ))
                    sleep 2
                elif echo "$send_output" | grep -qi "tls\|handshake\|eof\|connect\|timeout\|connection refused\|error sending request"; then
                    echo "RPC connection error, retrying with next RPC (same gas)..."
                    echo "$send_output"
                    attempt=$(( attempt + 1 ))
                    sleep 2
                else
                    echo "$send_output"
                    echo "Send failed (exit $send_exit)."
                    break
                fi
            done
            if [ "$send_exit" -ne 0 ]; then
                echo "Skipping to next key after $max_attempts attempts."
                echo "To fix $eth_address: clear pending tx (e.g. MetaMask: Activity -> Speed up or Cancel), then run Approve again."
            fi

            # Next validator uses next RPC in list
            key_index=$((key_index + 1))
            # Pause before next tx so previous is mined and RPC state is clear
            sleep 12
        else
            echo "Warning: No privateKey found in $key_file"
        fi
    done
}
