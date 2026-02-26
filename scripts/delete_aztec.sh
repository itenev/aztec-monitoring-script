# === Delete Aztec node implementation ===
delete_aztec_node() {
    echo -e "\n${RED}=== $(t "delete_node") ===${NC}"

    # Основной запрос
    while :; do
        read -p "$(t "delete_confirm") " -n 1 -r
        [[ $REPLY =~ ^[YyNn]$ ]] && break
        echo -e "\n${YELLOW}$(t "enter_yn")${NC}"
    done
    echo  # Фиксируем окончательный перевод строки

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}$(t "stopping_containers")${NC}"
        docker compose -f "$HOME/aztec/docker-compose.yml" down || true

        echo -e "${YELLOW}$(t "removing_node_data")${NC}"
        if [ -d "$HOME/.aztec" ] && [ -O "$HOME/.aztec" ]; then
            rm -rf "$HOME/.aztec"
        else
            sudo rm -rf "$HOME/.aztec"
        fi
        if [ -d "$HOME/aztec" ] && [ -O "$HOME/aztec" ]; then
            rm -rf "$HOME/aztec"
        else
            sudo rm -rf "$HOME/aztec"
        fi

        echo -e "${GREEN}$(t "node_deleted")${NC}"

        # Проверяем Watchtower
        if [ -d "$HOME/watchtower" ] || docker ps -a --format '{{.Names}}' | grep -q 'watchtower'; then
            while :; do
                read -p "$(t "delete_watchtower_confirm") " -n 1 -r
                [[ $REPLY =~ ^[YyNn]$ ]] && break
                echo -e "\n${YELLOW}$(t "enter_yn")${NC}"
            done
            echo

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}$(t "stopping_watchtower")${NC}"
                docker stop watchtower 2>/dev/null || true
                docker rm watchtower 2>/dev/null || true
                [ -f "$HOME/watchtower/docker-compose.yml" ] && docker compose -f "$HOME/watchtower/docker-compose.yml" down || true

                echo -e "${YELLOW}$(t "removing_watchtower_data")${NC}"
                if [ -d "$HOME/watchtower" ] && [ -O "$HOME/watchtower" ]; then
                    rm -rf "$HOME/watchtower"
                else
                    sudo rm -rf "$HOME/watchtower"
                fi
                echo -e "${GREEN}$(t "watchtower_deleted")${NC}"
            else
                echo -e "${GREEN}$(t "watchtower_kept")${NC}"
            fi
        fi

        # Проверяем web3signer
        if docker ps -a --format '{{.Names}}' | grep -q 'web3signer'; then
            while :; do
                read -p "$(t "delete_web3signer_confirm") " -n 1 -r
                [[ $REPLY =~ ^[YyNn]$ ]] && break
                echo -e "\n${YELLOW}$(t "enter_yn")${NC}"
            done
            echo

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}$(t "stopping_web3signer")${NC}"
                docker stop web3signer 2>/dev/null || true
                docker rm web3signer 2>/dev/null || true

                echo -e "${YELLOW}$(t "removing_web3signer_data")${NC}"
                # Данные web3signer находятся в $HOME/aztec/keys, который уже удален выше
                echo -e "${GREEN}$(t "web3signer_deleted")${NC}"
            else
                echo -e "${GREEN}$(t "web3signer_kept")${NC}"
            fi
        fi

        return 0
    else
        echo -e "${YELLOW}$(t "delete_canceled")${NC}"
        return 1
    fi
}

# === Delete Aztec node ===
function delete_aztec() {
    delete_aztec_node
}
