# Функция для обновления ноды Aztec до последней версии
update_aztec_node() {
    echo -e "\n${GREEN}=== $(t "update_title") ===${NC}"

    # Переходим в папку с нодой
    cd "$HOME/aztec" || {
        echo -e "${RED}$(t "update_folder_error")${NC}"
        return 1
    }

    # Проверяем текущий тег в docker-compose.yml
    CURRENT_TAG=$(grep -oP 'image: aztecprotocol/aztec:\K[^\s]+' docker-compose.yml || echo "")

    if [[ "$CURRENT_TAG" != "latest" ]]; then
        echo -e "${YELLOW}$(printf "$(t "tag_check")" "$CURRENT_TAG")${NC}"
        sed -i 's|image: aztecprotocol/aztec:.*|image: aztecprotocol/aztec:latest|' docker-compose.yml
    fi

    # Обновляем образ
    echo -e "${YELLOW}$(t "update_pulling")${NC}"
    docker pull aztecprotocol/aztec:latest || {
        echo -e "${RED}$(t "update_pull_error")${NC}"
        return 1
    }

    # Останавливаем контейнеры
    echo -e "${YELLOW}$(t "update_stopping")${NC}"
    docker compose down || {
        echo -e "${RED}$(t "update_stop_error")${NC}"
        return 1
    }

    # Запускаем контейнеры
    echo -e "${YELLOW}$(t "update_starting")${NC}"
    docker compose up -d || {
        echo -e "${RED}$(t "update_start_error")${NC}"
        return 1
    }

    echo -e "${GREEN}$(t "update_success")${NC}"
}

# === Update Aztec node ===
function update_aztec() {
    update_aztec_node
}
