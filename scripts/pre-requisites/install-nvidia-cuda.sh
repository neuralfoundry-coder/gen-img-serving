#!/bin/bash
#
# NVIDIA CUDA Environment Setup Script
# Target: Ubuntu 24.04 LTS (Noble Numbat)
# Note: NVIDIA Driver and CUDA are pre-installed
#

set -e

# =============================================================================
# Configuration
# =============================================================================
CUDA_VERSION="${CUDA_VERSION:-12.8}"
UBUNTU_VERSION="ubuntu2404"
ARCH="x86_64"

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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (sudo)."
        exit 1
    fi
}

check_ubuntu_version() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "${VERSION_ID}" != "24.04" && "${VERSION_ID}" != "24.10" ]]; then
            print_warning "This script is designed for Ubuntu 24.xx. Detected: ${VERSION_ID}"
            read -p "Continue anyway? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        print_warning "Cannot detect OS version. Proceeding anyway..."
    fi
}

check_nvidia_gpu() {
    if ! lspci | grep -i nvidia > /dev/null; then
        print_error "No NVIDIA GPU detected. Please check your hardware."
        exit 1
    fi
    print_success "NVIDIA GPU detected."
}

check_nvidia_driver() {
    if ! command -v nvidia-smi &> /dev/null; then
        print_error "NVIDIA driver is not installed. Please install NVIDIA driver first."
        exit 1
    fi
    print_success "NVIDIA driver is installed:"
    nvidia-smi --query-gpu=driver_version,name --format=csv,noheader
}

check_cuda() {
    if [ -d "/usr/local/cuda" ] || command -v nvcc &> /dev/null; then
        print_success "CUDA is installed."
        if command -v nvcc &> /dev/null; then
            nvcc --version | grep "release"
        fi
    else
        print_warning "CUDA not found. Environment may not be configured."
    fi
}

# =============================================================================
# Installation Steps
# =============================================================================
install_prerequisites() {
    print_info "Installing prerequisites..."
    
    apt-get update
    apt-get install -y \
        build-essential \
        dkms \
        linux-headers-$(uname -r) \
        wget \
        gnupg2 \
        software-properties-common \
        ca-certificates \
        curl
    
    print_success "Prerequisites installed."
}

install_cudnn() {
    print_info "Installing cuDNN..."
    
    # Add CUDA repository if not exists
    if [ ! -f /etc/apt/sources.list.d/cuda-ubuntu2404-x86_64.list ]; then
        print_info "Adding NVIDIA CUDA repository for cuDNN..."
        KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/${UBUNTU_VERSION}/${ARCH}/cuda-keyring_1.1-1_all.deb"
        wget -q "${KEYRING_URL}" -O /tmp/cuda-keyring.deb
        dpkg -i /tmp/cuda-keyring.deb
        rm -f /tmp/cuda-keyring.deb
        apt-get update
    fi
    
    # cuDNN 9 for CUDA 12
    apt-get install -y --no-install-recommends \
        libcudnn9-cuda-12 \
        libcudnn9-dev-cuda-12 \
        2>/dev/null || {
            print_warning "cuDNN 9 not available, trying cuDNN 8..."
            apt-get install -y --no-install-recommends \
                libcudnn8 \
                libcudnn8-dev \
                2>/dev/null || print_warning "cuDNN installation skipped."
        }
    
    print_success "cuDNN installed."
}

configure_environment() {
    print_info "Configuring environment variables..."
    
    CUDA_ENV_FILE="/etc/profile.d/cuda.sh"
    
    cat > "${CUDA_ENV_FILE}" << 'EOF'
# CUDA Environment Variables
export PATH=/usr/local/cuda/bin${PATH:+:${PATH}}
export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
export CUDA_HOME=/usr/local/cuda
EOF
    
    chmod +x "${CUDA_ENV_FILE}"
    
    # Also add to bashrc for immediate use
    if ! grep -q "CUDA_HOME" /etc/bash.bashrc; then
        cat >> /etc/bash.bashrc << 'EOF'

# CUDA Environment Variables
export PATH=/usr/local/cuda/bin${PATH:+:${PATH}}
export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
export CUDA_HOME=/usr/local/cuda
EOF
    fi
    
    print_success "Environment configured."
}

verify_installation() {
    print_info "Verifying installation..."
    
    # Source the environment
    export PATH=/usr/local/cuda/bin${PATH:+:${PATH}}
    export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
    
    echo ""
    print_info "NVIDIA Driver:"
    nvidia-smi
    
    echo ""
    if command -v nvcc &> /dev/null; then
        print_success "CUDA compiler (nvcc) is available:"
        nvcc --version
    else
        print_warning "nvcc not found in PATH. Please check CUDA installation."
    fi
    
    echo ""
    print_info "Installed CUDA/NVIDIA packages:"
    dpkg -l | grep -E "cuda|nvidia|cudnn" | head -20
}

# =============================================================================
# Main
# =============================================================================
main() {
    echo "=============================================="
    echo "  NVIDIA CUDA Environment Setup"
    echo "  Target: Ubuntu 24.04 LTS"
    echo "=============================================="
    echo ""
    
    check_root
    check_ubuntu_version
    check_nvidia_gpu
    check_nvidia_driver
    check_cuda
    
    echo ""
    print_info "This script will:"
    print_info "  - Install build prerequisites"
    print_info "  - Install cuDNN 9 for CUDA 12"
    print_info "  - Configure environment variables"
    echo ""
    
    read -p "Proceed with setup? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Setup cancelled."
        exit 0
    fi
    
    echo ""
    install_prerequisites
    install_cudnn
    configure_environment
    verify_installation
    
    echo ""
    echo "=============================================="
    print_success "Setup complete!"
    echo "=============================================="
    print_info "Environment variables have been configured."
    print_info "Run 'source /etc/profile.d/cuda.sh' or re-login to apply."
    echo ""
}

# Run main function
main "$@"
