#!/bin/bash
#
# Docker & NVIDIA Container Toolkit Installation Script
# Target: Ubuntu 24.04 LTS
#

set -e

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

# =============================================================================
# Installation Steps
# =============================================================================
install_docker() {
    print_info "Installing Docker..."
    
    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Install prerequisites
    apt-get update
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Set up the repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Enable and start Docker
    systemctl enable docker
    systemctl start docker
    
    print_success "Docker installed."
}

configure_docker_user() {
    print_info "Configuring Docker for non-root user..."
    
    # Add current user to docker group
    if [ -n "${SUDO_USER}" ]; then
        usermod -aG docker "${SUDO_USER}"
        print_success "User ${SUDO_USER} added to docker group."
        print_warning "Please log out and log back in for group changes to take effect."
    fi
}

install_nvidia_container_toolkit() {
    print_info "Installing NVIDIA Container Toolkit..."
    
    # Add NVIDIA Container Toolkit repository
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    apt-get update
    apt-get install -y nvidia-container-toolkit
    
    print_success "NVIDIA Container Toolkit installed."
}

configure_nvidia_docker() {
    print_info "Configuring Docker for NVIDIA runtime..."
    
    # Configure Docker daemon
    nvidia-ctk runtime configure --runtime=docker
    
    # Restart Docker to apply changes
    systemctl restart docker
    
    print_success "Docker configured for NVIDIA runtime."
}

verify_installation() {
    print_info "Verifying installation..."
    
    echo ""
    print_info "Docker version:"
    docker --version
    
    echo ""
    print_info "Docker Compose version:"
    docker compose version
    
    echo ""
    print_info "Checking NVIDIA Docker runtime..."
    if docker info 2>/dev/null | grep -q "nvidia"; then
        print_success "NVIDIA runtime is available."
    else
        print_warning "NVIDIA runtime may not be fully configured. Try rebooting."
    fi
    
    echo ""
    print_info "Testing NVIDIA Docker..."
    if docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu24.04 nvidia-smi 2>/dev/null; then
        print_success "NVIDIA Docker is working correctly!"
    else
        print_warning "NVIDIA Docker test failed. Please check your GPU driver installation."
    fi
}

# =============================================================================
# Main
# =============================================================================
main() {
    echo "=============================================="
    echo "  Docker & NVIDIA Container Toolkit Setup"
    echo "  Target: Ubuntu 24.04 LTS"
    echo "=============================================="
    echo ""
    
    check_root
    
    print_info "This script will install:"
    print_info "  - Docker Engine (latest)"
    print_info "  - Docker Compose Plugin"
    print_info "  - NVIDIA Container Toolkit"
    echo ""
    
    read -p "Proceed with installation? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled."
        exit 0
    fi
    
    echo ""
    install_docker
    configure_docker_user
    install_nvidia_container_toolkit
    configure_nvidia_docker
    verify_installation
    
    echo ""
    echo "=============================================="
    print_success "Installation complete!"
    echo "=============================================="
    print_info "You can now use 'docker run --gpus all ...' to access GPU in containers."
    echo ""
}

# Run main function
main "$@"

