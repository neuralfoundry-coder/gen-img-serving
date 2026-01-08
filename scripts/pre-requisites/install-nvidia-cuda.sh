#!/bin/bash
#
# NVIDIA CUDA Toolkit Installation Script
# Target: Ubuntu 24.04 LTS (Noble Numbat)
# CUDA Version: 12.8
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

remove_old_nvidia() {
    print_info "Removing old NVIDIA drivers if present..."
    
    # Remove old NVIDIA packages
    apt-get remove --purge -y 'nvidia-*' 'libnvidia-*' 'cuda-*' 'libcuda*' 2>/dev/null || true
    apt-get autoremove -y
    
    print_success "Old NVIDIA packages removed."
}

add_cuda_repo() {
    print_info "Adding NVIDIA CUDA repository..."
    
    # Download and install CUDA keyring
    KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/${UBUNTU_VERSION}/${ARCH}/cuda-keyring_1.1-1_all.deb"
    
    wget -q "${KEYRING_URL}" -O /tmp/cuda-keyring.deb
    dpkg -i /tmp/cuda-keyring.deb
    rm -f /tmp/cuda-keyring.deb
    
    apt-get update
    
    print_success "CUDA repository added."
}

install_cuda() {
    print_info "Installing CUDA ${CUDA_VERSION}..."
    
    # Install CUDA toolkit
    # cuda-12-8 패키지는 드라이버와 툴킷을 모두 포함
    apt-get install -y cuda-toolkit-12-8
    
    # Install NVIDIA driver (latest compatible version)
    apt-get install -y nvidia-driver-565
    
    print_success "CUDA ${CUDA_VERSION} installed."
}

install_cudnn() {
    print_info "Installing cuDNN..."
    
    apt-get install -y libcudnn9-cuda-12 libcudnn9-dev-cuda-12
    
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
    
    if command -v nvcc &> /dev/null; then
        print_success "CUDA compiler (nvcc) is available:"
        nvcc --version
    else
        print_warning "nvcc not found in PATH. Please reboot and try again."
    fi
    
    echo ""
    print_info "Installed CUDA packages:"
    dpkg -l | grep -E "cuda|nvidia" | head -20
}

# =============================================================================
# Main
# =============================================================================
main() {
    echo "=============================================="
    echo "  NVIDIA CUDA ${CUDA_VERSION} Installation"
    echo "  Target: Ubuntu 24.04 LTS"
    echo "=============================================="
    echo ""
    
    check_root
    check_ubuntu_version
    check_nvidia_gpu
    
    echo ""
    print_info "This script will install:"
    print_info "  - NVIDIA Driver 565 (CUDA 12.8 compatible)"
    print_info "  - CUDA Toolkit 12.8"
    print_info "  - cuDNN 9 for CUDA 12"
    echo ""
    
    read -p "Proceed with installation? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled."
        exit 0
    fi
    
    echo ""
    install_prerequisites
    remove_old_nvidia
    add_cuda_repo
    install_cuda
    install_cudnn
    configure_environment
    verify_installation
    
    echo ""
    echo "=============================================="
    print_success "Installation complete!"
    echo "=============================================="
    print_warning "Please REBOOT your system to load the NVIDIA driver."
    print_info "After reboot, verify with: nvidia-smi"
    echo ""
}

# Run main function
main "$@"

