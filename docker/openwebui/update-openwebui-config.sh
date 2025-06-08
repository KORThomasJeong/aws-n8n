#!/bin/bash

# OpenWebUI 설정 변경 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}OpenWebUI 설정 변경 스크립트${NC}"

# docker-compose.yml 파일 경로
COMPOSE_FILE="docker-compose.yml"

# docker-compose.yml 파일이 존재하는지 확인
if [ ! -f "$COMPOSE_FILE" ]; then
    echo -e "${YELLOW}경고: docker-compose.yml 파일을 찾을 수 없습니다.${NC}"
    exit 1
fi

# 메뉴 표시
echo "변경할 설정을 선택하세요:"
echo "1) 데이터베이스 비밀번호 변경"
echo "2) 포트 변경"
echo "3) 종료"

read -p "선택 (1-3): " choice

case $choice in
    1)
        # 새 비밀번호 생성
        new_password=$(openssl rand -base64 12)
        
        # 현재 비밀번호 추출
        current_password=$(grep -oP "POSTGRES_PASSWORD=\K[^'\"]*" $COMPOSE_FILE | head -1)
        
        # docker-compose.yml 파일 업데이트
        sed -i "s|POSTGRES_PASSWORD=$current_password|POSTGRES_PASSWORD=$new_password|g" $COMPOSE_FILE
        sed -i "s|postgresql://webui:$current_password@|postgresql://webui:$new_password@|g" $COMPOSE_FILE
        
        echo -e "${GREEN}데이터베이스 비밀번호가 업데이트되었습니다.${NC}"
        echo "새 비밀번호: $new_password"
        echo "이 비밀번호를 안전한 곳에 보관하세요."
        ;;
    2)
        read -p "새 포트 번호를 입력하세요 (현재: 2000): " new_port
        
        # docker-compose.yml 파일 업데이트
        sed -i "s|\"2000:8080\"|\"$new_port:8080\"|g" $COMPOSE_FILE
        
        echo -e "${GREEN}포트가 $new_port로 업데이트되었습니다.${NC}"
        ;;
    3)
        echo "종료합니다."
        exit 0
        ;;
    *)
        echo -e "${YELLOW}잘못된 선택입니다. 다시 시도하세요.${NC}"
        exit 1
        ;;
esac

echo "변경 사항을 적용하려면 OpenWebUI 서비스를 재시작하세요:"
echo "cd /home/$USER/docker/openwebui && docker-compose down && docker-compose up -d"
