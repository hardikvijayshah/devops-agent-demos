# AWS DevOps Agent - Serverless Application Troubleshooting Workshop

Hands-on workshop demonstrating AWS DevOps Agent's autonomous investigation capabilities across a serverless order processing application. Five labs inject realistic failures into Lambda, Step Functions, DynamoDB, API Gateway, and EventBridge -- then showcase how DevOps Agent correlates telemetry across services to identify root causes.

---

## Architecture

### System Overview

```
Client (curl / generate-traffic.sh)
  |
  v
+-----------------------+
|     API Gateway       |   REST API (Regional)
|     POST /orders      |   X-Ray Tracing: Enabled
|     GET  /orders      |   Metrics: 5XXError, Latency, Count
+-----------+-----------+
            |
+-----------v-----------+
|       Lambda:         |
|     order-api         |   Python 3.12 | 256MB | 30s timeout
|                       |   Writes order to DynamoDB
|                       |   Starts Step Functions execution
+-----------+-----------+
            |
+-----------v-------------------+
|        Step Functions         |
|     Order Workflow            |   X-Ray Tracing: Enabled
|                               |   Retry: 2 attempts per state
|  +-------------------------+  |   Catch: Routes errors to OrderFailed
|  | ValidateOrder           |  |
|  | (validate-order Lambda) |  |
|  +----------+--------------+  |
|             |                 |
|  +----------v--------------+  |
|  | ProcessPayment          |  |
|  | (process-payment Lambda)|  |
|  +----------+--------------+  |
|             |                 |
|  +----------v--------------+  |
|  | UpdateInventory         |  |
|  | (update-inventory Lambda)|  |
|  +----------+--------------+  |
|             |                 |
|  +----------v--------------+  |
|  | SendNotification        |  |
|  | (send-notification Lambda)|  |
|  +----------+--------------+  |
|             |                 |
|     +-------+--------+       |
|     |                |       |
|  +--v---+    +-------v----+  |
|  |Succeed|    |OrderFailed |  |
|  +------+    |  -> EventBridge
|              |  -> Fail    |  |
|              +-------------+  |
+-------------------------------+

Data Stores:                         Event / Messaging:
+------------------+                 +-------------------+
| DynamoDB:        |                 | EventBridge:      |
|   Orders         | 5 RCU / 5 WCU  |   Custom Bus      |
|   Inventory      | 5 RCU / 5 WCU  |   OrderCompleted   |---> SNS Topic
|   Payments       | 5 RCU / 5 WCU  |   OrderFailed      |---> SQS DLQ
+------------------+                 +-------------------+
```

### Data Flow

1. **Client** sends `POST /orders` with JSON body containing `customerId`, `items[]`, and `totalAmount`
2. **order-api Lambda** validates the request, writes order record to DynamoDB Orders table (`status: RECEIVED`), then starts a Step Functions execution
3. **ValidateOrder** checks each item against the Inventory table (stock availability)
4. **ProcessPayment** creates a payment record in the Payments table
5. **UpdateInventory** decrements stock counts in the Inventory table using conditional updates
6. **SendNotification** publishes `OrderCompleted` event to EventBridge and sends message to SNS topic
7. **On failure at any step:** the error is caught, `OrderFailed` event is published to EventBridge, which routes to the SQS Dead Letter Queue

### Seed Data

The CloudFormation template includes a custom resource Lambda that automatically populates the Inventory table on stack creation:

| Product ID | Name | Price | Stock |
|-----------|------|-------|-------|
| PROD-001 | Wireless Headphones | $79 | 500 |
| PROD-002 | USB-C Cable | $15 | 1000 |
| PROD-003 | Laptop Stand | $45 | 300 |
| PROD-004 | Mechanical Keyboard | $120 | 200 |
| PROD-005 | Monitor Light Bar | $55 | 150 |

---

## CloudFormation Resources (43 total)

| Category | Resource | Type | Purpose |
|----------|----------|------|---------|
| **DynamoDB** | OrdersTable | `AWS::DynamoDB::Table` | Stores order records |
| | InventoryTable | `AWS::DynamoDB::Table` | Product catalog and stock levels |
| | PaymentsTable | `AWS::DynamoDB::Table` | Payment transaction records |
| **Lambda** | OrderApiFunction | `AWS::Lambda::Function` | API entry point (256MB, 30s) |
| | ValidateOrderFunction | `AWS::Lambda::Function` | Order validation (128MB, 10s) |
| | ProcessPaymentFunction | `AWS::Lambda::Function` | Payment processing (128MB, 15s) |
| | UpdateInventoryFunction | `AWS::Lambda::Function` | Stock update (128MB, 10s) |
| | SendNotificationFunction | `AWS::Lambda::Function` | Event publishing (128MB, 10s) |
| | SeedDataFunction | `AWS::Lambda::Function` | Inventory seed data (custom resource) |
| **Log Groups** | 5x LogGroups | `AWS::Logs::LogGroup` | 7-day retention per Lambda |
| **Step Functions** | OrderWorkflowStateMachine | `AWS::StepFunctions::StateMachine` | 4-step order workflow |
| **API Gateway** | OrderApi | `AWS::ApiGateway::RestApi` | Regional REST API |
| | OrderResource | `AWS::ApiGateway::Resource` | `/orders` path |
| | OrderPostMethod | `AWS::ApiGateway::Method` | `POST /orders` |
| | OrderGetMethod | `AWS::ApiGateway::Method` | `GET /orders` |
| | ApiDeployment | `AWS::ApiGateway::Deployment` | API deployment |
| | ApiStage | `AWS::ApiGateway::Stage` | `prod` stage with tracing |
| **EventBridge** | OrderEventBus | `AWS::Events::EventBus` | Custom event bus |
| | OrderCompletedRule | `AWS::Events::Rule` | Routes completed orders to SNS |
| | OrderFailedRule | `AWS::Events::Rule` | Routes failed orders to SQS DLQ |
| **SQS** | OrderDLQ | `AWS::SQS::Queue` | Dead letter queue (14-day retention) |
| **SNS** | NotificationTopic | `AWS::SNS::Topic` | Order completion notifications |
| | AlarmNotificationTopic | `AWS::SNS::Topic` | CloudWatch alarm notifications |
| **IAM** | LambdaExecutionRole | `AWS::IAM::Role` | Shared Lambda role (DynamoDB, SFN, EventBridge, SNS) |
| | StepFunctionsExecutionRole | `AWS::IAM::Role` | SFN role (Lambda invoke, EventBridge) |
| | ApiGatewayLogRole | `AWS::IAM::Role` | API Gateway CloudWatch Logs access |
| **Permissions** | ApiGatewayLambdaPermission | `AWS::Lambda::Permission` | Allows API GW to invoke Lambda |
| | OrderCompletedRuleTopicPolicy | `AWS::SNS::TopicPolicy` | Allows EventBridge to publish to SNS |
| | OrderFailedRuleQueuePolicy | `AWS::SQS::QueuePolicy` | Allows EventBridge to send to SQS |
| **Alarms** | 8x CloudWatch Alarms | `AWS::CloudWatch::Alarm` | See alarm details below |
| **Custom** | SeedDataCustomResource | `Custom::SeedData` | Triggers inventory population |

### CloudWatch Alarms

| Alarm Name | Metric | Threshold | Period | Description |
|-----------|--------|-----------|--------|-------------|
| `{prefix}-order-api-errors` | Lambda Errors | >= 3 in 2 periods | 60s | Order API Lambda invocation errors |
| `{prefix}-order-api-duration` | Lambda Duration | >= 10,000ms avg in 2 periods | 60s | Order API Lambda execution time |
| `{prefix}-sfn-failures` | ExecutionsFailed | >= 1 in 1 period | 60s | Step Functions workflow failures |
| `{prefix}-dynamodb-throttle` | WriteThrottleEvents | >= 1 in 1 period | 60s | Inventory table write throttling |
| `{prefix}-api-5xx-errors` | 5XXError | >= 5 in 2 periods | 60s | API Gateway server errors |
| `{prefix}-api-latency` | Latency | >= 5,000ms avg in 2 periods | 60s | API Gateway response latency |
| `{prefix}-dlq-messages` | ApproxNumberOfMessagesVisible | >= 1 in 1 period | 60s | Messages in dead letter queue |
| `{prefix}-validate-order-errors` | Lambda Errors | >= 3 in 1 period | 60s | Validate order Lambda errors |

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **AWS CLI v2** | Configured with `aws configure` |
| **Permissions** | IAM, Lambda, API Gateway, Step Functions, DynamoDB, SQS, SNS, EventBridge, CloudWatch, CloudFormation |
| **DevOps Agent** | Agent Space configured with tag discovery (`devopsagent = true`) |
| **Utilities** | `bash`, `curl`, `zip` |
| **Region** | `us-east-1` recommended (default) |

---

## Deployment

```bash
# Default deployment
./scripts/deploy.sh

# Custom stack name + alarm email
./scripts/deploy.sh my-serverless-workshop user@example.com

# Specific region
export AWS_REGION=us-west-2
./scripts/deploy.sh
```

**Deployment time:** ~5-8 minutes
**Estimated cost:** ~$1-2/hour (DynamoDB provisioned capacity is the primary cost driver)

### What the Deploy Script Does

1. Validates the CloudFormation template syntax
2. Deploys the stack with `CAPABILITY_NAMED_IAM`
3. Tags all resources with `devopsagent=true`
4. Prints all stack outputs (API endpoint, table names, ARNs)
5. Seed data Lambda populates the Inventory table automatically

### Validate Deployment

```bash
./tests/validate-stack.sh [stack-name]
```

This checks: stack status, all Lambda functions, DynamoDB tables, Step Functions state machine, API Gateway endpoint, EventBridge bus, SQS DLQ, CloudWatch alarms, seed data (5 inventory items), and runs an end-to-end order submission test.

---

## Labs

| Lab | Scenario | What Gets Changed | Impact | Alarms Triggered | Difficulty |
|-----|----------|-------------------|--------|-----------------|-----------|
| **1** | [Lambda Timeout](labs/lab1-lambda-timeout/) | Timeout: 30s -> 1s, Memory: 256MB -> 128MB | API returns 502/504, no orders processed | order-api-errors, order-api-duration, api-5xx-errors | Beginner |
| **2** | [Step Functions Failure](labs/lab2-stepfunctions-failure/) | validate-order code replaced with broken version | Orders accepted but workflow fails at validation | sfn-failures, validate-order-errors, dlq-messages | Intermediate |
| **3** | [DynamoDB Throttle](labs/lab3-dynamodb-throttle/) | Inventory WCU: 5 -> 1, RCU: 5 -> 1 | Cascade: DDB throttle -> Lambda fail -> SFN fail -> DLQ | dynamodb-throttle, sfn-failures, dlq-messages | Intermediate |
| **4** | [API Gateway 5xx](labs/lab4-api-gateway-errors/) | order-api code returns malformed responses | All API requests return 502 Bad Gateway | api-5xx-errors, order-api-errors | Intermediate |
| **5** | [EventBridge Misconfig](labs/lab5-eventbridge-misconfig/) | Rule pattern: `order.service` -> `order.service.v2` | Orders complete but notifications silently stop | None initially (silent failure) | Advanced |

### Lab Flow

```bash
# 1. Navigate to the lab
cd labs/lab1-lambda-timeout/

# 2. Inject the failure
./inject.sh [stack-name]

# 3. Generate traffic to trigger the failure
../../scripts/generate-traffic.sh [stack-name] 30 1

# 4. Wait for alarms (2-3 minutes)
aws cloudwatch describe-alarms \
    --alarm-name-prefix [stack-name] \
    --state-value ALARM --output table

# 5. Investigate with DevOps Agent
# Via web UI, Slack, or automatic webhook

# 6. Rollback when done
./rollback.sh [stack-name]
```

### Lab Details

**Lab 1 -- Lambda Timeout (Beginner):**
Reduces the order-api Lambda timeout to 1 second and memory to 128MB. Under any traffic, the function cannot complete DynamoDB writes and Step Functions starts before timing out. DevOps Agent should identify the configuration change, correlate it with the error spike, and recommend increasing timeout/memory.

**Lab 2 -- Step Functions Failure (Intermediate):**
Replaces the validate-order Lambda code with a version that accesses a non-existent nested path (`order['orderDetails']['itemList']['entries']`), causing `KeyError` on every invocation. Orders are accepted by the API but fail during workflow processing. DevOps Agent should trace failures from Step Functions execution history through to the Lambda error logs.

**Lab 3 -- DynamoDB Throttle (Intermediate):**
Reduces the Inventory table provisioned throughput to 1 RCU/1 WCU. Under moderate traffic, write operations are throttled with `ProvisionedThroughputExceededException`, causing cascading failures through update-inventory Lambda -> Step Functions -> DLQ. DevOps Agent should map the full cascade chain and recommend throughput increase or on-demand billing.

**Lab 4 -- API Gateway 5xx (Intermediate):**
Replaces the order-api Lambda code with a version that randomly returns malformed responses (missing `statusCode`, unhandled exceptions, non-string `body`). API Gateway returns 502 Bad Gateway for all requests. DevOps Agent should identify the Lambda integration error and detect the code change as root cause.

**Lab 5 -- EventBridge Misconfig (Advanced):**
Changes the EventBridge rule pattern to expect `order.service.v2` / `OrderCompletedV2` instead of the actual `order.service` / `OrderCompleted`. Orders complete successfully end-to-end, but completion notifications silently stop because no rule matches. This is the hardest scenario -- a silent failure with no errors. DevOps Agent must correlate the absence of expected SNS activity with the EventBridge rule configuration change.

---

## DevOps Agent Space Configuration

After deploying the stack:

1. **Tag-based discovery:** Configure Agent Space to discover resources with tag `devopsagent = true`
2. **CloudWatch Logs:** Ensure the agent can query log groups `/aws/lambda/{prefix}-*`
3. **CloudWatch Metrics:** Ensure access to Lambda, DynamoDB, States, ApiGateway, SQS namespaces
4. **CloudTrail:** Enable for Lambda configuration changes, DynamoDB throughput changes, EventBridge rule updates
5. **Webhook (optional):** Connect CloudWatch Alarm -> SNS -> Lambda -> DevOps Agent webhook endpoint for automatic investigation triggers

---

## Cleanup

```bash
./scripts/cleanup.sh [stack-name]
```

Prompts for confirmation, then deletes the entire CloudFormation stack and all resources.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Stack fails with IAM error | Ensure deploying user has `iam:CreateRole` and `iam:PutRolePolicy` |
| Lambda functions not in Agent Space | Check `devopsagent=true` tag, verify Agent Space tag filter |
| Alarms not triggering | Generate more traffic (`30 1` = 30 requests, 1s apart); wait 2 evaluation periods |
| API returns 403 | Check API Gateway stage is deployed; verify Lambda permission exists |
| Seed data missing | Check SeedDataFunction logs; re-run stack update if needed |
| Rollback doesn't clear alarms | Alarms return to OK after 1-2 evaluation periods of healthy metrics |
