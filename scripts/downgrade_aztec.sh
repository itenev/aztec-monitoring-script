# Функция для даунгрейда ноды Aztec
downgrade_aztec_node() {
    echo -e "\n${GREEN}=== $(t "downgrade_title") ===${NC}"

    # Получаем список доступных тегов с Docker Hub с обработкой пагинации
    echo -e "${YELLOW}$(t "downgrade_fetching")${NC}"

    # Собираем все теги с нескольких страниц
    ALL_TAGS=""
    PAGE=1
    while true; do
        PAGE_TAGS=$(curl -s "https://hub.docker.com/v2/repositories/aztecprotocol/aztec/tags/?page=$PAGE&page_size=100" | jq -r '.results[].name' 2>/dev/null)

        if [ -z "$PAGE_TAGS" ] || [ "$PAGE_TAGS" = "null" ] || [ "$PAGE_TAGS" = "" ]; then
            break
        fi

        ALL_TAGS="$ALL_TAGS"$'\n'"$PAGE_TAGS"
        PAGE=$((PAGE + 1))

        # Ограничим максимальное количество страниц для безопасности
        if [ $PAGE -gt 10 ]; then
            break
        fi
    done

    if [ -z "$ALL_TAGS" ]; then
        echo -e "${RED}$(t "downgrade_fetch_error")${NC}"
        return 1
    fi

    # Фильтруем теги: оставляем только latest и стабильные версии (формат X.Y.Z)
    FILTERED_TAGS=$(echo "$ALL_TAGS" | grep -E '^(latest|[0-9]+\.[0-9]+\.[0-9]+)$' | grep -v -E '.*-(rc|night|alpha|beta|dev|test|unstable|preview).*' | sort -Vr | uniq)

    # Выводим список тегов с нумерацией
    if [ -z "$FILTERED_TAGS" ]; then
        echo -e "${RED}$(t "downgrade_no_stable_versions")${NC}"
        return 1
    fi

    echo -e "\n${CYAN}$(t "downgrade_available")${NC}"
    select TAG in $FILTERED_TAGS; do
        if [ -n "$TAG" ]; then
            break
        else
            echo -e "${RED}$(t "downgrade_invalid_choice")${NC}"
        fi
    done

    echo -e "\n${YELLOW}$(t "downgrade_selected") $TAG${NC}"

    # Переходим в папку с нодой
    cd "$HOME/aztec" || {
        echo -e "${RED}$(t "downgrade_folder_error")${NC}"
        return 1
    }

    # Обновляем образ до выбранной версии
    echo -e "${YELLOW}$(t "downgrade_pulling")$TAG...${NC}"
    docker pull aztecprotocol/aztec:"$TAG" || {
        echo -e "${RED}$(t "downgrade_pull_error")${NC}"
        return 1
    }

    # Останавливаем контейнеры
    echo -e "${YELLOW}$(t "downgrade_stopping")${NC}"
    docker compose down || {
        echo -e "${RED}$(t "downgrade_stop_error")${NC}"
        return 1
    }

    # Изменяем версию в docker-compose.yml
    echo -e "${YELLOW}$(t "downgrade_updating")${NC}"
    sed -i "s|image: aztecprotocol/aztec:.*|image: aztecprotocol/aztec:$TAG|" docker-compose.yml || {
        echo -e "${RED}$(t "downgrade_update_error")${NC}"
        return 1
    }

    # Запускаем контейнеры
    echo -e "${YELLOW}$(t "downgrade_starting") $TAG...${NC}"
    docker compose up -d || {
        echo -e "${RED}$(t "downgrade_start_error")${NC}"
        return 1
    }

    echo -e "${GREEN}$(t "downgrade_success") $TAG!${NC}"
}

# === Downgrade Aztec node ===
function downgrade_aztec() {
    downgrade_aztec_node
}
