# === Generate BLS keys with mode selection ===
generate_bls_keys() {
    echo -e "\n${BLUE}=== BLS Keys Generation and Transfer ===${NC}"
    echo -e "${RED}WARNING: This operation involves handling private keys. Please be extremely careful and ensure you are in a secure environment.${NC}"

    # Выбор способа генерации
    echo -e "\n${CYAN}Select an action with BLS:${NC}"
    echo -e "1) $(t "bls_method_new_operator")"
    echo -e "2) $(t "bls_method_existing")"
    echo -e "3) $(t "bls_to_keystore")"
    echo -e "4) $(t "bls_method_dashboard")"
    echo ""
    read -p "$(t "bls_method_prompt") " GENERATION_METHOD

    case $GENERATION_METHOD in
        1)
            generate_bls_new_operator_method
            ;;
        2)
            generate_bls_existing_method
            ;;
        3)
            add_bls_to_keystore
            ;;
        4)
            generate_bls_dashboard_method
            ;;
        *)
            echo -e "${RED}$(t "bls_invalid_method")${NC}"
            return 1
            ;;
    esac
}
