import { CfnOutput, Duration, RemovalPolicy, Stack, StackProps } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from "aws-cdk-lib/aws-ec2";
import { readFileSync } from "fs";
import * as cognito from "aws-cdk-lib/aws-cognito";
import * as iam from "aws-cdk-lib/aws-iam";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as s3deploy from "aws-cdk-lib/aws-s3-deployment";

export class CdkWorkshopStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

/* //VPC
    const vpc = new ec2.Vpc(this, "Tsai_cdk_Vpc", {
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
      subnetConfiguration: [
      {
        cidrMask: 24,
        name: 'ingress',
        subnetType: ec2.SubnetType.PUBLIC,
      },
      {
        cidrMask: 24,
        name: 'application',
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      {
        cidrMask: 28,
        name: 'rds',
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      }
    ]
    });

//security group create tsai-SG (office ip only)
   const securityGroup = new ec2.SecurityGroup(this, 'tsai-SG', { 
    vpc,
    description: 'Allow HTTP from office ip',
    allowAllOutbound: true,
    securityGroupName: 'tsai-SG',
  });

     securityGroup.addIngressRule(ec2.Peer.ipv4("39.110.203.85/32"),ec2.Port.tcp(80),"Allow http from 39.110.203.85"); */

//cognito create user pool
   const userPool = new cognito.UserPool(this, 'tsai_userpool',{
    userPoolName: 'tsai_userpool',
    signInAliases: {
      email: true,
    },
    autoVerify: {
      email: true,
    },
    passwordPolicy: {
      minLength: 8,
      requireLowercase: true,
      requireUppercase: true,
      requireDigits: true,
      requireSymbols: true,
      tempPasswordValidity: Duration.days(3),
    },
    accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
    removalPolicy: RemovalPolicy.DESTROY,
    selfSignUpEnabled: true,
    mfa: cognito.Mfa.OPTIONAL,
    mfaSecondFactor: {
      sms: true,
      otp: true,
    },
    signInCaseSensitive: false, // 改為 false 更方便使用
  });

// 創建 App Client（移除 Amazon 提供商，簡化設置）
const client = userPool.addClient('tsai-cdk-app-client', {
  userPoolClientName: 'tsai-cdk-app-client',
  generateSecret: false, // 前端應用不需要 secret
  authFlows: {
    adminUserPassword: true,
    custom: true,
    userSrp: true,
    userPassword: true,
  },
  supportedIdentityProviders: [
    cognito.UserPoolClientIdentityProvider.COGNITO,
  ],
});

// Create an identity pool
const identityPool = new cognito.CfnIdentityPool(this, 'tsai-IdentityPool', {
  identityPoolName: 'tsai-IdentityPool',
  allowUnauthenticatedIdentities: true,
  cognitoIdentityProviders: [{
    clientId: client.userPoolClientId,
    providerName: userPool.userPoolProviderName,
  }],
});

// 創建身份池角色
const authenticatedRole = new iam.Role(this, 'CognitoDefaultAuthenticatedRole', {
  assumedBy: new iam.FederatedPrincipal('cognito-identity.amazonaws.com', {
    StringEquals: {
      'cognito-identity.amazonaws.com:aud': identityPool.ref,
    },
    'ForAnyValue:StringLike': {
      'cognito-identity.amazonaws.com:amr': 'authenticated',
    },
  }),
});

const unauthenticatedRole = new iam.Role(this, 'CognitoDefaultUnauthenticatedRole', {
  assumedBy: new iam.FederatedPrincipal('cognito-identity.amazonaws.com', {
    StringEquals: {
      'cognito-identity.amazonaws.com:aud': identityPool.ref,
    },
    'ForAnyValue:StringLike': {
      'cognito-identity.amazonaws.com:amr': 'unauthenticated',
    },
  }),
});

// 附加身份池角色
new cognito.CfnIdentityPoolRoleAttachment(this, 'IdentityPoolRoleAttachment', {
  identityPoolId: identityPool.ref,
  roles: {
    authenticated: authenticatedRole.roleArn,
    unauthenticated: unauthenticatedRole.roleArn,
  },
});

// 創建 S3 bucket 來託管網頁
const websiteBucket = new s3.Bucket(this, 'WebsiteBucket', {
  bucketName: `tsai-cognito-website-${this.account}-${this.region}`,
  websiteIndexDocument: 'index.html',
  publicReadAccess: true,
  blockPublicAccess: {
    blockPublicAcls: false,
    blockPublicPolicy: false,
    ignorePublicAcls: false,
    restrictPublicBuckets: false,
  },
  removalPolicy: RemovalPolicy.DESTROY,
  autoDeleteObjects: true,
});

// 部署網頁文件
new s3deploy.BucketDeployment(this, 'DeployWebsite', {
  sources: [s3deploy.Source.asset('../frontend/website')],
  destinationBucket: websiteBucket,
});

// 輸出重要的資源 ID
new CfnOutput(this, 'UserPoolId', {
  value: userPool.userPoolId,
  description: 'Cognito User Pool ID',
});

new CfnOutput(this, 'UserPoolClientId', {
  value: client.userPoolClientId,
  description: 'Cognito User Pool Client ID',
});

new CfnOutput(this, 'IdentityPoolId', {
  value: identityPool.ref,
  description: 'Cognito Identity Pool ID',
});

new CfnOutput(this, 'Region', {
  value: this.region,
  description: 'AWS Region',
});

new CfnOutput(this, 'WebsiteURL', {
  value: websiteBucket.bucketWebsiteUrl,
  description: 'Website URL',
});

/* new CfnOutput(this, 'SecurityGroupId', {
  value: securityGroup.securityGroupId,
  description: 'Security Group ID',
}); */
  }
}
