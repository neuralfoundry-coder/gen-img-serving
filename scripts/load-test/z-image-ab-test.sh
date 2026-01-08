#!/bin/bash
#
# Z-Image-Turbo Load Test Script
# True concurrent request testing with image saving
#

set +e

# =============================================================================
# Configuration
# =============================================================================
BASE_URL="${BASE_URL:-http://localhost:8001}"
ENDPOINT="/v1/images/generations"
TIMEOUT="${TIMEOUT:-60}"
MAX_CONCURRENT="${MAX_CONCURRENT:-20}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_DIR="${SCRIPT_DIR}/images"
RESULTS_DIR="${SCRIPT_DIR}/results"

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

# Check dependencies
check_dependencies() {
    local missing=0
    
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed."
        missing=1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_error "jq is required but not installed."
        print_info "Install with: sudo apt-get install -y jq"
        missing=1
    fi
    
    if ! command -v xargs &> /dev/null; then
        print_error "xargs is required but not installed."
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        exit 1
    fi
    
    print_success "All dependencies are installed."
}

# Setup directories
setup_directories() {
    mkdir -p "${IMAGES_DIR}"
    mkdir -p "${RESULTS_DIR}"
}

# Check if server is available
check_server() {
    print_info "Checking server availability at ${BASE_URL}..."
    if curl -s --connect-timeout 5 "${BASE_URL}/v1/models" > /dev/null 2>&1; then
        print_success "Server is available."
        return 0
    else
        print_warning "Server may not be available. Proceeding anyway..."
        return 0
    fi
}

# Single request function (called by xargs)
# Args: concurrent_level request_id images_subdir
do_request() {
    local concurrent=$1
    local request_id=$2
    local images_subdir=$3
    local start_time=$(date +%s.%N)
    
    local temp_response=$(mktemp)
    local image_file="${images_subdir}/${request_id}.png"
    
    # Make request
    local http_code=$(curl -s -w "%{http_code}" \
        --max-time "${TIMEOUT}" \
        -X POST "${BASE_URL}${ENDPOINT}" \
        -H "Content-Type: application/json" \
        -d "${REQUEST_BODY}" \
        -o "${temp_response}" 2>/dev/null) || http_code="000"
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
    
    local status="FAILED"
    local saved="NO"
    
    if [[ "$http_code" == "200" ]]; then
        # Extract and save image
        local b64_data=$(jq -r '.data[0].b64_json' "${temp_response}" 2>/dev/null)
        
        if [[ -n "$b64_data" && "$b64_data" != "null" ]]; then
            echo "$b64_data" | base64 -d > "$image_file" 2>/dev/null
            if [ -f "$image_file" ] && [ -s "$image_file" ]; then
                status="SUCCESS"
                saved="YES"
            fi
        fi
    elif [[ "$http_code" == "000" ]]; then
        status="TIMEOUT"
    fi
    
    rm -f "${temp_response}"
    
    # Output result
    echo "${request_id}|${status}|${http_code}|${duration}|${saved}"
}

export -f do_request
export BASE_URL ENDPOINT TIMEOUT REQUEST_BODY

# Run concurrent test
run_concurrent_test() {
    local concurrent=$1
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local images_subdir="${IMAGES_DIR}/c${concurrent}_${timestamp}"
    local result_file="${RESULTS_DIR}/c${concurrent}_${timestamp}.txt"
    
    # Create images subdirectory for this test
    mkdir -p "${images_subdir}"
    
    print_info "Starting ${concurrent} concurrent request(s)..."
    print_info "Images will be saved to: ${images_subdir}"
    
    local test_start=$(date +%s.%N)
    
    # Generate request IDs and run in parallel using xargs
    seq 1 $concurrent | xargs -P $concurrent -I {} bash -c \
        "do_request $concurrent {} '${images_subdir}'" > "${result_file}"
    
    local test_end=$(date +%s.%N)
    local total_duration=$(echo "$test_end - $test_start" | bc 2>/dev/null || echo "0")
    
    # Parse results
    local success_count=0
    local failed_count=0
    local timeout_count=0
    local saved_count=0
    local total_response_time=0
    
    echo ""
    echo "  Individual Results:"
    while IFS='|' read -r req_id status http_code duration saved; do
        printf "    Request %2s: %-8s HTTP:%s  Time:%ss  Image:%s\n" \
            "$req_id" "$status" "$http_code" "$duration" "$saved"
        
        case "$status" in
            SUCCESS)
                success_count=$((success_count + 1))
                total_response_time=$(echo "$total_response_time + $duration" | bc 2>/dev/null || echo "$total_response_time")
                ;;
            TIMEOUT)
                timeout_count=$((timeout_count + 1))
                ;;
            *)
                failed_count=$((failed_count + 1))
                ;;
        esac
        
        if [[ "$saved" == "YES" ]]; then
            saved_count=$((saved_count + 1))
        fi
    done < "${result_file}"
    
    # Calculate average
    local avg_time=0
    if [ $success_count -gt 0 ]; then
        avg_time=$(echo "scale=3; $total_response_time / $success_count" | bc 2>/dev/null || echo "0")
    fi
    
    # Print summary box
    echo ""
    echo "  ┌─────────────────────────────────────────────────┐"
    printf "  │ Concurrent: %-36s│\n" "$concurrent"
    printf "  │ Success: %-4s  Failed: %-4s  Timeout: %-4s     │\n" "$success_count" "$failed_count" "$timeout_count"
    printf "  │ Images Saved: %-4s / %-4s                       │\n" "$saved_count" "$concurrent"
    printf "  │ Total Time: %-8ss                          │\n" "$total_duration"
    printf "  │ Avg Response: %-8ss                        │\n" "$avg_time"
    printf "  │ Images: %-38s│\n" "c${concurrent}_${timestamp}/"
    echo "  └─────────────────────────────────────────────────┘"
    echo ""
    
    # List saved images
    local image_count=$(ls -1 "${images_subdir}"/*.png 2>/dev/null | wc -l)
    if [ "$image_count" -gt 0 ]; then
        print_success "Saved ${image_count} image(s):"
        ls -la "${images_subdir}"/*.png 2>/dev/null | awk '{print "    " $NF}'
    fi
    
    # Return summary line for final report
    echo "${concurrent}|${success_count}|${failed_count}|${timeout_count}|${saved_count}|${total_duration}|${avg_time}" >> /tmp/load_test_summary_$$.txt
}

# Print final summary
print_summary() {
    local summary_file="/tmp/load_test_summary_$$.txt"
    
    if [ ! -f "$summary_file" ]; then
        return
    fi
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "  FINAL LOAD TEST SUMMARY"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
    printf "%-10s %-10s %-10s %-10s %-10s %-12s %-10s\n" \
        "Concurrent" "Success" "Failed" "Timeout" "Images" "Total(s)" "Avg(s)"
    printf "%-10s %-10s %-10s %-10s %-10s %-12s %-10s\n" \
        "----------" "-------" "------" "-------" "------" "--------" "------"
    
    while IFS='|' read -r concurrent success failed timeout saved total avg; do
        printf "%-10s %-10s %-10s %-10s %-10s %-12s %-10s\n" \
            "$concurrent" "$success" "$failed" "$timeout" "$saved" "$total" "$avg"
    done < "$summary_file"
    
    echo ""
    print_info "Images directory: ${IMAGES_DIR}"
    print_info "Results directory: ${RESULTS_DIR}"
    echo ""
    
    # Show directory structure
    echo "  Image folders:"
    ls -d "${IMAGES_DIR}"/c*_* 2>/dev/null | while read dir; do
        local count=$(ls -1 "$dir"/*.png 2>/dev/null | wc -l)
        echo "    $(basename $dir)/ - ${count} images"
    done
    
    rm -f "$summary_file"
}

# =============================================================================
# Main
# =============================================================================
main() {
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "  Z-Image-Turbo Load Test (True Concurrent)"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
    print_info "URL: ${BASE_URL}${ENDPOINT}"
    print_info "Timeout: ${TIMEOUT}s"
    print_info "Max Concurrent: ${MAX_CONCURRENT}"
    echo ""
    
    check_dependencies
    setup_directories
    check_server
    
    # Clear previous summary
    rm -f /tmp/load_test_summary_$$.txt
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "  Starting Load Tests (1 to ${MAX_CONCURRENT} concurrent)"
    echo "═══════════════════════════════════════════════════════════════════════"
    
    # Run tests from 1 to MAX_CONCURRENT
    for concurrent in $(seq 1 $MAX_CONCURRENT); do
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Test ${concurrent}/${MAX_CONCURRENT}: ${concurrent} concurrent request(s)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        run_concurrent_test $concurrent
        
        # Delay between tests (let server recover)
        if [ $concurrent -lt $MAX_CONCURRENT ]; then
            print_info "Waiting 5 seconds before next test..."
            sleep 5
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
    echo "  TIMEOUT        Request timeout in seconds (default: 60)"
    echo "  MAX_CONCURRENT Maximum concurrent requests (default: 20)"
    echo ""
    echo "Output:"
    echo "  Images are saved to: scripts/load-test/images/c{N}_{timestamp}/"
    echo "  Each concurrent test creates a numbered folder with N images"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  BASE_URL=http://192.168.1.100:8001 $0"
    echo "  MAX_CONCURRENT=10 $0"
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
