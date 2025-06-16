import { CfnOutput, Duration, RemovalPolicy, Stack, StackProps } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from "aws-cdk-lib/aws-ec2";
import { readFileSync } from "fs";
import * as cognito from "aws-cdk-lib/aws-cognito";
import * as iam from "aws-cdk-lib/aws-iam";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as s3deploy from "aws-cdk-lib/aws-s3-deployment";
import * as cfninc from 'aws-cdk-lib/cloudformation-include';
import * as path from 'path';

export class CdkWorkshopStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

//const cloudformation_template = readFileSync("./lib/resources/cloudformaiton-template.yaml", "utf8");
const cloudformation_template = readFileSync(path.join(__dirname, 'resources', 'cloudformation-template.yaml'), 'utf8');

const cfnTemplate = new cfninc.CfnInclude(this, 'Template', {
  templateFile: './lib/resources/cloudformation-template.yaml',
});
}
}
