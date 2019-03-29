#!/bin/bash

### This works for CircleCI, not local execution
STACK_NAME=${CIRCLE_PROJECT_REPONAME}-${CIRCLE_BRANCH}

### This works for local execution, not CircleCI
# REPO_NAME=$(basename `git rev-parse --show-toplevel`)
# BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
# STACK_NAME=${REPO_NAME}-${BRANCH_NAME}
# if [ "$BRANCH_NAME" == "master" ]; then {
#     echo -e "Test works for all branches except MASTER"
#     exit 1
# }
# fi

echo -e "STACK_NAME=" $STACK_NAME

echo -e "Working with test env, setting appropriate variables.."
ENVIRONMENT="TEST"
AWS_REGION="eu-west-1"
AWS_S3_BUCKET_TEST="aws-cloudformation-ec2-radius/test"
AWS_S3_BUCKET_PROD="aws-cloudformation-ec2-radius/production"
AWS_EC2_INSTANCE_TYPE_TEST="t2.large"
HOSTED_ZONE="demo.kagarlickij.com"
RECORD_SET_TEST="test-endpoint.demo.kagarlickij.com"

echo -e "AWS_REGION="$AWS_REGION
echo -e "AWS_S3_BUCKET_TEST="$AWS_S3_BUCKET_TEST
echo -e "AWS_S3_BUCKET_PROD="$AWS_S3_BUCKET_PROD
echo -e "AWS_EC2_INSTANCE_TYPE_TEST="$AWS_EC2_INSTANCE_TYPE_TEST
echo -e "HOSTED_ZONE="$HOSTED_ZONE
echo -e "RECORD_SET_TEST="$RECORD_SET_TEST

function checkCommandExitCode {
    if [ $? -ne 0 ]; then {
        echo -e $1 "command has failed"
        exit 1
    }
    fi
}

function deleteStack {
    echo -e "Starting CloudFormation stack delete.."
    aws cloudformation delete-stack --region $AWS_REGION --stack-name $STACK_NAME
    checkCommandExitCode "CloudFormation stack delete"

    WAIT_RESULT=$(aws cloudformation wait stack-delete-complete --region $AWS_REGION --stack-name $STACK_NAME)
    if [ "$WAIT_RESULT" == "Waiter StackCreateComplete failed: Waiter encountered a terminal failure state" ]; then {
        echo -e "CloudFormation stack delete has failed"
        aws cloudformation describe-stack-events --region $AWS_REGION --stack-name $STACK_NAME
        exit 1
    } else {
        echo -e "CloudFormation stack delete has passed successfully"
    }
    fi
}

function runTests {
    echo -e "Starting CloudFormation Linter.."
    cfn-lint
    if [ $? -ne 0 ]; then {
        checkCommandExitCode "CloudFormation Linter has failed"
    } else {
        echo -e "CloudFormation Linter has passed successfully"
    }
    fi
}

function createProdCopy {
    echo -e "Downloading root template from master branch.."
    git show master:root.yaml > master_root.yaml
    checkCommandExitCode "Downloading root template from master branch"

    echo -e "Starting CloudFormation stack create.."
    aws cloudformation create-stack \
        --region $AWS_REGION \
        --capabilities CAPABILITY_NAMED_IAM \
        --stack-name $STACK_NAME \
        --template-body file://master_root.yaml \
        --parameters \
        ParameterKey=NestedTemplateUrl,ParameterValue=https://s3.amazonaws.com/$AWS_S3_BUCKET_PROD/nested.yaml \
        ParameterKey=InstanceType,ParameterValue=$AWS_EC2_INSTANCE_TYPE_TEST \
        ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
        ParameterKey=HostedZone,ParameterValue=$HOSTED_ZONE \
        ParameterKey=RecordSetName,ParameterValue=$RECORD_SET_TEST
    checkCommandExitCode "CloudFormation stack create"

    rm -f ./master_root.yaml
    checkCommandExitCode "Delete ./master_root.yaml file"

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
}

function updateProdCopy {
    aws s3 rm s3://$AWS_S3_BUCKET_TEST/nested.yaml
    checkCommandExitCode "aws s3 rm"
    aws s3 cp nested.yaml s3://$AWS_S3_BUCKET_TEST/nested.yaml
    checkCommandExitCode "aws s3 cp"

    echo -e "Starting CloudFormation stack update.."
    aws cloudformation update-stack \
        --region $AWS_REGION \
        --capabilities CAPABILITY_NAMED_IAM \
        --stack-name $STACK_NAME \
        --template-body file://root.yaml \
        --parameters \
        ParameterKey=NestedTemplateUrl,ParameterValue=https://s3.amazonaws.com/$AWS_S3_BUCKET_TEST/nested.yaml \
        ParameterKey=InstanceType,ParameterValue=$AWS_EC2_INSTANCE_TYPE_TEST \
        ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
        ParameterKey=HostedZone,ParameterValue=$HOSTED_ZONE \
        ParameterKey=RecordSetName,ParameterValue=$RECORD_SET_TEST
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
        deleteStack
    }
    fi
}

runTests
createProdCopy
updateProdCopy
