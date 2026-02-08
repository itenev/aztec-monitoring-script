# === Claim Rewards Function ===
claim_rewards() {
    echo -e "\n${BLUE}=== $(t "aztec_rewards_claim") ===${NC}"
    echo ""

    # Get network settings
    local settings
    settings=$(get_network_settings)
    local network=$(echo "$settings" | cut -d'|' -f1)
    local rpc_url=$(echo "$settings" | cut -d'|' -f2)
    local contract_address=$(echo "$settings" | cut -d'|' -f3)

    # Determine token symbol based on network
    local TOKEN_SYMBOL="STK"
    if [[ "$network" == "mainnet" ]]; then
        TOKEN_SYMBOL="AZTEC"
    fi

    local KEYSTORE_FILE="$HOME/aztec/config/keystore.json"

    echo -e "${CYAN}$(t "using_contract") $contract_address${NC}"
    echo -e "${CYAN}$(t "using_rpc") $rpc_url${NC}"

    # Check if rewards are claimable
    echo -e "\n${BLUE}🔍 $(t "checking_rewards_claimable")${NC}"
    local claimable_result
    claimable_result=$(cast call "$contract_address" "isRewardsClaimable()" --rpc-url "$rpc_url" 2>/dev/null)

    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ $(t "failed_check_rewards_claimable")${NC}"
        return 1
    fi

    if [ "$claimable_result" != "0x1" ]; then
            echo -e "${RED}❌ $(t "rewards_not_claimable")${NC}"

            # Get earliest claimable timestamp for information
            local timestamp_result
            timestamp_result=$(cast call "$contract_address" "getEarliestRewardsClaimableTimestamp()" --rpc-url "$rpc_url" 2>/dev/null)

            if [ $? -eq 0 ] && [ -n "$timestamp_result" ]; then
                local timestamp_dec
                timestamp_dec=$(cast --to-dec "$timestamp_result" 2>/dev/null)
                if [ $? -eq 0 ]; then
                    if [ "$timestamp_dec" -eq "0" ]; then
                        echo -e "${YELLOW}ℹ️  $(t "claim_function_not_activated")${NC}"
                    else
                        local timestamp_human
                        timestamp_human=$(date -d "@$timestamp_dec" 2>/dev/null || echo "unknown format")
                        printf -v message "$(t "earliest_rewards_claimable_timestamp")" "$timestamp_dec" "$timestamp_human"
                        echo -e "${CYAN}ℹ️  ${message}${NC}"
                    fi
                fi
            fi
            return 1
    fi

    echo -e "${GREEN}✅ $(t "rewards_are_claimable")${NC}"

    # Extract validator addresses from keystore
    if [ ! -f "$KEYSTORE_FILE" ]; then
        echo -e "\n${RED}❌ $(t "keystore_file_not_found") $KEYSTORE_FILE${NC}"
        return 1
    fi

    echo -e "\n${BLUE}📋 $(t "extracting_validator_addresses")${NC}"

    # Extract payout addresses:
    # - Prefer per-validator .coinbase
    # - If .coinbase is missing/invalid, fall back to .attester.eth
    local coinbase_addresses=()
    while IFS= read -r address; do
        if [ -n "$address" ] && [ "$address" != "null" ] && [[ "$address" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            coinbase_addresses+=("$address")
        fi
    done < <(jq -r '
        .validators[]
        | if (.coinbase != null and (.coinbase | test("^0x[0-9a-fA-F]{40}$")))
          then .coinbase
          elif (.attester.eth != null and (.attester.eth | test("^0x[0-9a-fA-F]{40}$")))
          then .attester.eth
          else empty
          end
    ' "$KEYSTORE_FILE" 2>/dev/null)

    if [ ${#coinbase_addresses[@]} -eq 0 ]; then
        echo -e "${YELLOW}⚠️ $(t "no_coinbase_addresses_found")${NC}"
        return 1
    fi

    # Remove duplicates and track unique addresses
    local unique_addresses=()
    local address_counts=()

    for addr in "${coinbase_addresses[@]}"; do
        local addr_lower=$(echo "$addr" | tr '[:upper:]' '[:lower:]')
        local found=0

        for i in "${!unique_addresses[@]}"; do
            if [ "${unique_addresses[i],,}" = "$addr_lower" ]; then
                ((address_counts[i]++))
                found=1
                break
            fi
        done

        if [ $found -eq 0 ]; then
            unique_addresses+=("$addr")
            address_counts+=("1")
        fi
    done

    echo -e "${GREEN}✅ $(t "found_unique_coinbase_addresses") ${#unique_addresses[@]}${NC}"

    # Show address distribution
    for i in "${!unique_addresses[@]}"; do
        if [ "${address_counts[i]}" -gt 1 ]; then
            printf "${CYAN}  📍 %s ($(t "repeats_times"))${NC}\n" "${unique_addresses[i]}" "${address_counts[i]}"
        else
            echo -e "${CYAN}  📍 ${unique_addresses[i]}${NC}"
        fi
    done

    # Check rewards for each unique address
    local addresses_with_rewards=()
    local reward_amounts=()

    echo -e "\n${BLUE}💰 $(t "checking_rewards")${NC}"

    for address in "${unique_addresses[@]}"; do
        echo -e "${CYAN}$(t "checking_address") $address...${NC}"

        local rewards_hex
        rewards_hex=$(cast call "$contract_address" "getSequencerRewards(address)" "$address" --rpc-url "$rpc_url" 2>/dev/null)

        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}⚠️ $(t "failed_get_rewards_for_address") $address${NC}"
            continue
        fi

        # Convert hex to decimal
        local rewards_wei
        rewards_wei=$(cast --to-dec "$rewards_hex" 2>/dev/null)

        if [ $? -ne 0 ]; then
            printf -v message "$(t "failed_convert_rewards_amount")" "$address"
            echo -e "${YELLOW}⚠️ ${message}${NC}"
            continue
        fi

        # Convert wei to human-readable token amount (18 decimals)
        local rewards_eth
        rewards_eth=$(echo "scale=6; $rewards_wei / 1000000000000000000" | bc 2>/dev/null)

        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}⚠️ $(t "failed_convert_to_eth") $address${NC}"
            continue
        fi

        # Check if rewards > 0
        if (( $(echo "$rewards_eth > 0" | bc -l) )); then
            printf -v message "$(t "rewards_amount")" "$rewards_eth"
            echo -e "${GREEN}🎯 ${message} ${TOKEN_SYMBOL}${NC}"
            addresses_with_rewards+=("$address")
            reward_amounts+=("$rewards_eth")
        else
            echo -e "${YELLOW}⏭️ $(t "no_rewards")${NC}"
        fi
    done

    if [ ${#addresses_with_rewards[@]} -eq 0 ]; then
        echo -e "${YELLOW}🎉 $(t "no_rewards_to_claim")${NC}"
        return 0
    fi

    printf "${GREEN}✅ $(t "found_unique_addresses_with_rewards") ${#addresses_with_rewards[@]}${NC}\n"

    # Claim rewards
    local claimed_count=0
    local failed_count=0
    local claimed_addresses=()

    for i in "${!addresses_with_rewards[@]}"; do
        local address="${addresses_with_rewards[$i]}"
        local amount="${reward_amounts[$i]}"

        # Check if we already claimed this address in this session
        if [[ " ${claimed_addresses[@]} " =~ " ${address} " ]]; then
            echo -e "${YELLOW}⏭️ $(t "already_claimed_this_session") $address, $(t "skipping")${NC}"
            continue
        fi

        echo -e "\n${BLUE}================================${NC}"
        echo -e "${CYAN}🎯 $(t "address_label") $address${NC}"
        printf "${YELLOW}💰 $(t "amount_eth") ${TOKEN_SYMBOL}${NC}\n" "$amount"

        # Find how many times this address repeats
        local repeat_count=0
        for j in "${!unique_addresses[@]}"; do
            if [ "${unique_addresses[j],,}" = "${address,,}" ]; then
                repeat_count="${address_counts[j]}"
                break
            fi
        done

        if [ "$repeat_count" -gt 1 ]; then
            printf "${CYAN}📊 $(t "address_appears_times")${NC}\n" "$repeat_count"
        fi

        # Ask for confirmation
        read -p "$(echo -e "\n${YELLOW}$(t "claim_rewards_confirmation") ${NC}")" confirm

        case "$confirm" in
            [yY]|yes)
                echo -e "${BLUE}🚀 $(t "claiming_rewards")${NC}"

                # Send claim transaction
                local tx_hash
                tx_hash=$(cast send "$contract_address" "claimSequencerRewards(address)" "$address" \
                    --rpc-url "$rpc_url" \
                    --keystore "$KEYSTORE_FILE" \
                    --from "$address" 2>/dev/null)

                if [ $? -eq 0 ] && [ -n "$tx_hash" ]; then
                    echo -e "${GREEN}✅ $(t "transaction_sent") $tx_hash${NC}"

                    # Wait and check receipt
                    echo -e "${BLUE}⏳ $(t "waiting_confirmation")${NC}"
                    sleep 10

                    local receipt
                    receipt=$(cast receipt "$tx_hash" --rpc-url "$rpc_url" 2>/dev/null)

                    if [ $? -eq 0 ]; then
                        local status
                        status=$(echo "$receipt" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

                        if [ "$status" = "0x1" ] || [ "$status" = "1" ]; then
                            echo -e "${GREEN}✅ $(t "transaction_confirmed_successfully")${NC}"

                            # Mark this address as claimed
                            claimed_addresses+=("$address")

                            # Verify rewards are now zero
                            local new_rewards_hex
                            new_rewards_hex=$(cast call "$contract_address" "getSequencerRewards(address)" "$address" --rpc-url "$rpc_url" 2>/dev/null)
                            local new_rewards_wei
                            new_rewards_wei=$(cast --to-dec "$new_rewards_hex" 2>/dev/null)
                            local new_rewards_eth
                            new_rewards_eth=$(echo "scale=6; $new_rewards_wei / 1000000000000000000" | bc 2>/dev/null)

                            if (( $(echo "$new_rewards_eth == 0" | bc -l) )); then
                                echo -e "${GREEN}✅ $(t "rewards_successfully_claimed")${NC}"
                            else
                                printf -v message "$(t "rewards_claimed_balance_not_zero")" "$new_rewards_eth"
                                echo -e "${YELLOW}⚠️ ${message} ${TOKEN_SYMBOL}${NC}"
                            fi

                            ((claimed_count++))

                            # If this address repeats multiple times, show message
                            if [ "$repeat_count" -gt 1 ]; then
                                printf -v message "$(t "claimed_rewards_for_address_appears_times")" "$address" "$repeat_count"
                                echo -e "${GREEN}✅ ${message}${NC}"
                            fi
                        else
                            echo -e "${RED}❌ $(t "transaction_failed")${NC}"
                            ((failed_count++))
                        fi
                    else
                        echo -e "${YELLOW}⚠️ $(t "could_not_get_receipt_transaction_sent")${NC}"
                        claimed_addresses+=("$address")
                        ((claimed_count++))
                    fi
                else
                    echo -e "${RED}❌ $(t "failed_send_transaction")${NC}"
                    ((failed_count++))
                fi
                ;;
            [nN]|no)
                echo -e "${YELLOW}⏭️ $(t "skipping_claim_for_address") $address${NC}"
                ;;
            skip)
                echo -e "${YELLOW}⏭️ $(t "skipping_all_remaining_claims")${NC}"
                break
                ;;
            *)
                echo -e "${YELLOW}⏭️ $(t "skipping_claim_for_address") $address${NC}"
                ;;
        esac

        # Delay between transactions
        if [ $i -lt $((${#addresses_with_rewards[@]} - 1)) ]; then
            echo -e "${BLUE}⏳ $(t "waiting_seconds")${NC}"
            sleep 5
        fi
    done

    # Summary
    echo -e "\n${CYAN}================================${NC}"
    echo -e "${CYAN}           $(t "summary")${NC}"
    echo -e "${CYAN}================================${NC}"
    printf "${GREEN}✅ $(t "successfully_claimed") $claimed_count${NC}\n"
    if [ $failed_count -gt 0 ]; then
        printf "${RED}❌ $(t "failed_count") $failed_count${NC}\n"
    fi
    printf "${GREEN}🎯 $(t "unique_addresses_with_rewards") ${#addresses_with_rewards[@]}${NC}\n"
    printf "${GREEN}📊 $(t "total_coinbase_addresses_in_keystore") ${#coinbase_addresses[@]}${NC}\n"
    echo -e "${CYAN}📍 $(t "contract_used") $contract_address${NC}"

    return 0
}
