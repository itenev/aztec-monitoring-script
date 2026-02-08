# === Publisher Balance Monitoring Management ===
manage_publisher_balance_monitoring() {
  local env_file
  env_file=$(_ensure_env_file)
  source "$env_file"

  echo -e "\n${BLUE}$(t "publisher_monitoring_title")${NC}"
  echo -e "\n${NC}$(t "publisher_monitoring_option1")${NC}"
  echo -e "${NC}$(t "publisher_monitoring_option2")${NC}"
  echo -e "${NC}$(t "publisher_monitoring_option3")${NC}"

  while true; do
    echo ""
    read -p "$(t "publisher_monitoring_choose") " choice
    case "$choice" in
      1)
        # Configure balance monitoring
        echo -e "\n${BLUE}$(t "publisher_addresses_prompt")${NC}"
        echo -e "${YELLOW}$(t "publisher_addresses_format")${NC}"
        while true; do
          read -p "> " PUBLISHERS
          if [[ -n "$PUBLISHERS" ]]; then
            # Validate addresses format (basic check for 0x prefix)
            local valid=true
            IFS=',' read -ra ADDR_ARRAY <<< "$PUBLISHERS"
            for addr in "${ADDR_ARRAY[@]}"; do
              addr=$(echo "$addr" | xargs) # trim whitespace
              if [[ ! "$addr" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
                echo -e "${RED}Invalid address format: $addr${NC}"
                valid=false
                break
              fi
            done
            if [ "$valid" = true ]; then
              # Save to .env-aztec-agent (append or update)
              if [ -f "$env_file" ]; then
                if grep -q "^PUBLISHERS=" "$env_file"; then
                  # Escape special characters in PUBLISHERS for sed (using | as delimiter)
                  PUBLISHERS_ESCAPED=$(printf '%s\n' "$PUBLISHERS" | sed 's/[[\.*^$()+?{|]/\\&/g' | sed 's/|/\\|/g')
                  sed -i "s|^PUBLISHERS=.*|PUBLISHERS=\"$PUBLISHERS_ESCAPED\"|" "$env_file"
                else
                  printf 'PUBLISHERS="%s"\n' "$PUBLISHERS" >> "$env_file"
                fi
              else
                printf 'PUBLISHERS="%s"\n' "$PUBLISHERS" > "$env_file"
              fi
              # Enable monitoring
              if grep -q "^MONITORING_PUBLISHERS=" "$env_file"; then
                sed -i "s|^MONITORING_PUBLISHERS=.*|MONITORING_PUBLISHERS=true|" "$env_file"
              else
                printf 'MONITORING_PUBLISHERS=true\n' >> "$env_file"
              fi
              echo -e "\n${GREEN}$(t "publisher_monitoring_enabled")${NC}"
              break
            fi
          else
            echo -e "\n${RED}$(t "publisher_addresses_empty")${NC}"
          fi
        done
        ;;
      2)
        # Configure minimum balance threshold
        echo -e "\n${BLUE}$(t "publisher_min_balance_prompt")${NC}"
        while true; do
          read -p "> " min_balance
          if [[ -z "$min_balance" ]]; then
            min_balance="0.15"
          fi
          # Validate that it's a positive number
          if [[ "$min_balance" =~ ^[0-9]+\.?[0-9]*$ ]] && awk "BEGIN {exit !($min_balance > 0)}"; then
            # Save to .env-aztec-agent (append or update)
            if [ -f "$env_file" ]; then
              if grep -q "^MIN_BALANCE_FOR_WARNING=" "$env_file"; then
                # Escape special characters in min_balance for sed (using | as delimiter)
                MIN_BALANCE_ESCAPED=$(printf '%s\n' "$min_balance" | sed 's/[[\.*^$()+?{|]/\\&/g' | sed 's/|/\\|/g')
                sed -i "s|^MIN_BALANCE_FOR_WARNING=.*|MIN_BALANCE_FOR_WARNING=\"$MIN_BALANCE_ESCAPED\"|" "$env_file"
              else
                printf 'MIN_BALANCE_FOR_WARNING="%s"\n' "$min_balance" >> "$env_file"
              fi
            else
              printf 'MIN_BALANCE_FOR_WARNING="%s"\n' "$min_balance" > "$env_file"
            fi
            echo -e "\n${GREEN}Minimum balance threshold set to $min_balance ETH${NC}"
            break
          else
            echo -e "\n${RED}$(t "publisher_min_balance_invalid")${NC}"
          fi
        done
        ;;
      3)
        # Stop balance monitoring
        if [ -f "$env_file" ]; then
          if grep -q "^MONITORING_PUBLISHERS=" "$env_file"; then
            sed -i "s|^MONITORING_PUBLISHERS=.*|MONITORING_PUBLISHERS=false|" "$env_file"
          else
            printf 'MONITORING_PUBLISHERS=false\n' >> "$env_file"
          fi
        else
          printf 'MONITORING_PUBLISHERS=false\n' > "$env_file"
        fi
        echo -e "\n${GREEN}$(t "publisher_monitoring_disabled")${NC}"
        ;;
      *)
        echo -e "\n${RED}$(t "invalid_choice")${NC}"
        continue
        ;;
    esac
    break
  done
}
