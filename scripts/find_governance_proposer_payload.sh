# === Find governanceProposerPayload ===
find_governance_proposer_payload() {
  echo -e "\n${BLUE}$(t "search_gov")${NC}"

  # Получаем ID контейнера
  container_id=$(docker ps --format "{{.ID}} {{.Names}}" | grep aztec | grep -vE 'watchtower|otel|prometheus|grafana' | head -n 1 | awk '{print $1}')

  if [ -z "$container_id" ]; then
    echo -e "\n${RED}$(t "container_not_found")${NC}"
    return 1
  fi

  echo -e "\n${CYAN}$(t "gov_found")${NC}"

  # Вспомогательная функция для запуска поиска в фоне (writes to $1 if set, else /tmp/gov_payloads.tmp for backward compat)
  _find_payloads_worker() {
    local out="${1:-/tmp/gov_payloads.tmp}"
    docker logs "$container_id" 2>&1 | \
      grep -i '"governanceProposerPayload"' | \
      grep -o '"governanceProposerPayload":"0x[a-fA-F0-9]\{40\}"' | \
      cut -d'"' -f4 | \
      tr '[:upper:]' '[:lower:]' | \
      awk '!seen[$0]++ {print}' | \
      tail -n 10 > "$out"
  }

  # Запускаем поиск в фоне и спиннер
  local gov_payloads_tmp
  gov_payloads_tmp=$(mktemp)

  _find_payloads_worker "$gov_payloads_tmp" &
  worker_pid=$!
  spinner $worker_pid
  wait $worker_pid

  if [ ! -s "$gov_payloads_tmp" ]; then
    echo -e "\n${RED}$(t "gov_not_found")${NC}"
    rm -f "$gov_payloads_tmp"
    return 1
  fi

  mapfile -t payloads_array < "$gov_payloads_tmp"
  rm -f "$gov_payloads_tmp"

  echo -e "\n${GREEN}$(t "gov_found_results")${NC}"
  for p in "${payloads_array[@]}"; do
    echo "• $p"
  done

  if [ "${#payloads_array[@]}" -gt 1 ]; then
    echo -e "\n${RED}$(t "gov_changed")${NC}"
    for ((i = 1; i < ${#payloads_array[@]}; i++)); do
      echo -e "${YELLOW}$(t "gov_was") ${payloads_array[i-1]} → $(t "gov_now") ${payloads_array[i]}${NC}"
    done
  else
    echo -e "\n${GREEN}$(t "gov_no_changes")${NC}"
  fi

  return 0
}
