#!/bin/bash
#
# Z-Image-Turbo Load Test Script
# Tests concurrent requests from 1 to 10
#

set -e

# =============================================================================
# Configuration
# =============================================================================
BASE_URL="${BASE_URL:-http://localhost:8001}"
ENDPOINT="/v1/images/generations"
TIMEOUT="${TIMEOUT:-30}"
MAX_CONCURRENT="${MAX_CONCURRENT:-10}"

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
        print_warning "jq is not installed. Response parsing will be limited."
    fi
}

# Check if server is available
check_server() {
    print_info "Checking server availability at ${BASE_URL}..."
    if curl -s --connect-timeout 5 "${BASE_URL}/health" > /dev/null 2>&1 || \
       curl -s --connect-timeout 5 "${BASE_URL}/v1/models" > /dev/null 2>&1; then
        print_success "Server is available."
        return 0
    else
        print_warning "Server health check failed. Proceeding anyway..."
        return 0
    fi
}

# Single request function
make_request() {
    local request_id=$1
    local start_time=$(date +%s.%N)
    
    local response
    local http_code
    
    # Make request and capture both response and http code
    response=$(curl -s -w "\n%{http_code}" \
        --max-time "${TIMEOUT}" \
        -X POST "${BASE_URL}${ENDPOINT}" \
        -H "Content-Type: application/json" \
        -d "${REQUEST_BODY}" 2>&1)
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    # Extract http code (last line)
    http_code=$(echo "$response" | tail -n1)
    
    # Check result
    if [[ "$http_code" == "200" ]]; then
        echo "REQUEST_${request_id}|SUCCESS|${duration}s|HTTP_${http_code}"
    elif [[ "$http_code" =~ ^[0-9]+$ ]]; then
        echo "REQUEST_${request_id}|FAILED|${duration}s|HTTP_${http_code}"
    else
        echo "REQUEST_${request_id}|TIMEOUT|${TIMEOUT}s|TIMEOUT"
    fi
}

# Run concurrent requests
run_concurrent_test() {
    local concurrent=$1
    local pids=()
    local results=()
    local temp_dir=$(mktemp -d)
    
    print_info "Starting ${concurrent} concurrent request(s)..."
    
    local test_start=$(date +%s.%N)
    
    # Launch concurrent requests
    for i in $(seq 1 $concurrent); do
        make_request $i > "${temp_dir}/result_${i}.txt" &
        pids+=($!)
    done
    
    # Wait for all requests to complete
    for pid in "${pids[@]}"; do
        wait $pid 2>/dev/null || true
    done
    
    local test_end=$(date +%s.%N)
    local total_duration=$(echo "$test_end - $test_start" | bc)
    
    # Collect results
    local success_count=0
    local failed_count=0
    local timeout_count=0
    local total_response_time=0
    
    echo ""
    echo "  Results:"
    for i in $(seq 1 $concurrent); do
        local result=$(cat "${temp_dir}/result_${i}.txt")
        echo "    $result"
        
        if [[ "$result" == *"|SUCCESS|"* ]]; then
            ((success_count++))
            local response_time=$(echo "$result" | cut -d'|' -f3 | sed 's/s//')
            total_response_time=$(echo "$total_response_time + $response_time" | bc)
        elif [[ "$result" == *"|TIMEOUT|"* ]]; then
            ((timeout_count++))
        else
            ((failed_count++))
        fi
    done
    
    # Calculate average response time
    local avg_response_time=0
    if [ $success_count -gt 0 ]; then
        avg_response_time=$(echo "scale=3; $total_response_time / $success_count" | bc)
    fi
    
    echo ""
    echo "  Summary:"
    echo "    - Concurrent: ${concurrent}"
    echo "    - Success: ${success_count}/${concurrent}"
    echo "    - Failed: ${failed_count}"
    echo "    - Timeout: ${timeout_count}"
    echo "    - Total Duration: ${total_duration}s"
    if [ $success_count -gt 0 ]; then
        echo "    - Avg Response Time: ${avg_response_time}s"
    fi
    echo ""
    
    # Cleanup
    rm -rf "${temp_dir}"
    
    # Return results for summary
    echo "${concurrent}|${success_count}|${failed_count}|${timeout_count}|${total_duration}|${avg_response_time}" >> /tmp/load_test_summary.txt
}

# Print final summary
print_summary() {
    echo ""
    echo "=============================================="
    echo "  LOAD TEST SUMMARY"
    echo "=============================================="
    echo ""
    printf "%-12s %-10s %-10s %-10s %-15s %-15s\n" "Concurrent" "Success" "Failed" "Timeout" "Total(s)" "Avg(s)"
    printf "%-12s %-10s %-10s %-10s %-15s %-15s\n" "----------" "-------" "------" "-------" "--------" "------"
    
    while IFS='|' read -r concurrent success failed timeout total avg; do
        printf "%-12s %-10s %-10s %-10s %-15s %-15s\n" "$concurrent" "$success" "$failed" "$timeout" "$total" "$avg"
    done < /tmp/load_test_summary.txt
    
    echo ""
    rm -f /tmp/load_test_summary.txt
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
    echo ""
    
    check_dependencies
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
    echo "  MAX_CONCURRENT Maximum concurrent requests (default: 10)"
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

