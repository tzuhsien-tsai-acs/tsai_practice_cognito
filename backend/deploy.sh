#!/bin/zsh

# 色の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ログ関数
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_step() { echo -e "${PURPLE}🚀 $1${NC}"; }

echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}🚀 Tsai Cognito アプリケーション自動デプロイスクリプト${NC}"
echo -e "${CYAN}================================================${NC}"

# 必要なツールのチェック
log_step "環境要件を確認中..."

check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_error "$1 はインストールされていません。先にインストールしてください: $2"
        exit 1
    fi
}

#check_command "cdk" "npm install -g aws-cdk"
#check_command "aws" "AWS CLI"
#check_command "node" "Node.js"
#check_command "npm" "Node.js"

# jq のチェック（JSON処理用）
if ! command -v jq >/dev/null 2>&1; then
    log_warning "jq はインストールされていません。インストールを試みます..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install jq 2>/dev/null || { log_error "jq を手動でインストールしてください: brew install jq"; exit 1; }
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update && sudo apt-get install -y jq 2>/dev/null || { log_error "jq を手動でインストールしてください"; exit 1; }
    else
        log_error "jq を手動でインストールしてください"
        exit 1
    fi
fi

# AWS 認証情報のチェック
log_info "AWS 認証情報を確認中..."
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log_error "AWS 認証情報が設定されていません。以下を実行してください: aws configure"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region || echo "us-east-1")
log_success "環境チェックを通過しました (Account: $ACCOUNT_ID, Region: $AWS_REGION)"

# ウェブサイトディレクトリとファイルの作成
# 依存関係のインストール
#log_step "NPM 依存関係をインストール中..."
npm install

# CDK のブートストラップ（必要な場合）
log_step "CDK をブートストラップ中..."
npx aws-cdk bootstrap --require-approval never

# スタックのデプロイ
log_step "CDK スタックをデプロイ中..."
npx aws-cdk deploy --no-notices --require-approval never

if [ $? -eq 0 ]; then
    log_success "CDK デプロイが成功しました！"
    
    # スタック名の取得
    STACK_NAME=$(npx aws-cdk --no-notices list | head -n 1)
    log_info "スタック名: $STACK_NAME"
    
    # 出力値の取得
    log_step "デプロイ出力値を取得中..."
    OUTPUTS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].Outputs' --output json)
    
    # 設定値の抽出
    USER_POOL_ID=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="UserPoolId" or .OutputKey=="UserPool") | .OutputValue' | head -n 1)
    CLIENT_ID=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="UserPoolClientId") | .OutputValue')
    IDENTITY_POOL_ID=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="IdentityPoolId") | .OutputValue')
    WEBSITE_URL=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="WebsiteURL") | .OutputValue')
    
    # 出力から Region を取得できなかった場合、現在の設定済みの Region を使用
    if [ -z "$AWS_REGION" ] || [ "$AWS_REGION" = "null" ]; then
        AWS_REGION=$(aws configure get region || echo "us-east-1")
    fi
    
    # 必要な設定値の検証
    if [ -z "$USER_POOL_ID" ] || [ "$USER_POOL_ID" = "null" ]; then
        log_error "User Pool ID を取得できませんでした"
        exit 1
    fi
    
    if [ -z "$CLIENT_ID" ] || [ "$CLIENT_ID" = "null" ]; then
        log_error "Client ID を取得できませんでした"
        exit 1
    fi
    
    # ... (CLIENT_ID, USER_POOL_ID, AWS_REGION の代入後) ...
    log_info "DEBUG: 抽出された USER_POOL_ID: '$USER_POOL_ID'"
    log_info "DEBUG: 抽出された CLIENT_ID: '$CLIENT_ID'"
    log_info "DEBUG: 抽出された AWS_REGION: '$AWS_REGION'"
# ... (sed コマンド開始) ...
    # HTML ファイル内の設定を更新
    log_step "ウェブサイト設定を更新中..."

    cp ../frontend/website/template-index.html ../frontend/website/index.html
    
    # sed を使用してプレースホルダーを置換
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
    
    log_success "ウェブサイト設定の更新が完了しました！"
    
    # S3 ウェブサイトがある場合、ファイルを同期
    if [ "$WEBSITE_URL" != "null" ] && [ -n "$WEBSITE_URL" ]; then
        log_step "ウェブサイトファイルを S3 に同期中..."
        
        # CloudFormation から S3 バケット名を取得
        BUCKET_NAME=$(aws cloudformation describe-stack-resources --stack-name "$STACK_NAME" --query 'StackResources[?ResourceType==`AWS::S3::Bucket`].PhysicalResourceId' --output text)
        
        if [ -n "$BUCKET_NAME" ] && [ "$BUCKET_NAME" != "None" ]; then
            aws s3 sync ../frontend/website/ s3://$BUCKET_NAME/ --delete
            log_success "ウェブサイトファイルの同期が完了しました！"
        fi
    fi
    
    # デプロイ結果の表示
    echo ""
    echo -e "${CYAN}================================================${NC}"
    echo -e "${GREEN}🎉 デプロイ完了！${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo -e "${BLUE}📋 リソース情報:${NC}"
    echo -e "   Region: ${GREEN}$AWS_REGION${NC}"
    echo -e "   User Pool ID: ${GREEN}$USER_POOL_ID${NC}"
    echo -e "   Client ID: ${GREEN}$CLIENT_ID${NC}"
    
    if [ "$IDENTITY_POOL_ID" != "null" ] && [ -n "$IDENTITY_POOL_ID" ]; then
        echo -e "   Identity Pool ID: ${GREEN}$IDENTITY_POOL_ID${NC}"
    fi
    
    if [ "$WEBSITE_URL" != "null" ] && [ -n "$WEBSITE_URL" ]; then
        echo -e "   ウェブサイト URL: ${GREEN}$WEBSITE_URL${NC}"
        echo ""
        echo -e "${GREEN}🌐 あなたのウェブサイトは準備完了です！${NC}"
        echo -e "${YELLOW}📱 上記 URL にアクセスしてログインとサインアップ機能をテストしてください${NC}"
        echo ""
        echo -e "${BLUE}💡 テスト手順：${NC}"
        echo -e "   1. 'サインアップ' タブをクリック"
        echo -e "   2. メールアドレスとパスワード（8文字以上）を入力"
        echo -e "   3. メールで認証コードを確認"
        echo -e "   4. 認証コードを入力してサインアップを完了"
        echo -e "   5. 登録したアカウントでログイン"
    else
        echo ""
        echo -e "${YELLOW}📁 ローカルテスト：${NC}"
        echo -e "   ../frontend/website/index.html ファイルを直接開いてアプリケーションをテストできます"
    fi
    
    echo -e "${CYAN}================================================${NC}"
    
else
    log_error "CDK デプロイが失敗しました"
    exit 1
fi
