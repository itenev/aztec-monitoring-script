# === Check Aztec node version ===
function check_aztec_version() {

    echo -e "\n${CYAN}$(t "checking_aztec_version")${NC}"
    container_id=$(docker ps --format "{{.ID}} {{.Names}}" \
                   | grep aztec | grep -vE 'watchtower|otel|prometheus|grafana' | head -n 1 | awk '{print $1}')

    if [ -z "$container_id" ]; then
        echo -e "${RED}$(t "container_not_found")${NC}"
        return
    fi

    echo -e "${GREEN}$(t "container_found") ${BLUE}$container_id${NC}"

    # Получаем вывод команды и фильтруем только версию
    version_output=$(docker exec "$container_id" node /usr/src/yarn-project/aztec/dest/bin/index.js --version 2>/dev/null)

    # Извлекаем только строку с версией (игнорируем debug/verbose сообщения)
    version=$(echo "$version_output" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | tail -n 1)

    # Альтернативный вариант: ищем последнюю строку, которая соответствует формату версии
    if [ -z "$version" ]; then
        version=$(echo "$version_output" | tail -n 1 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+')
    fi

    # Проверяем версию с поддержкой rc версий (например: 2.0.0-rc.27)
    if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]]; then
        echo -e "${GREEN}$(t "aztec_node_version") ${BLUE}$version${NC}"
    else
        echo -e "\n${RED}$(t "aztec_version_failed")${NC}"
        echo -e "${YELLOW}$(t "raw_output"):${NC}"
        echo "$version_output"
    fi
}
