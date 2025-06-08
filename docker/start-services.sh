#!/bin/bash

# 서비스 시작 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}서비스 시작 스크립트${NC}"

# Nginx Proxy Manager 시작
echo "Nginx Proxy Manager 시작 중..."
cd /home/$USER/docker/npm && docker-compose up -d
sleep 5

# n8n 시작
echo "n8n 시작 중..."
cd /home/$USER/docker/n8n && docker-compose up -d
sleep 5

# OpenWebUI 시작
echo "OpenWebUI 시작 중..."
cd /home/$USER/docker/openwebui && docker-compose up -d

echo -e "${GREEN}모든 서비스가 시작되었습니다.${NC}"
echo "Nginx Proxy Manager: http://your-server-ip:81"
echo "n8n: https://$(grep N8N_HOST /home/$USER/docker/n8n/.env | cut -d= -f2)"
echo "OpenWebUI: http://your-server-ip:2000"
