# === Find PeerID in logs ===
find_peer_id() {
  echo -e "\n${BLUE}$(t "search_peer")${NC}"

  container_id=$(docker ps --format "{{.ID}} {{.Names}}" | grep aztec | grep -vE 'watchtower|otel|prometheus|grafana' | head -n 1 | awk '{print $1}')

  if [ -z "$container_id" ]; then
    echo -e "\n${RED}$(t "container_not_found")${NC}"
    return 1
  fi

  # Фоновый процесс для поиска peerId (writes to $1 if set, else /tmp/peer_id.tmp for backward compat)
  _find_peer_id_worker() {
    local out="${1:-/tmp/peer_id.tmp}"
    docker logs "$container_id" 2>&1 | \
      grep -i "peerId" | \
      grep -o '"peerId":"[^"]*"' | \
      cut -d'"' -f4 | \
      head -n 1 > "$out"
  }
