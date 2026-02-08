# === Stop Aztec containers ===
function stop_aztec_containers() {
  local env_file
  env_file=$(_ensure_env_file)

  local run_type
  run_type=$(_read_env_var "$env_file" "RUN_TYPE")

  case "$run_type" in
    "DOCKER")
      local compose_path
      compose_path=$(_read_env_var "$env_file" "COMPOSE_PATH")

      if ! _validate_compose_path "$compose_path"; then
        read -p "$(t "enter_compose_path")" compose_path
        if _validate_compose_path "$compose_path"; then
          _update_env_var "$env_file" "COMPOSE_PATH" "$compose_path"
        else
          echo -e "${RED}$(t "invalid_path")${NC}"
          return 1
        fi
      fi

      _update_env_var "$env_file" "RUN_TYPE" "DOCKER"

      if cd "$compose_path" && docker compose down; then
        echo -e "${GREEN}$(t "docker_stop_success")${NC}"
      else
        echo -e "${RED}Failed to stop Docker containers${NC}"
        return 1
      fi
      ;;

    "CLI")
      local session_name
      session_name=$(_read_env_var "$env_file" "SCREEN_SESSION")

      if [[ -z "$session_name" ]]; then
        session_name=$(screen -ls | grep aztec | awk '{print $1}')
        # Extract only the alphabetical part (remove numbers and .aztec)
        session_name=$(echo "$session_name" | sed 's/^[0-9]*\.//;s/\.aztec$//')
        if [[ -z "$session_name" ]]; then
          echo -e "${RED}$(t "no_aztec_screen")${NC}"
          return 1
        fi
        _update_env_var "$env_file" "SCREEN_SESSION" "$session_name"
      fi

      _update_env_var "$env_file" "RUN_TYPE" "CLI"

      screen -S "$session_name" -p 0 -X stuff $'\003'
      sleep 2
      screen -S "$session_name" -X quit
      echo -e "${GREEN}$(t "cli_stop_success")${NC}"
      ;;

    *)
      echo -e "\n${YELLOW}$(t "stop_method_prompt")${NC}"
      read -r method

      case "$method" in
        "docker-compose")
          read -p "$(t "enter_compose_path")" compose_path
          if _validate_compose_path "$compose_path"; then
            _update_env_var "$env_file" "COMPOSE_PATH" "$compose_path"
            _update_env_var "$env_file" "RUN_TYPE" "DOCKER"

            cd "$compose_path" || return 1
            docker compose down
            echo -e "${GREEN}$(t "docker_stop_success")${NC}"
          else
            echo -e "${RED}$(t "invalid_path")${NC}"
            return 1
          fi
          ;;

        "cli")
          local session_name
          session_name=$(screen -ls | grep aztec | awk '{print $1}')
          if [[ -n "$session_name" ]]; then
            # Extract only the alphabetical part (remove numbers and .aztec)
            session_name=$(echo "$session_name" | sed 's/^[0-9]*\.//;s/\.aztec$//')
            _update_env_var "$env_file" "SCREEN_SESSION" "$session_name"
            _update_env_var "$env_file" "RUN_TYPE" "CLI"

            screen -S "$session_name" -p 0 -X stuff $'\003'
            sleep 2
            screen -S "$session_name" -X quit
            echo -e "${GREEN}$(t "cli_stop_success")${NC}"
          else
            echo -e "${RED}$(t "no_aztec_screen")${NC}"
            return 1
          fi
          ;;

        *)
          echo -e "${RED}Invalid method. Choose 'docker-compose' or 'cli'.${NC}"
          return 1
          ;;
      esac
      ;;
  esac
}
