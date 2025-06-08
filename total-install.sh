#!/bin/bash

# AWS Lightsail에 n8n, Nginx Proxy Manager, OpenWebUI 설치 스크립트
# 작성자: ThomasJeong
# 날짜: 2025-06-08

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 관리자 권한 확인
if [ "$EUID" -ne 0 ]; then
    error "이 스크립트는 관리자 권한으로 실행해야 합니다. 'sudo bash total-install.sh' 명령어를 사용하세요."
fi

# 시스템 업데이트 및 기본 패키지 설치
log "시스템 업데이트 및 기본 패키지 설치 중..."
apt update && apt upgrade -y
apt install -y curl wget git nano unzip apt-transport-https ca-certificates gnupg lsb-release

# 관리자 패스워드 설정
setup_admin_password() {
    log "관리자 패스워드 설정..."
    read -sp "새 관리자 패스워드를 입력하세요: " ADMIN_PASSWORD
    echo
    read -sp "패스워드를 다시 입력하세요: " ADMIN_PASSWORD_CONFIRM
    echo
    
    if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]; then
        error "패스워드가 일치하지 않습니다. 다시 시도하세요."
    fi
    
    echo "root:$ADMIN_PASSWORD" | chpasswd
    log "관리자 패스워드가 성공적으로 설정되었습니다."
}

# 캐시 메모리 설정 (4GB)
setup_swap() {
    log "4GB 스왑 메모리 설정 중..."
    
    # 기존 스왑 파일 확인 및 제거
    if [ -f /swapfile ]; then
        swapoff /swapfile
        rm /swapfile
    fi
    
    # 4GB 스왑 파일 생성
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    # 부팅 시 자동 마운트 설정
    if ! grep -q "/swapfile" /etc/fstab; then
        echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
    fi
    
    # 스왑 설정 최적화
    echo "vm.swappiness=10" >> /etc/sysctl.conf
    echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
    sysctl -p
    
    log "스왑 메모리 설정 완료: $(free -h | grep Swap)"
}

# Docker 설치
install_docker() {
    log "Docker 설치 중..."
    
    # 기존 Docker 제거
    apt remove -y docker docker-engine docker.io containerd runc || true
    
    # Docker 저장소 설정
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Docker 설치
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io
    
    # Docker Compose 설치
    log "Docker Compose 설치 중..."
    curl -L "https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Docker 서비스 시작 및 자동 시작 설정
    systemctl start docker
    systemctl enable docker
    
    # 현재 사용자를 docker 그룹에 추가
    usermod -aG docker $SUDO_USER
    
    log "Docker 설치 완료: $(docker --version)"
    log "Docker Compose 설치 완료: $(docker-compose --version)"
}

# 기본 디렉토리 구조 생성
create_directory_structure() {
    log "디렉토리 구조 생성 중..."
    
    # 기본 디렉토리 생성
    mkdir -p /home/$SUDO_USER/docker/{n8n,npm,openwebui}
    
    # n8n 데이터 디렉토리
    mkdir -p /home/$SUDO_USER/docker/n8n/data
    mkdir -p /home/$SUDO_USER/docker/n8n/n8n_data
    
    # npm 데이터 디렉토리
    mkdir -p /home/$SUDO_USER/docker/npm/data
    mkdir -p /home/$SUDO_USER/docker/npm/letsencrypt
    mkdir -p /home/$SUDO_USER/docker/npm/mysql
    
    # openwebui 데이터 디렉토리
    mkdir -p /home/$SUDO_USER/docker/openwebui/data
    mkdir -p /home/$SUDO_USER/docker/openwebui/postgres
    
    # 권한 설정
    chown -R $SUDO_USER:$SUDO_USER /home/$SUDO_USER/docker
    
    log "디렉토리 구조 생성 완료"
}

# 환경 변수 설정
setup_environment() {
    log "환경 변수 설정 중..."
    
    # 도메인 설정
    read -p "n8n 웹훅 URL을 입력하세요 (예: https://n8n.example.com): " N8N_WEBHOOK_URL
    
    # URL에서 도메인 추출
    N8N_DOMAIN=$(echo $N8N_WEBHOOK_URL | sed -E 's|https?://||' | sed -E 's|:[0-9]+$||')
    
    # 암호화 키 생성
    N8N_ENCRYPTION_KEY=$(openssl rand -base64 32)
    
    # PostgreSQL 비밀번호 생성
    POSTGRES_PASSWORD=$(openssl rand -base64 32)
    
    # n8n .env 파일 생성
    cat > /home/$SUDO_USER/docker/n8n/.env << EOF
# n8n 기본 설정
N8N_HOST=$N8N_DOMAIN
N8N_PORT=5678
N8N_PROTOCOL=https

# 보안을 위한 암호화 키
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY

# Webhook URL 설정
N8N_WEBHOOK_URL=$N8N_WEBHOOK_URL
WEBHOOK_URL=$N8N_WEBHOOK_URL

# PostgreSQL 데이터베이스 설정
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# 이메일 설정 (선택사항)
N8N_EMAIL_MODE=smtp
N8N_SMTP_HOST=
N8N_SMTP_PORT=587
N8N_SMTP_USER=
N8N_SMTP_PASS=
N8N_SMTP_SENDER=

# 프록시 및 보안 설정
N8N_TRUSTED_PROXIES=*
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
N8N_RUNNERS_ENABLED=true
EOF
    
    # OpenWebUI 환경 변수
    OPENWEBUI_DB_PASSWORD=$(openssl rand -base64 12)
    
    log "환경 변수 설정 완료"
}

# n8n Docker Compose 파일 생성
create_n8n_compose() {
    log "n8n Docker Compose 파일 생성 중..."
    
    cat > /home/$SUDO_USER/docker/n8n/docker-compose.yml << EOF
services:
  n8n:
    image: n8nio/n8n:latest
    restart: always
    container_name: n8n
    ports:
      - "\${N8N_PORT}:5678"
    environment:
      - N8N_HOST=\${N8N_HOST}
      - N8N_PORT=\${N8N_PORT}
      - N8N_PROTOCOL=\${N8N_PROTOCOL}
      - NODE_ENV=production
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      - N8N_WEBHOOK_URL=\${N8N_WEBHOOK_URL}
      - WEBHOOK_URL=\${WEBHOOK_URL}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=\${POSTGRES_DB}
      - DB_POSTGRESDB_USER=\${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD}
      - N8N_EMAIL_MODE=\${N8N_EMAIL_MODE}
      - N8N_SMTP_HOST=\${N8N_SMTP_HOST}
      - N8N_SMTP_PORT=\${N8N_SMTP_PORT}
      - N8N_SMTP_USER=\${N8N_SMTP_USER}
      - N8N_SMTP_PASS=\${N8N_SMTP_PASS}
      - N8N_SMTP_SENDER=\${N8N_SMTP_SENDER}
      - N8N_TRUSTED_PROXIES=*
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=true
      - GENERIC_TIMEZONE=Asia/Seoul
      - PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
      - PPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
    volumes:
      - ./n8n_data:/home/node/.n8n
    depends_on:
      - postgres
    networks:
      - n8n-network

  postgres:
    container_name: n8n-db
    image: postgres:14-alpine
    restart: always
    environment:
      - POSTGRES_DB=\${POSTGRES_DB}
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - n8n-network
    ports:
      - "5432:5432"
  
volumes:
  n8n_data:
  postgres_data:

networks:
  n8n-network:
    driver: bridge
EOF
    
    log "n8n Docker Compose 파일 생성 완료"
}

# Nginx Proxy Manager Docker Compose 파일 생성
create_npm_compose() {
    log "Nginx Proxy Manager Docker Compose 파일 생성 중..."
    
    cat > /home/$SUDO_USER/docker/npm/docker-compose.yml << EOF
services:
  npm:
    container_name: npm
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'
      - '443:443'
      - '81:81'
    environment:
      DB_MYSQL_HOST: "db"
      DB_MYSQL_PORT: 3306
      DB_MYSQL_USER: "npm"
      DB_MYSQL_PASSWORD: "npm"
      DB_MYSQL_NAME: "npm"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    depends_on:
      - db
  db:
    container_name: npm-db
    image: 'yobasystems/alpine-mariadb:latest'
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: 'npm'
      MYSQL_DATABASE: 'npm'
      MYSQL_USER: 'npm'
      MYSQL_PASSWORD: 'npm'
      TZ: Asia/Seoul
    volumes:
      - ./mysql:/var/lib/mysql
networks:
  default:
    name: npm
EOF
    
    log "Nginx Proxy Manager Docker Compose 파일 생성 완료"
}

# OpenWebUI Docker Compose 파일 생성
create_openwebui_compose() {
    log "OpenWebUI Docker Compose 파일 생성 중..."
    
    cat > /home/$SUDO_USER/docker/openwebui/docker-compose.yml << EOF
services:
  webui-db:
    container_name: open-webui-db
    image: postgres:13
    environment:
      - POSTGRES_DB=webui
      - POSTGRES_USER=webui
      - POSTGRES_PASSWORD=$OPENWEBUI_DB_PASSWORD
    ports:
      - "5433:5432"
    volumes:
      - ./postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U webui -d webui -p 5432"]
      interval: 3s
      timeout: 5s
      retries: 5
    restart: always

  open-webui:
    container_name: open-webui
    image: ghcr.io/open-webui/open-webui:main
    depends_on:
      webui-db:
        condition: service_healthy
    ports:
      - "2000:8080"
    environment:
      - 'DATABASE_URL=postgresql://webui:$OPENWEBUI_DB_PASSWORD@webui-db:5432/webui'
    volumes:
      - ./data:/app/backend/data
    restart: unless-stopped

networks:
  default:
    driver: bridge
EOF
    
    log "OpenWebUI Docker Compose 파일 생성 완료"
}

# 설정 변경 스크립트 생성
create_config_scripts() {
    log "설정 변경 스크립트 생성 중..."
    
    # n8n 설정 변경 스크립트
    cat > /home/$SUDO_USER/docker/n8n/update-n8n-config.sh << EOF
#!/bin/bash

# n8n 설정 변경 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "\${GREEN}n8n 설정 변경 스크립트\${NC}"
echo "현재 설정을 불러오는 중..."

# .env 파일 경로
ENV_FILE=".env"

# .env 파일이 존재하는지 확인
if [ ! -f "\$ENV_FILE" ]; then
    echo -e "\${YELLOW}경고: .env 파일을 찾을 수 없습니다.\${NC}"
    exit 1
fi

# 현재 설정 불러오기
source "\$ENV_FILE"

# 메뉴 표시
echo "변경할 설정을 선택하세요:"
echo "1) 웹훅 URL 변경"
echo "2) 이메일 설정 변경"
echo "3) 데이터베이스 비밀번호 변경"
echo "4) 종료"

read -p "선택 (1-4): " choice

case \$choice in
    1)
        read -p "새 웹훅 URL을 입력하세요 (예: https://n8n.example.com): " new_webhook
        # URL에서 도메인 추출
        new_domain=\$(echo \$new_webhook | sed -E 's|https?://||' | sed -E 's|:[0-9]+$||')
        
        # .env 파일 업데이트
        sed -i "s|N8N_HOST=.*|N8N_HOST=\$new_domain|" \$ENV_FILE
        sed -i "s|N8N_WEBHOOK_URL=.*|N8N_WEBHOOK_URL=\$new_webhook|" \$ENV_FILE
        sed -i "s|WEBHOOK_URL=.*|WEBHOOK_URL=\$new_webhook|" \$ENV_FILE
        
        echo -e "\${GREEN}웹훅 URL이 업데이트되었습니다.\${NC}"
        ;;
    2)
        read -p "SMTP 호스트 (예: smtp.gmail.com): " smtp_host
        read -p "SMTP 포트 (예: 587): " smtp_port
        read -p "SMTP 사용자 이메일: " smtp_user
        read -sp "SMTP 비밀번호: " smtp_pass
        echo
        read -p "발신자 이메일: " smtp_sender
        
        # .env 파일 업데이트
        sed -i "s|N8N_SMTP_HOST=.*|N8N_SMTP_HOST=\$smtp_host|" \$ENV_FILE
        sed -i "s|N8N_SMTP_PORT=.*|N8N_SMTP_PORT=\$smtp_port|" \$ENV_FILE
        sed -i "s|N8N_SMTP_USER=.*|N8N_SMTP_USER=\$smtp_user|" \$ENV_FILE
        sed -i "s|N8N_SMTP_PASS=.*|N8N_SMTP_PASS=\$smtp_pass|" \$ENV_FILE
        sed -i "s|N8N_SMTP_SENDER=.*|N8N_SMTP_SENDER=\$smtp_sender|" \$ENV_FILE
        
        echo -e "\${GREEN}이메일 설정이 업데이트되었습니다.\${NC}"
        ;;
    3)
        # 새 비밀번호 생성
        new_password=\$(openssl rand -base64 32)
        
        # .env 파일 업데이트
        sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=\$new_password|" \$ENV_FILE
        
        echo -e "\${GREEN}데이터베이스 비밀번호가 업데이트되었습니다.\${NC}"
        echo "새 비밀번호: \$new_password"
        echo "이 비밀번호를 안전한 곳에 보관하세요."
        ;;
    4)
        echo "종료합니다."
        exit 0
        ;;
    *)
        echo -e "\${YELLOW}잘못된 선택입니다. 다시 시도하세요.\${NC}"
        exit 1
        ;;
esac

echo "변경 사항을 적용하려면 n8n 서비스를 재시작하세요:"
echo "cd /home/\$USER/docker/n8n && docker-compose down && docker-compose up -d"
EOF
    
    # OpenWebUI 설정 변경 스크립트
    cat > /home/$SUDO_USER/docker/openwebui/update-openwebui-config.sh << EOF
#!/bin/bash

# OpenWebUI 설정 변경 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "\${GREEN}OpenWebUI 설정 변경 스크립트\${NC}"

# docker-compose.yml 파일 경로
COMPOSE_FILE="docker-compose.yml"

# docker-compose.yml 파일이 존재하는지 확인
if [ ! -f "\$COMPOSE_FILE" ]; then
    echo -e "\${YELLOW}경고: docker-compose.yml 파일을 찾을 수 없습니다.\${NC}"
    exit 1
fi

# 메뉴 표시
echo "변경할 설정을 선택하세요:"
echo "1) 데이터베이스 비밀번호 변경"
echo "2) 포트 변경"
echo "3) 종료"

read -p "선택 (1-3): " choice

case \$choice in
    1)
        # 새 비밀번호 생성
        new_password=\$(openssl rand -base64 12)
        
        # 현재 비밀번호 추출
        current_password=\$(grep -oP "POSTGRES_PASSWORD=\K[^'\"]*" \$COMPOSE_FILE | head -1)
        
        # docker-compose.yml 파일 업데이트
        sed -i "s|POSTGRES_PASSWORD=\$current_password|POSTGRES_PASSWORD=\$new_password|g" \$COMPOSE_FILE
        sed -i "s|postgresql://webui:\$current_password@|postgresql://webui:\$new_password@|g" \$COMPOSE_FILE
        
        echo -e "\${GREEN}데이터베이스 비밀번호가 업데이트되었습니다.\${NC}"
        echo "새 비밀번호: \$new_password"
        echo "이 비밀번호를 안전한 곳에 보관하세요."
        ;;
    2)
        read -p "새 포트 번호를 입력하세요 (현재: 2000): " new_port
        
        # docker-compose.yml 파일 업데이트
        sed -i "s|\"2000:8080\"|\"$new_port:8080\"|g" \$COMPOSE_FILE
        
        echo -e "\${GREEN}포트가 \$new_port로 업데이트되었습니다.\${NC}"
        ;;
    3)
        echo "종료합니다."
        exit 0
        ;;
    *)
        echo -e "\${YELLOW}잘못된 선택입니다. 다시 시도하세요.\${NC}"
        exit 1
        ;;
esac

echo "변경 사항을 적용하려면 OpenWebUI 서비스를 재시작하세요:"
echo "cd /home/\$USER/docker/openwebui && docker-compose down && docker-compose up -d"
EOF
    
    # 스크립트 실행 권한 부여
    chmod +x /home/$SUDO_USER/docker/n8n/update-n8n-config.sh
    chmod +x /home/$SUDO_USER/docker/openwebui/update-openwebui-config.sh
    
    log "설정 변경 스크립트 생성 완료"
}

# 서비스 시작 스크립트 생성
create_start_script() {
    log "서비스 시작 스크립트 생성 중..."
    
    cat > /home/$SUDO_USER/docker/start-services.sh << EOF
#!/bin/bash

# 서비스 시작 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "\${GREEN}서비스 시작 스크립트\${NC}"

# Nginx Proxy Manager 시작
echo "Nginx Proxy Manager 시작 중..."
cd /home/\$USER/docker/npm && docker-compose up -d
sleep 5

# n8n 시작
echo "n8n 시작 중..."
cd /home/\$USER/docker/n8n && docker-compose up -d
sleep 5

# OpenWebUI 시작
echo "OpenWebUI 시작 중..."
cd /home/\$USER/docker/openwebui && docker-compose up -d

echo -e "\${GREEN}모든 서비스가 시작되었습니다.\${NC}"
echo "Nginx Proxy Manager: http://your-server-ip:81"
echo "n8n: https://\$(grep N8N_HOST /home/\$USER/docker/n8n/.env | cut -d= -f2)"
echo "OpenWebUI: http://your-server-ip:2000"
EOF
    
    # 스크립트 실행 권한 부여
    chmod +x /home/$SUDO_USER/docker/start-services.sh
    
    log "서비스 시작 스크립트 생성 완료"
}

# README.md 파일 생성
create_readme() {
    log "README.md 파일 생성 중..."
    
    cat > /home/$SUDO_USER/aws-n8n/README.md << EOF
# AWS Lightsail n8n, Nginx Proxy Manager, OpenWebUI 설치 가이드

이 저장소는 AWS Lightsail 인스턴스에 n8n, Nginx Proxy Manager, OpenWebUI를 한 번에 설치하기 위한 스크립트를 제공합니다.

## 시스템 요구사항

- AWS Lightsail 인스턴스 (최소 2GB RAM, 2 vCPU 권장)
- Ubuntu 20.04 LTS 이상
- 관리자(sudo) 권한

## 설치 방법

1. AWS Lightsail 인스턴스에 SSH로 접속합니다.

2. 다음 명령어로 설치 스크립트를 다운로드합니다:

\`\`\`bash
wget https://raw.githubusercontent.com/your-username/aws-n8n/main/total-install.sh
chmod +x total-install.sh
\`\`\`

3. 스크립트를 실행합니다:

\`\`\`bash
sudo bash total-install.sh
\`\`\`

4. 설치 과정에서 다음 정보를 입력해야 합니다:
   - 관리자 패스워드
   - n8n 웹훅 URL (예: https://n8n.example.com)

5. 설치가 완료되면 다음 URL로 각 서비스에 접근할 수 있습니다:
   - Nginx Proxy Manager: http://your-server-ip:81
   - n8n: https://your-n8n-domain
   - OpenWebUI: http://your-server-ip:2000

## 디렉토리 구조

설치 후 다음과 같은 디렉토리 구조가 생성됩니다:

\`\`\`
~/docker/
├── n8n/
│   ├── docker-compose.yml
│   ├── .env
│   ├── data/
│   ├── n8n_data/
│   └── update-n8n-config.sh
├── npm/
│   ├── docker-compose.yml
│   ├── data/
│   ├── letsencrypt/
│   └── mysql/
├── openwebui/
│   ├── docker-compose.yml
│   ├── data/
│   ├── postgres/
│   └── update-openwebui-config.sh
└── start-services.sh
\`\`\`

## 설정 변경

각 서비스의 설정을 변경하려면 다음 스크립트를 사용할 수 있습니다:

- n8n 설정 변경: \`~/docker/n8n/update-n8n-config.sh\`
- OpenWebUI 설정 변경: \`~/docker/openwebui/update-openwebui-config.sh\`

## 서비스 시작/중지

모든 서비스를 한 번에 시작하려면:

\`\`\`bash
~/docker/start-services.sh
\`\`\`

개별 서비스를 시작/중지하려면:

\`\`\`bash
# n8n 시작
cd ~/docker/n8n && docker-compose up -d

# n8n 중지
cd ~/docker/n8n && docker-compose down

# Nginx Proxy Manager 시작
cd ~/docker/npm && docker-compose up -d

# Nginx Proxy Manager 중지
cd ~/docker/npm && docker-compose down

# OpenWebUI 시작
cd ~/docker/openwebui && docker-compose up -d

# OpenWebUI 중지
cd ~/docker/openwebui && docker-compose down
\`\`\`

## Nginx Proxy Manager 초기 설정

Nginx Proxy Manager에 처음 로그인할 때 다음 기본 자격 증명을 사용하세요:

- 이메일: admin@example.com
- 비밀번호: changeme

로그인 후 반드시 이메일과 비밀번호를 변경하세요.

## 문제 해결

문제가 발생하면 다음 로그를 확인하세요:

\`\`\`bash
# n8n 로그 확인
cd ~/docker/n8n && docker-compose logs -f

# Nginx Proxy Manager 로그 확인
cd ~/docker/npm && docker-compose logs -f

# OpenWebUI 로그 확인
cd ~/docker/openwebui && docker-compose logs -f
\`\`\`

## 라이센스

MIT
EOF
    
    log "README.md 파일 생성 완료"
}

# GitHub 설정 안내
github_setup_guide() {
    log "GitHub 설정 안내..."
    
    cat > /home/$SUDO_USER/aws-n8n/github-setup.md << EOF
# GitHub 저장소 설정 가이드

이 가이드는 AWS Lightsail n8n 설치 스크립트를 GitHub에 업로드하는 방법을 설명
