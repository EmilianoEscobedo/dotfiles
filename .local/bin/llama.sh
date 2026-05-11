#!/bin/bash

# Configuration
BASE_DIR="$HOME/ai"
MODELS_DIR="$BASE_DIR/models"
SERVER_BIN="$BASE_DIR/llama.cpp/build/bin/llama-server"
PORT=8081
OPENCODE_CONFIG="$HOME/.config/opencode/config.json"

# Colors
GRAY='\033[90m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[1;35m'
RED='\033[1;31m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
NC='\033[0m'

VERBOSE=false
[[ "$1" == "--verbose" ]] && VERBOSE=true

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "▗▄▖  ▗▄▖                      ▗▄▖          ▗▖";
    echo "▝▜▌  ▝▜▌                      ▝▜▌          ▐▌";
    echo " ▐▌   ▐▌   ▟██▖▐█▙█▖ ▟██▖      ▐▌   ▟█▟▌ ▟█▟▌";
    echo " ▐▌   ▐▌   ▘▄▟▌▐▌█▐▌ ▘▄▟▌      ▐▌  ▐▛ ▜▌▐▛ ▜▌";
    echo " ▐▌   ▐▌  ▗█▀▜▌▐▌█▐▌▗█▀▜▌ ██▌  ▐▌  ▐▌ ▐▌▐▌ ▐▌";
    echo " ▐▙▄  ▐▙▄ ▐▙▄█▌▐▌█▐▌▐▙▄█▌      ▐▙▄ ▝█▄█▌▝█▄█▌";
    echo "  ▀▀   ▀▀  ▀▀▝▘▝▘▀▝▘ ▀▀▝▘       ▀▀  ▞▀▐▌ ▝▀▝▘";
    echo "                                    ▜█▛▘     ";
    echo -e "${NC}"
}

sync_to_opencode() {
    local active_model_path=$1
    local active_model_id=$(basename "$active_model_path" .gguf)
    
    mkdir -p "$(dirname "$OPENCODE_CONFIG")"

    # Ensure jq is present
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}⚠️  jq not found. Cannot sync library.${NC}"
        return
    fi

    # Build the models list object
    local models_json="{"
    for f in "$MODELS_DIR"/*.gguf; do
        [ -e "$f" ] || continue
        id=$(basename "$f" .gguf)
        models_json+="\"$id\": {\"name\": \"$id\"},"
    done
    models_json="${models_json%,}}" 

    # Correcting to singular "provider" and using "llamacpp" ID from your reference script
    jq -n \
        --arg base "http://127.0.0.1:$PORT/v1" \
        --arg active "llamacpp/$active_model_id" \
        --argjson list "$models_json" \
        '
        .provider.llamacpp = {
            "npm": "@ai-sdk/openai-compatible",
            "name": "Local llama.cpp",
            "options": { "baseURL": $base, "apiKey": "none" },
            "models": $list
        } | .model = $active
        ' > "$OPENCODE_CONFIG"
}

list_models() {
    show_banner
    echo -e "${BOLD}📦 Available Models:${NC}\n"
    mapfile -t models < <(ls "$MODELS_DIR"/*.gguf 2>/dev/null)
    
    local i=1
    for model in "${models[@]}"; do
        filename=$(basename "$model")
        size=$(du -h "$model" | cut -f1 | tr '[:upper:]' '[:lower:]')
        echo -e "  ${CYAN}$i)${NC} $filename ${GRAY}($size)${NC}"
        ((i++))
    done

    echo -e "\n  ${CYAN}$i)${NC} 📥 Download new model (HF)"
    echo -e "  ${CYAN}q)${NC} Exit"
    echo -ne "\n${BOLD}  Selection > ${NC}"
    read choice

    if [[ "$choice" == "q" ]]; then exit 0;
    elif [[ "$choice" -eq "$i" ]]; then download_model;
    elif [[ "$choice" -gt 0 && "$choice" -lt "$i" ]]; then
        ask_context "${models[$((choice-1))]}"
    else
        echo -e "  ${YELLOW}Invalid selection.${NC}"; sleep 1; list_models
    fi
}

ask_context() {
    local model_path=$1
    echo -ne "\n${BOLD}  🧠 Context (e.g. 16k, 32k) or [Enter] for auto: ${NC}"
    read ctx_input
    
    local ctx_final=""
    if [[ "$ctx_input" =~ ^([0-9]+)[kK]$ ]]; then
        ctx_final=$(( ${BASH_REMATCH[1]} * 1024 ))
    elif [[ "$ctx_input" =~ ^[0-9]+$ ]]; then
        ctx_final="$ctx_input"
    fi
    run_model "$model_path" "$ctx_final"
}

download_model() {
    echo -e "\n${BOLD}🌐 Hugging Face Downloader${NC}"
    read -p "  Repo: " repo
    read -p "  File: " file
    huggingface-cli download "$repo" "$file" --local-dir "$MODELS_DIR" --local-dir-use-symlinks False
    echo -e "\n${GREEN}✅ Success!${NC}"; sleep 2; list_models
}

run_model() {
    local model_path=$1
    local ctx_size=$2
    local model_name=$(basename "$model_path")
    local E=$(printf '\033')
    local ARGS=("-m" "$model_path" "--port" "$PORT" "-ngl" "999" "-fa" "on")
    [[ -n "$ctx_size" ]] && ARGS+=("-c" "$ctx_size")

    # Sync to OpenCode using singular key
    sync_to_opencode "$model_path"

    show_banner
    echo -e "  ${GREEN}🚀 Launching:${NC} ${BOLD}$model_name${NC}"
    [[ -n "$ctx_size" ]] && echo -e "  ${CYAN}🧠 Context:${NC}   $ctx_size tokens"
    echo -e "  ${CYAN}🌐 Web UI:${NC}    ${GREEN}${UNDERLINE}http://127.0.0.1:8081${NC}"
    echo -e "  ${MAGENTA}⚙️ Config:${NC}    Synced to OpenCode config.json"
    
    if [ "$VERBOSE" = true ]; then
        echo -e "${YELLOW}🛠️  Verbose mode: Output formatting disabled.${NC}"
    fi
    echo -e "${GRAY}-------------------------------------------------------${NC}\n"

    trap 'kill -TERM -$PID 2>/dev/null; echo -e "\n${YELLOW}⏹️  Server stopped.${NC}"; sleep 1; list_models' SIGINT

    set -m
    if [ "$VERBOSE" = true ]; then
        "$SERVER_BIN" "${ARGS[@]}" 2>&1 &
    else
        "$SERVER_BIN" "${ARGS[@]}" 2>&1 | \
        grep --line-buffered -v -E "speculative|slots are idle|slot load|llama_model_loader: -|load: |chat template|example_format|<\|im_start\|>|helpful assistant|Hello|Hi there|How are you?|<think>|warming up|print_info:|llama_kv_cache:|llama_context:|llama_memory_recurrent:|sched_reserve:|llm_load_print_meta|logit bias = -inf" | \
        sed -u \
            -e "s/.*memory breakdown.*/${E}[1;35m📊 &${E}[0m/; t" \
            -e "s/.*Vulkan0.*/${E}[1;33m⚡ &${E}[0m/; t" \
            -e "s/.*projected to use.*/${E}[1;32m💾 &${E}[0m/; t" \
            -e "s/.*will leave.*no changes needed.*/${E}[1;32m🔋 &${E}[0m/; t" \
            -e "s/.*successfully fit.*/${E}[1;32m✅ &${E}[0m/; t" \
            -e "s/.*loaded meta data.*/${E}[1;36m🧬 &${E}[0m/; t" \
            -e "s/.*offloading.*GPU.*/${E}[1;34m⚙️  &${E}[0m/; t" \
            -e "s/.*offloaded.*layers to GPU.*/${E}[1;32m🔥 &${E}[0m/; t" \
            -e "s/.*n_ctx .*=.*/${E}[1;36m🧠 &${E}[0m/; t" \
            -e "s/.*not be utilized.*/${E}[1;33m⚠️  &${E}[0m/; t" \
            -e "s/.*model loaded.*/${E}[1;32m✨ &${E}[0m/; t" \
            -e "s/.*server is listening on.*/${E}[1;32m🌐 ${E}[4m&${E}[0m/; t" \
            -e "s/.*cannot meet free memory.*/${E}[1;31m❌ &${E}[0m/; t" \
            -e "s/.*need to reduce.*/${E}[1;31m🛑 &${E}[0m/; t" \
            -e "s/.*/${E}[90m&${E}[0m/" &
    fi
    
    PID=$!
    wait $PID
    set +m
}

list_models
