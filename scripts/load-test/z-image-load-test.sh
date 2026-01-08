#!/bin/bash
#
# Z-Image-Turbo Load Test Script
# Tests concurrent requests from 1 to 20
#

# Don't exit on error - we want to continue even if some requests fail
set +e

# =============================================================================
# Configuration
# =============================================================================
BASE_URL="${BASE_URL:-http://localhost:8001}"
ENDPOINT="/v1/images/generations"
TIMEOUT="${TIMEOUT:-30}"
MAX_CONCURRENT="${MAX_CONCURRENT:-20}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_DIR="${SCRIPT_DIR}/images"

# Request body
REQUEST_BODY='{
  "prompt": "고양이와 강아지",
  "n": 1,
  "size": "1024x1024",
  "response_format": "b64_json",
  "num_inference_steps": 8,
  "cfg_scale": 1,
  "seed": -1
}'

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

# Check if curl is available
check_dependencies() {
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed."
        exit 1
    fi
    if ! command -v jq &> /dev/null; then
        print_error "jq is required but not installed."
        print_info "Install with: sudo apt-get install -y jq"
        exit 1
    fi
    if ! command -v base64 &> /dev/null; then
        print_error "base64 is required but not installed."
        exit 1
    fi
}

# Create images directory
setup_images_dir() {
    if [ ! -d "${IMAGES_DIR}" ]; then
        print_info "Creating images directory: ${IMAGES_DIR}"
        mkdir -p "${IMAGES_DIR}"
    fi
}

# Check if server is available
check_server() {
    print_info "Checking server availability at ${BASE_URL}..."
    # Use /health or just check if port is open (vllm-omni doesn't support /v1/models)
    if curl -s --connect-timeout 5 "${BASE_URL}/health" > /dev/null 2>&1; then
        print_success "Server is available (health check passed)."
        return 0
    elif curl -s --connect-timeout 5 -o /dev/null -w "%{http_code}" "${BASE_URL}/" 2>/dev/null | grep -q "200\|404\|405"; then
        print_success "Server is available (port is open)."
        return 0
    else
        print_warning "Server health check failed. Proceeding anyway..."
        return 0
    fi
}

# Single request function
make_request() {
    local request_id=$1
    local concurrent_level=$2
    local start_time=$(date +%s.%N)
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    local http_code
    local temp_response=$(mktemp)
    
    # Make request - save response to temp file, capture http code separately
    http_code=$(curl -s -w "%{http_code}" \
        --max-time "${TIMEOUT}" \
        -X POST "${BASE_URL}${ENDPOINT}" \
        -H "Content-Type: application/json" \
        -d "${REQUEST_BODY}" \
        -o "${temp_response}" 2>/dev/null) || http_code="000"
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
    
    # Check result and save image if successful
    if [[ "$http_code" == "200" ]]; then
        # Extract base64 image data and save to file
        local image_file="${IMAGES_DIR}/${timestamp}_c${concurrent_level}_r${request_id}.png"
        local b64_data=$(jq -r '.data[0].b64_json' "${temp_response}" 2>/dev/null)
        
        if [[ -n "$b64_data" && "$b64_data" != "null" ]]; then
            echo "$b64_data" | base64 -d > "$image_file" 2>/dev/null
            if [ -f "$image_file" ] && [ -s "$image_file" ]; then
                echo "REQUEST_${request_id}|SUCCESS|${duration}s|HTTP_${http_code}|${image_file}"
            else
                echo "REQUEST_${request_id}|SUCCESS|${duration}s|HTTP_${http_code}|SAVE_FAILED"
            fi
        else
            echo "REQUEST_${request_id}|SUCCESS|${duration}s|HTTP_${http_code}|NO_IMAGE_DATA"
        fi
    elif [[ "$http_code" =~ ^[0-9]+$ ]]; then
        local error_msg=$(jq -r '.error.message // .detail // "unknown"' "${temp_response}" 2>/dev/null | head -c 50)
        echo "REQUEST_${request_id}|FAILED|${duration}s|HTTP_${http_code}|${error_msg}"
    else
        echo "REQUEST_${request_id}|TIMEOUT|${TIMEOUT}s|TIMEOUT|"
    fi
    
    # Cleanup temp file
    rm -f "${temp_response}"
}

# Run concurrent requests
run_concurrent_test() {
    local concurrent=$1
    local pids=()
    local results=()
    local temp_dir=$(mktemp -d)
    local start_signal="${temp_dir}/start_signal"
    
    print_info "Starting ${concurrent} concurrent request(s)..."
    
    # Launch all workers first (they wait for signal)
    for i in $(seq 1 $concurrent); do
        (
            # Wait for start signal
            while [ ! -f "$start_signal" ]; do
                sleep 0.01
            done
            make_request $i $concurrent
        ) > "${temp_dir}/result_${i}.txt" 2>&1 &
        pids+=($!)
    done
    
    # Small delay to ensure all workers are waiting
    sleep 0.1
    
    # Send start signal - all workers start simultaneously
    local test_start=$(date +%s.%N)
    touch "$start_signal"
    
    # Wait for all requests to complete
    for pid in "${pids[@]}"; do
        wait $pid 2>/dev/null || true
    done
    
    local test_end=$(date +%s.%N)
    local total_duration=$(echo "$test_end - $test_start" | bc 2>/dev/null || echo "0")
    
    # Collect results
    local success_count=0
    local failed_count=0
    local timeout_count=0
    local total_response_time=0
    local saved_images=0
    
    echo ""
    echo "  Results:"
    for i in $(seq 1 $concurrent); do
        local result=""
        if [ -f "${temp_dir}/result_${i}.txt" ]; then
            result=$(cat "${temp_dir}/result_${i}.txt" 2>/dev/null || echo "REQUEST_${i}|ERROR|0s|READ_ERROR|")
        else
            result="REQUEST_${i}|ERROR|0s|NO_RESULT|"
        fi
        echo "    $result"
        
        if [[ "$result" == *"|SUCCESS|"* ]]; then
            success_count=$((success_count + 1))
            local response_time=$(echo "$result" | cut -d'|' -f3 | sed 's/s//')
            total_response_time=$(echo "$total_response_time + $response_time" | bc 2>/dev/null || echo "$total_response_time")
            
            # Check if image was saved
            local image_path=$(echo "$result" | cut -d'|' -f5)
            if [[ -n "$image_path" && "$image_path" != "SAVE_FAILED" && "$image_path" != "NO_IMAGE_DATA" ]]; then
                saved_images=$((saved_images + 1))
            fi
        elif [[ "$result" == *"|TIMEOUT|"* ]]; then
            timeout_count=$((timeout_count + 1))
        else
            failed_count=$((failed_count + 1))
        fi
    done
    
    # Calculate average response time
    local avg_response_time=0
    if [ $success_count -gt 0 ]; then
        avg_response_time=$(echo "scale=3; $total_response_time / $success_count" | bc 2>/dev/null || echo "0")
    fi
    
    echo ""
    echo "  Summary:"
    echo "    - Concurrent: ${concurrent}"
    echo "    - Success: ${success_count}/${concurrent}"
    echo "    - Failed: ${failed_count}"
    echo "    - Timeout: ${timeout_count}"
    echo "    - Images Saved: ${saved_images}"
    echo "    - Total Duration: ${total_duration}s"
    if [ $success_count -gt 0 ]; then
        echo "    - Avg Response Time: ${avg_response_time}s"
    fi
    echo ""
    
    # Cleanup
    rm -rf "${temp_dir}"
    
    # Return results for summary
    echo "${concurrent}|${success_count}|${failed_count}|${timeout_count}|${total_duration}|${avg_response_time}|${saved_images}" >> /tmp/load_test_summary.txt
}

# Print final summary
print_summary() {
    echo ""
    echo "=============================================="
    echo "  LOAD TEST SUMMARY"
    echo "=============================================="
    echo ""
    printf "%-12s %-10s %-10s %-10s %-10s %-12s %-12s\n" "Concurrent" "Success" "Failed" "Timeout" "Images" "Total(s)" "Avg(s)"
    printf "%-12s %-10s %-10s %-10s %-10s %-12s %-12s\n" "----------" "-------" "------" "-------" "------" "--------" "------"
    
    if [ -f /tmp/load_test_summary.txt ]; then
        while IFS='|' read -r concurrent success failed timeout total avg images; do
            printf "%-12s %-10s %-10s %-10s %-10s %-12s %-12s\n" "$concurrent" "$success" "$failed" "$timeout" "$images" "$total" "$avg"
        done < /tmp/load_test_summary.txt
        rm -f /tmp/load_test_summary.txt
    fi
    
    echo ""
    print_info "Images saved to: ${IMAGES_DIR}"
}

# =============================================================================
# Main
# =============================================================================
main() {
    echo "=============================================="
    echo "  Z-Image-Turbo Load Test"
    echo "=============================================="
    echo ""
    print_info "URL: ${BASE_URL}${ENDPOINT}"
    print_info "Timeout: ${TIMEOUT}s"
    print_info "Max Concurrent: ${MAX_CONCURRENT}"
    print_info "Images Dir: ${IMAGES_DIR}"
    echo ""
    
    check_dependencies
    setup_images_dir
    check_server
    
    # Clear previous summary
    rm -f /tmp/load_test_summary.txt
    
    echo ""
    echo "=============================================="
    echo "  Starting Load Tests"
    echo "=============================================="
    
    # Run tests from 1 to MAX_CONCURRENT
    for concurrent in $(seq 1 $MAX_CONCURRENT); do
        echo ""
        echo "----------------------------------------------"
        echo "  Test ${concurrent}/${MAX_CONCURRENT}: ${concurrent} concurrent request(s)"
        echo "----------------------------------------------"
        run_concurrent_test $concurrent
        
        # Small delay between tests
        if [ $concurrent -lt $MAX_CONCURRENT ]; then
            print_info "Waiting 2 seconds before next test..."
            sleep 2
        fi
    done
    
    print_summary
    
    print_success "Load test completed!"
}

# Help
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  BASE_URL       Base URL of the server (default: http://localhost:8001)"
    echo "  TIMEOUT        Request timeout in seconds (default: 30)"
    echo "  MAX_CONCURRENT Maximum concurrent requests (default: 20)"
    echo ""
    echo "Output:"
    echo "  Images are saved to: scripts/load-test/images/"
    echo "  Filename format: YYYYMMDD_HHMMSS_c{concurrent}_r{request}.png"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  BASE_URL=http://192.168.1.100:8001 $0"
    echo "  MAX_CONCURRENT=5 TIMEOUT=60 $0"
}

# Parse arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main
        ;;
esac

