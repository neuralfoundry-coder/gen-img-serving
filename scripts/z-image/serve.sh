#!/bin/bash
#
# Z-Image-Turbo Model Serving Script (Docker)
# Model: Tongyi-MAI/Z-Image-Turbo
# Docker Image: vllm/vllm-omni:v0.12.0rc1
#

set -e

# =============================================================================
# Configuration
# =============================================================================
CONTAINER_NAME="z-image-turbo"
DOCKER_IMAGE="vllm/vllm-omni:v0.12.0rc1"
MODEL_NAME="Tongyi-MAI/Z-Image-Turbo"

# Default values (can be overridden by environment variables)
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8001}"
INTERNAL_PORT="${INTERNAL_PORT:-8091}"
GPUS="${GPUS:-1}"  # GPU count or device ids like "0" or "0,1"
HF_CACHE="${HF_CACHE:-$HOME/.cache/huggingface}"

# Batch configuration for 32GB GPU RAM (optimized settings)
# Z-Image-Turbo 모델 기준 최적화 설정
MAX_NUM_SEQS="${MAX_NUM_SEQS:-16}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-4096}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.90}"
MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-8192}"

# =============================================================================
# Helper Functions
# =============================================================================
print_info() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

print_success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

print_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

print_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $1"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
}

check_nvidia_docker() {
    # Check if nvidia-container-toolkit is available
    if ! command -v nvidia-container-cli &> /dev/null; then
        print_warning "NVIDIA Container Toolkit may not be installed."
        print_warning "Run: sudo apt-get install -y nvidia-container-toolkit"
    fi
}

is_running() {
    docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

container_exists() {
    docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

# =============================================================================
# Commands
# =============================================================================
cmd_start() {
    print_info "Starting ${CONTAINER_NAME}..."
    
    check_docker
    check_nvidia_docker
    
    # Stop and remove existing container if exists
    if is_running; then
        print_info "Stopping existing running container..."
        docker stop "${CONTAINER_NAME}" > /dev/null
    fi
    
    if container_exists; then
        print_info "Removing existing container..."
        docker rm "${CONTAINER_NAME}" > /dev/null
    fi
    
    # Create HF cache directory if not exists
    mkdir -p "${HF_CACHE}"
    
    print_info "Configuration:"
    print_info "  - Host: ${HOST}"
    print_info "  - Port: ${PORT} (internal: ${INTERNAL_PORT})"
    print_info "  - GPUs: ${GPUS}"
    print_info "  - Max Num Seqs: ${MAX_NUM_SEQS}"
    print_info "  - Max Model Length: ${MAX_MODEL_LEN}"
    print_info "  - Max Batched Tokens: ${MAX_NUM_BATCHED_TOKENS}"
    print_info "  - GPU Memory Utilization: ${GPU_MEMORY_UTILIZATION}"
    
    docker run -d \
        --name "${CONTAINER_NAME}" \
        --runtime nvidia \
        --gpus "${GPUS}" \
        -v "${HF_CACHE}:/root/.cache/huggingface" \
        --env "HF_TOKEN=${HF_TOKEN}" \
        -p "${PORT}:${INTERNAL_PORT}" \
        --ipc=host \
        --restart unless-stopped \
        "${DOCKER_IMAGE}" \
        --model "${MODEL_NAME}" \
        --port "${INTERNAL_PORT}" \
        --max-num-seqs "${MAX_NUM_SEQS}" \
        --max-model-len "${MAX_MODEL_LEN}" \
        --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION}" \
        --max-num-batched-tokens "${MAX_NUM_BATCHED_TOKENS}"
    
    print_success "Container ${CONTAINER_NAME} started successfully!"
    print_info "API endpoint: http://${HOST}:${PORT}"
}

cmd_stop() {
    print_info "Stopping ${CONTAINER_NAME}..."
    
    if ! is_running; then
        print_warning "Container ${CONTAINER_NAME} is not running."
        return 0
    fi
    
    docker stop "${CONTAINER_NAME}" > /dev/null
    print_success "Container ${CONTAINER_NAME} stopped."
}

cmd_status() {
    if is_running; then
        print_success "Container ${CONTAINER_NAME} is running."
        echo ""
        docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.ID}}\t{{.Status}}\t{{.Ports}}"
    elif container_exists; then
        print_warning "Container ${CONTAINER_NAME} exists but is not running."
        docker ps -a --filter "name=${CONTAINER_NAME}" --format "table {{.ID}}\t{{.Status}}\t{{.Ports}}"
    else
        print_info "Container ${CONTAINER_NAME} does not exist."
    fi
}

cmd_restart() {
    print_info "Restarting ${CONTAINER_NAME}..."
    cmd_stop
    sleep 2
    cmd_start
}

cmd_logs() {
    if ! container_exists; then
        print_error "Container ${CONTAINER_NAME} does not exist."
        exit 1
    fi
    
    # Pass additional arguments to docker logs (e.g., -f, --tail, etc.)
    docker logs "$@" "${CONTAINER_NAME}"
}

cmd_help() {
    echo "Usage: $0 {start|stop|status|restart|logs} [options]"
    echo ""
    echo "Commands:"
    echo "  start    Start the Z-Image-Turbo serving container"
    echo "  stop     Stop the container"
    echo "  status   Show container status"
    echo "  restart  Restart the container"
    echo "  logs     Show container logs (supports docker logs options like -f, --tail)"
    echo ""
    echo "Environment Variables:"
    echo "  HOST                    Server host (default: 0.0.0.0)"
    echo "  PORT                    External server port (default: 8001)"
    echo "  INTERNAL_PORT           Internal container port (default: 8091)"
    echo "  GPUS                    GPU count or device ids like '0' or '0,1' (default: 1)"
    echo "  HF_TOKEN                Hugging Face API token"
    echo "  HF_CACHE                Hugging Face cache directory (default: ~/.cache/huggingface)"
    echo "  MAX_NUM_SEQS            Maximum number of sequences per batch (default: 16)"
    echo "  MAX_MODEL_LEN           Maximum model context length (default: 4096)"
    echo "  MAX_NUM_BATCHED_TOKENS  Maximum number of batched tokens (default: 8192)"
    echo "  GPU_MEMORY_UTILIZATION  GPU memory utilization ratio (default: 0.90)"
    echo ""
    echo "Examples:"
    echo "  $0 start"
    echo "  PORT=8080 $0 start"
    echo "  $0 logs -f --tail 100"
}

# =============================================================================
# Main
# =============================================================================
case "${1:-}" in
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    status)
        cmd_status
        ;;
    restart)
        cmd_restart
        ;;
    logs)
        shift
        cmd_logs "$@"
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        cmd_help
        exit 1
        ;;
esac

