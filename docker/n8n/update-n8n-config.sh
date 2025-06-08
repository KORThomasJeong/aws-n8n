#!/bin/bash

# n8n 설정 변경 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}n8n 설정 변경 스크립트${NC}"
echo "현재 설정을 불러오는 중..."

# .env 파일 경로
ENV_FILE=".env"

# .env 파일이 존재하는지 확인
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}경고: .env 파일을 찾을 수 없습니다.${NC}"
    exit 1
fi

# 현재 설정 불러오기
source "$ENV_FILE"

# 메뉴 표시
echo "변경할 설정을 선택하세요:"
echo "1) 웹훅 URL 변경"
echo "2) 이메일 설정 변경"
echo "3) 데이터베이스 비밀번호 변경"
echo "4) 종료"

read -p "선택 (1-4): " choice

case $choice in
    1)
        read -p "새 웹훅 URL을 입력하세요 (예: https://n8n.example.com): " new_webhook
        # URL에서 도메인 추출
        new_domain=$(echo $new_webhook | sed -E 's|https?://||' | sed -E 's|:[0-9]+$||')
        
        # .env 파일 업데이트
        sed -i "s|N8N_HOST=.*|N8N_HOST=$new_domain|" $ENV_FILE
        sed -i "s|N8N_WEBHOOK_URL=.*|N8N_WEBHOOK_URL=$new_webhook|" $ENV_FILE
        sed -i "s|WEBHOOK_URL=.*|WEBHOOK_URL=$new_webhook|" $ENV_FILE
        
        echo -e "${GREEN}웹훅 URL이 업데이트되었습니다.${NC}"
        ;;
    2)
        read -p "SMTP 호스트 (예: smtp.gmail.com): " smtp_host
        read -p "SMTP 포트 (예: 587): " smtp_port
        read -p "SMTP 사용자 이메일: " smtp_user
        read -sp "SMTP 비밀번호: " smtp_pass
        echo
        read -p "발신자 이메일: " smtp_sender
        
        # .env 파일 업데이트
        sed -i "s|N8N_SMTP_HOST=.*|N8N_SMTP_HOST=$smtp_host|" $ENV_FILE
        sed -i "s|N8N_SMTP_PORT=.*|N8N_SMTP_PORT=$smtp_port|" $ENV_FILE
        sed -i "s|N8N_SMTP_USER=.*|N8N_SMTP_USER=$smtp_user|" $ENV_FILE
        sed -i "s|N8N_SMTP_PASS=.*|N8N_SMTP_PASS=$smtp_pass|" $ENV_FILE
        sed -i "s|N8N_SMTP_SENDER=.*|N8N_SMTP_SENDER=$smtp_sender|" $ENV_FILE
        
        echo -e "${GREEN}이메일 설정이 업데이트되었습니다.${NC}"
        ;;
    3)
        # 새 비밀번호 생성
        new_password=$(openssl rand -base64 32)
        
        # .env 파일 업데이트
        sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$new_password|" $ENV_FILE
        
        echo -e "${GREEN}데이터베이스 비밀번호가 업데이트되었습니다.${NC}"
        echo "새 비밀번호: $new_password"
        echo "이 비밀번호를 안전한 곳에 보관하세요."
        ;;
    4)
        echo "종료합니다."
        exit 0
        ;;
    *)
        echo -e "${YELLOW}잘못된 선택입니다. 다시 시도하세요.${NC}"
        exit 1
        ;;
esac

echo "변경 사항을 적용하려면 n8n 서비스를 재시작하세요:"
echo "cd /home/$USER/docker/n8n && docker-compose down && docker-compose up -d"
