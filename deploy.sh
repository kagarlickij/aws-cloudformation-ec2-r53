#!/bin/bash

### This works for CircleCI, not local execution
STACK_NAME=${CIRCLE_PROJECT_REPONAME}-${CIRCLE_BRANCH}

### This works for local execution, not CircleCI
# REPO_NAME=$(basename `git rev-parse --show-toplevel`)
# BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
# STACK_NAME=${REPO_NAME}-${BRANCH_NAME}
# if [ "$BRANCH_NAME" != "master" ]; then {
#     echo -e "Deploy works for MASTER branch only, current branch $BRANCH_NAME is not supported"
#     exit 1
# }
# fi

echo -e "STACK_NAME=" $STACK_NAME

echo -e "Deploy to production env, setting appropriate variables.."
ENVIRONMENT="PROD"
AWS_REGION="us-east-1"
AWS_S3_BUCKET_PROD="aws-cloudformation-ec2-radius/production"
AWS_EC2_INSTANCE_TYPE_PROD="m5.large"
HOSTED_ZONE="demo.kagarlickij.com"
RECORD_SET_PROD="endpoint.demo.kagarlickij.com"

echo -e "AWS_REGION="$AWS_REGION
echo -e "AWS_S3_BUCKET_PROD="$AWS_S3_BUCKET_PROD
echo -e "AWS_EC2_INSTANCE_TYPE_PROD="$AWS_EC2_INSTANCE_TYPE_PROD
echo -e "HOSTED_ZONE="$HOSTED_ZONE
echo -e "RECORD_SET_PROD="$RECORD_SET_PROD

function checkCommandExitCode {
    if [ $? -ne 0 ]; then {
        echo -e $1 "command has failed"
        exit 1
    }
    fi
}

function updateProd {
    echo -e "Starting CloudFormation stack update.."
    aws cloudformation update-stack \
        --region $AWS_REGION \
        --capabilities CAPABILITY_NAMED_IAM \
        --stack-name $STACK_NAME \
        --template-body file://root.yaml \
        --parameters \
        ParameterKey=NestedTemplateUrl,ParameterValue=https://s3.amazonaws.com/$AWS_S3_BUCKET_PROD/nested.yaml \
        ParameterKey=InstanceType,ParameterValue=$AWS_EC2_INSTANCE_TYPE_PROD \
        ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
        ParameterKey=HostedZone,ParameterValue=$HOSTED_ZONE \
        ParameterKey=RecordSetName,ParameterValue=$RECORD_SET_PROD
    checkCommandExitCode "CloudFormation stack update"

    WAIT_RESULT=$(aws cloudformation wait stack-update-complete --region $AWS_REGION --stack-name $STACK_NAME)
    if [ "$WAIT_RESULT" == "Waiter StackCreateComplete failed: Waiter encountered a terminal failure state" ]; then {
        echo -e "CloudFormation stack update has failed"
        aws cloudformation describe-stack-events --region $AWS_REGION --stack-name $STACK_NAME
        exit 1
    }
    fi

    DEPLOY_RESULT=$(aws cloudformation describe-stacks --region $AWS_REGION --stack-name $STACK_NAME | jq --raw-output '.Stacks | .[] | .StackStatus')
    if [ "$DEPLOY_RESULT" != "UPDATE_COMPLETE" ]; then {
        echo -e "CloudFormation stack update has failed"
        aws cloudformation describe-stack-events --region $AWS_REGION --stack-name $STACK_NAME
        exit 1
    } else {
        echo -e "CloudFormation stack update has passed successfully"
    }
    fi
}

function createProd {
    aws s3 rm s3://$AWS_S3_BUCKET_PROD/nested.yaml
    checkCommandExitCode "aws s3 rm"

    aws s3 cp nested.yaml s3://$AWS_S3_BUCKET_PROD/nested.yaml
    checkCommandExitCode "aws s3 cp"

    echo -e "Checking if CloudFormation stack exists.."
    aws cloudformation describe-stacks --region $AWS_REGION --stack-name $STACK_NAME
    if [ $? -ne 0 ]; then {

        echo -e "Starting CloudFormation stack create.."
        aws cloudformation create-stack \
            --region $AWS_REGION \
            --capabilities CAPABILITY_NAMED_IAM \
            --stack-name $STACK_NAME \
            --template-body file://root.yaml \
            --parameters \
            ParameterKey=NestedTemplateUrl,ParameterValue=https://s3.amazonaws.com/$AWS_S3_BUCKET_PROD/nested.yaml \
            ParameterKey=InstanceType,ParameterValue=$AWS_EC2_INSTANCE_TYPE_PROD \
            ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
            ParameterKey=HostedZone,ParameterValue=$HOSTED_ZONE \
            ParameterKey=RecordSetName,ParameterValue=$RECORD_SET_PROD
        checkCommandExitCode "CloudFormation stack create"

        WAIT_RESULT=$(aws cloudformation wait stack-create-complete --region $AWS_REGION --stack-name $STACK_NAME)
        if [ "$WAIT_RESULT" == "Waiter StackCreateComplete failed: Waiter encountered a terminal failure state" ]; then {
            echo -e "CloudFormation stack create has failed"
            aws cloudformation describe-stack-events --region $AWS_REGION --stack-name $STACK_NAME
            exit 1
        }
        fi

        DEPLOY_RESULT=$(aws cloudformation describe-stacks --region $AWS_REGION --stack-name $STACK_NAME | jq --raw-output '.Stacks | .[] | .StackStatus')
        if [ "$DEPLOY_RESULT" != "CREATE_COMPLETE" ]; then {
            echo -e "CloudFormation stack create has failed"
            aws cloudformation describe-stack-events --region $AWS_REGION --stack-name $STACK_NAME
            exit 1
        } else {
            echo -e "CloudFormation stack create has passed successfully"
        }
        fi
    } else {
        updateProd
    }
    fi
}

createProd
