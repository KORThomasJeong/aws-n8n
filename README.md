# AWS Lightsail n8n, Nginx Proxy Manager, OpenWebUI 설치 가이드

이 저장소는 AWS Lightsail 인스턴스에 n8n, Nginx Proxy Manager, OpenWebUI를 한 번에 설치하기 위한 스크립트를 제공합니다.

## 시스템 요구사항

- AWS Lightsail 인스턴스 (최소 1GB RAM, 2 vCPU 권장)
- Ubuntu 20.04 LTS 이상
- 관리자(sudo) 권한

## 설치 방법

1. AWS Lightsail 인스턴스에 SSH로 접속합니다.

2. 다음 명령어로 설치 스크립트를 다운로드합니다:

```bash
wget https://raw.githubusercontent.com/KORThomasJeong/aws-n8n/refs/heads/master/total-install.sh
chmod +x total-install.sh
```

3. 스크립트를 실행합니다:

```bash
sudo bash total-install.sh
```

4. 설치 과정에서 다음 정보를 입력해야 합니다:
   - 관리자 패스워드
   - n8n 웹훅 URL (예: https://n8n.example.com)

5. 설치가 완료되면 다음 URL로 각 서비스에 접근할 수 있습니다:
   - Nginx Proxy Manager: http://your-server-ip:81
   - n8n: https://your-n8n-domain
   - OpenWebUI: http://your-server-ip:2000

## 디렉토리 구조

설치 후 다음과 같은 디렉토리 구조가 생성됩니다:

```
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
```

## 설정 변경

각 서비스의 설정을 변경하려면 다음 스크립트를 사용할 수 있습니다:

- n8n 설정 변경: `~/docker/n8n/update-n8n-config.sh`
- OpenWebUI 설정 변경: `~/docker/openwebui/update-openwebui-config.sh`

## 서비스 시작/중지

모든 서비스를 한 번에 시작하려면:

```bash
~/docker/start-services.sh
```

개별 서비스를 시작/중지하려면:

```bash
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
```

## Nginx Proxy Manager 초기 설정

Nginx Proxy Manager에 처음 로그인할 때 다음 기본 자격 증명을 사용하세요:

- 이메일: admin@example.com
- 비밀번호: changeme

로그인 후 반드시 이메일과 비밀번호를 변경하세요.

## 문제 해결

문제가 발생하면 다음 로그를 확인하세요:

```bash
# n8n 로그 확인
cd ~/docker/n8n && docker-compose logs -f

# Nginx Proxy Manager 로그 확인
cd ~/docker/npm && docker-compose logs -f

# OpenWebUI 로그 확인
cd ~/docker/openwebui && docker-compose logs -f
```

## 라이센스

MIT
