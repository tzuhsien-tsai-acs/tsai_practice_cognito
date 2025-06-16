#!/bin/zsh

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 日誌函數
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_step() { echo -e "${PURPLE}🚀 $1${NC}"; }

echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}🚀 Tsai Cognito 應用自動部署腳本${NC}"
echo -e "${CYAN}================================================${NC}"

# 檢查必要工具
log_step "檢查環境要求..."

check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_error "$1 未安裝。請先安裝: $2"
        exit 1
    fi
}

#check_command "cdk" "npm install -g aws-cdk"
#check_command "aws" "AWS CLI"
#check_command "node" "Node.js"
#check_command "npm" "Node.js"

# 檢查 jq（用於 JSON 處理）
if ! command -v jq >/dev/null 2>&1; then
    log_warning "jq 未安裝，嘗試安裝..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install jq 2>/dev/null || { log_error "請手動安裝 jq: brew install jq"; exit 1; }
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update && sudo apt-get install -y jq 2>/dev/null || { log_error "請手動安裝 jq"; exit 1; }
    else
        log_error "請手動安裝 jq"
        exit 1
    fi
fi

# 檢查 AWS 憑證
log_info "檢查 AWS 憑證..."
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log_error "AWS 憑證未配置。請運行: aws configure"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region || echo "us-east-1")
log_success "環境檢查通過 (Account: $ACCOUNT_ID, Region: $AWS_REGION)"

# 創建網站目錄和文件
# 安裝依賴
#log_step "安裝 NPM 依賴..."
npm install

# Bootstrap CDK（如果需要）
log_step "Bootstrap CDK..."
npx aws-cdk bootstrap --require-approval never

# 部署堆疊
log_step "部署 CDK 堆疊..."
npx aws-cdk deploy --no-notices --require-approval never

if [ $? -eq 0 ]; then
    log_success "CDK 部署成功！"
    
    # 獲取堆疊名稱
    STACK_NAME=$(npx aws-cdk --no-notices list | head -n 1)
    log_info "堆疊名稱: $STACK_NAME"
    
    # 獲取輸出值
    log_step "獲取部署輸出值..."
    OUTPUTS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].Outputs' --output json)
    
    # 提取配置值
    USER_POOL_ID=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="UserPoolId" or .OutputKey=="UserPool") | .OutputValue' | head -n 1)
    CLIENT_ID=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="UserPoolClientId") | .OutputValue')
    IDENTITY_POOL_ID=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="IdentityPoolId") | .OutputValue')
    WEBSITE_URL=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="WebsiteURL") | .OutputValue')
    
    # 如果沒有從輸出獲取到 Region，使用當前配置的 Region
    if [ -z "$AWS_REGION" ] || [ "$AWS_REGION" = "null" ]; then
        AWS_REGION=$(aws configure get region || echo "us-east-1")
    fi
    
    # 驗證必要的配置值
    if [ -z "$USER_POOL_ID" ] || [ "$USER_POOL_ID" = "null" ]; then
        log_error "無法獲取 User Pool ID"
        exit 1
    fi
    
    if [ -z "$CLIENT_ID" ] || [ "$CLIENT_ID" = "null" ]; then
        log_error "無法獲取 Client ID"
        exit 1
    fi
    

    # ... (在 CLIENT_ID, USER_POOL_ID, AWS_REGION 賦值之後) ...
    log_info "DEBUG: Extracted USER_POOL_ID: '$USER_POOL_ID'"
    log_info "DEBUG: Extracted CLIENT_ID: '$CLIENT_ID'"
    log_info "DEBUG: Extracted AWS_REGION: '$AWS_REGION'"
# ... (sed 命令開始) ...
    # 更新 HTML 文件中的配置
    log_step "更新網站配置..."

    cp ../frontend/website/template-index.html ../frontend/website/index.html
    
    # 使用 sed 替換佔位符
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s|{{USER_POOL_ID}}|$USER_POOL_ID|g" ../frontend/website/index.html
        sed -i '' "s|{{CLIENT_ID}}|$CLIENT_ID|g" ../frontend/website/index.html
        sed -i '' "s|{{REGION}}|$AWS_REGION|g" ../frontend/website/index.html
    else
        # Linux
        sed -i "s|{{USER_POOL_ID}}|$USER_POOL_ID|g" ../frontend/website/index.html
        sed -i "s|{{CLIENT_ID}}|$CLIENT_ID|g" ../frontend/website/index.html
        sed -i "s|{{REGION}}|$AWS_REGION|g" ../frontend/website/index.html
    fi
    
    log_success "網站配置更新完成！"
    
    # 如果有 S3 網站，同步文件
    if [ "$WEBSITE_URL" != "null" ] && [ -n "$WEBSITE_URL" ]; then
        log_step "同步網站文件到 S3..."
        
        # 從 CloudFormation 獲取 S3 bucket 名稱
        BUCKET_NAME=$(aws cloudformation describe-stack-resources --stack-name "$STACK_NAME" --query 'StackResources[?ResourceType==`AWS::S3::Bucket`].PhysicalResourceId' --output text)
        
        if [ -n "$BUCKET_NAME" ] && [ "$BUCKET_NAME" != "None" ]; then
            aws s3 sync ../frontend/website/ s3://$BUCKET_NAME/ --delete
            log_success "網站文件同步完成！"
        fi
    fi
    
    # 顯示部署結果
    echo ""
    echo -e "${CYAN}================================================${NC}"
    echo -e "${GREEN}🎉 部署完成！${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo -e "${BLUE}📋 資源資訊:${NC}"
    echo -e "   Region: ${GREEN}$AWS_REGION${NC}"
    echo -e "   User Pool ID: ${GREEN}$USER_POOL_ID${NC}"
    echo -e "   Client ID: ${GREEN}$CLIENT_ID${NC}"
    
    if [ "$IDENTITY_POOL_ID" != "null" ] && [ -n "$IDENTITY_POOL_ID" ]; then
        echo -e "   Identity Pool ID: ${GREEN}$IDENTITY_POOL_ID${NC}"
    fi
    
    if [ "$WEBSITE_URL" != "null" ] && [ -n "$WEBSITE_URL" ]; then
        echo -e "   網站 URL: ${GREEN}$WEBSITE_URL${NC}"
        echo ""
        echo -e "${GREEN}🌐 您的網站已準備就緒！${NC}"
        echo -e "${YELLOW}📱 請訪問上述 URL 來測試登入和註冊功能${NC}"
        echo ""
        echo -e "${BLUE}💡 測試步驟：${NC}"
        echo -e "   1. 點擊 '註冊' 標籤"
        echo -e "   2. 輸入電子郵件和密碼（至少8位字符）"
        echo -e "   3. 檢查您的電子郵件獲取驗證碼"
        echo -e "   4. 輸入驗證碼完成註冊"
        echo -e "   5. 使用註冊的帳戶登入"
    else
        echo ""
        echo -e "${YELLOW}📁 本地測試：${NC}"
        echo -e "   您可以直接打開 ../frontend/website/index.html 文件來測試應用"
    fi
    
    echo -e "${CYAN}================================================${NC}"
    
else
    log_error "CDK 部署失敗"
    exit 1
fi
