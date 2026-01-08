#!/bin/bash
#
# Z-Image-Turbo Load Test Script using Apache Benchmark (ab)
# True concurrent request testing
#

set +e

# =============================================================================
# Configuration
# =============================================================================
BASE_URL="${BASE_URL:-http://localhost:8001}"
ENDPOINT="/v1/images/generations"
TIMEOUT="${TIMEOUT:-30}"
MAX_CONCURRENT="${MAX_CONCURRENT:-20}"
REQUESTS_PER_LEVEL="${REQUESTS_PER_LEVEL:-1}"  # Number of requests per concurrency level

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# Check and install ab
check_and_install_ab() {
    if command -v ab &> /dev/null; then
        print_success "Apache Benchmark (ab) is installed."
        return 0
    fi
    
    print_warning "Apache Benchmark (ab) is not installed. Installing..."
    
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install -y apache2-utils
    elif [ -f /etc/redhat-release ]; then
        # CentOS/RHEL
        sudo yum install -y httpd-tools
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS - ab comes with macOS
        print_info "ab should be pre-installed on macOS"
    else
        print_error "Unknown OS. Please install apache2-utils manually."
        exit 1
    fi
    
    if command -v ab &> /dev/null; then
        print_success "Apache Benchmark installed successfully."
    else
        print_error "Failed to install Apache Benchmark."
        exit 1
    fi
}

# Setup results directory
setup_results_dir() {
    if [ ! -d "${RESULTS_DIR}" ]; then
        print_info "Creating results directory: ${RESULTS_DIR}"
        mkdir -p "${RESULTS_DIR}"
    fi
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

# Run ab test for specific concurrency
run_ab_test() {
    local concurrent=$1
    local total_requests=$((concurrent * REQUESTS_PER_LEVEL))
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local result_file="${RESULTS_DIR}/ab_c${concurrent}_${timestamp}.txt"
    local body_file=$(mktemp)
    
    # Write request body to temp file
    echo "${REQUEST_BODY}" > "${body_file}"
    
    print_info "Running: ${concurrent} concurrent, ${total_requests} total requests"
    
    # Run ab test
    ab -n ${total_requests} \
       -c ${concurrent} \
       -s ${TIMEOUT} \
       -T "application/json" \
       -p "${body_file}" \
       "${BASE_URL}${ENDPOINT}" 2>&1 | tee "${result_file}"
    
    # Cleanup
    rm -f "${body_file}"
    
    # Extract key metrics
    local complete=$(grep "Complete requests:" "${result_file}" | awk '{print $3}')
    local failed=$(grep "Failed requests:" "${result_file}" | awk '{print $3}')
    local rps=$(grep "Requests per second:" "${result_file}" | awk '{print $4}')
    local time_per_req=$(grep "Time per request:" "${result_file}" | head -1 | awk '{print $4}')
    local total_time=$(grep "Time taken for tests:" "${result_file}" | awk '{print $5}')
    
    echo ""
    echo "  ┌─────────────────────────────────────────┐"
    echo "  │ Concurrent: ${concurrent}"
    echo "  │ Complete: ${complete:-0} / Failed: ${failed:-0}"
    echo "  │ Requests/sec: ${rps:-0}"
    echo "  │ Time/request: ${time_per_req:-0} ms"
    echo "  │ Total time: ${total_time:-0} s"
    echo "  └─────────────────────────────────────────┘"
    echo ""
    
    # Append to summary
    echo "${concurrent}|${complete:-0}|${failed:-0}|${rps:-0}|${time_per_req:-0}|${total_time:-0}" >> "${RESULTS_DIR}/summary_${timestamp}.csv"
}

# Print final summary
print_summary() {
    local latest_summary=$(ls -t "${RESULTS_DIR}"/summary_*.csv 2>/dev/null | head -1)
    
    if [ -z "$latest_summary" ] || [ ! -f "$latest_summary" ]; then
        return
    fi
    
    echo ""
    echo "=============================================="
    echo "  LOAD TEST SUMMARY (Apache Benchmark)"
    echo "=============================================="
    echo ""
    printf "%-12s %-10s %-10s %-12s %-15s %-12s\n" "Concurrent" "Complete" "Failed" "Req/sec" "Time/req(ms)" "Total(s)"
    printf "%-12s %-10s %-10s %-12s %-15s %-12s\n" "----------" "--------" "------" "-------" "-----------" "--------"
    
    while IFS='|' read -r concurrent complete failed rps time_per_req total_time; do
        printf "%-12s %-10s %-10s %-12s %-15s %-12s\n" "$concurrent" "$complete" "$failed" "$rps" "$time_per_req" "$total_time"
    done < "$latest_summary"
    
    echo ""
    print_info "Detailed results saved to: ${RESULTS_DIR}"
}

# =============================================================================
# Main
# =============================================================================
main() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    echo "=============================================="
    echo "  Z-Image-Turbo Load Test (Apache Benchmark)"
    echo "=============================================="
    echo ""
    print_info "URL: ${BASE_URL}${ENDPOINT}"
    print_info "Timeout: ${TIMEOUT}s"
    print_info "Max Concurrent: ${MAX_CONCURRENT}"
    print_info "Requests per level: ${REQUESTS_PER_LEVEL}"
    echo ""
    
    check_and_install_ab
    setup_results_dir
    check_server
    
    # Initialize summary file
    rm -f "${RESULTS_DIR}/summary_${timestamp}.csv"
    
    echo ""
    echo "=============================================="
    echo "  Starting Load Tests"
    echo "=============================================="
    
    # Run tests from 1 to MAX_CONCURRENT
    for concurrent in $(seq 1 $MAX_CONCURRENT); do
        echo ""
        echo "----------------------------------------------"
        echo "  Test ${concurrent}/${MAX_CONCURRENT}"
        echo "----------------------------------------------"
        run_ab_test $concurrent
        
        # Small delay between tests
        if [ $concurrent -lt $MAX_CONCURRENT ]; then
            print_info "Waiting 3 seconds before next test..."
            sleep 3
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
    echo "  BASE_URL            Base URL of the server (default: http://localhost:8001)"
    echo "  TIMEOUT             Request timeout in seconds (default: 30)"
    echo "  MAX_CONCURRENT      Maximum concurrent requests (default: 20)"
    echo "  REQUESTS_PER_LEVEL  Requests per concurrency level (default: 1)"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  BASE_URL=http://192.168.1.100:8001 $0"
    echo "  MAX_CONCURRENT=10 REQUESTS_PER_LEVEL=5 $0"
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

