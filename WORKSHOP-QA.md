# AWS DevOps Agent Workshop - Anticipated Questions & Answers

Prepared for workshop presenters. Covers product fundamentals, technical deep dives, pricing, security, and workshop-specific questions customers are likely to ask.

---

## Table of Contents

1. [Product Overview & Positioning](#1-product-overview--positioning)
2. [Architecture & Agent Spaces](#2-architecture--agent-spaces)
3. [Capabilities & Supported Services](#3-capabilities--supported-services)
4. [Integrations & Extensibility](#4-integrations--extensibility)
5. [Security & Compliance](#5-security--compliance)
6. [Pricing & Cost](#6-pricing--cost)
7. [Comparison with Other AWS Services](#7-comparison-with-other-aws-services)
8. [Multi-Account & Enterprise](#8-multi-account--enterprise)
9. [Setup & Prerequisites](#9-setup--prerequisites)
10. [Workshop-Specific Questions](#10-workshop-specific-questions)
11. [Limitations & Edge Cases](#11-limitations--edge-cases)
12. [Customer Success Stories](#12-customer-success-stories)

---

## 1. Product Overview & Positioning

### Q: What exactly is AWS DevOps Agent?

**A:** AWS DevOps Agent is an autonomous AI-powered operations service that acts as an always-available operations teammate. It resolves incidents, proactively prevents future problems, and handles on-demand SRE tasks across AWS, multicloud, and on-premises environments. It is powered by Amazon Bedrock foundation models and operates as a standalone AWS service.

---

### Q: Is DevOps Agent generally available or still in preview?

**A:** DevOps Agent is **generally available (GA)**. It was previously in Public Preview, and customers who participated in the preview are eligible for a 2-month free trial post-GA.

---

### Q: What are the three main modes of operation?

**A:** DevOps Agent operates in three modes:

1. **Investigations** -- Autonomous incident response triggered by alarms, webhooks, or manual request. The agent correlates telemetry, identifies root cause, and recommends remediation.
2. **Evaluations** -- Proactive prevention. The agent reviews past incidents and system state to identify potential issues before they cause outages.
3. **On-demand SRE tasks** -- Interactive chat for ad-hoc operational questions like "Why is my Lambda cold-starting?" or "What changed in this service last week?"

---

### Q: How does DevOps Agent actually "investigate" an incident?

**A:** The agent follows an autonomous investigation loop:

1. Receives a trigger (alarm, webhook, manual)
2. Queries relevant telemetry -- metrics, logs, traces, deployment history
3. Correlates signals across services and time windows
4. Forms and tests hypotheses (e.g., "did a deployment coincide with the error spike?")
5. Identifies root cause with supporting evidence
6. Recommends remediation steps (with agent-ready implementation specs)
7. Logs every reasoning step in a detailed investigation journal for auditability

---

### Q: Does DevOps Agent take automated remediation actions?

**A:** Currently, DevOps Agent focuses on **investigation and recommendation**. It identifies root cause and provides actionable remediation steps (including agent-ready instructions that could be executed by another agent), but it does not autonomously modify your infrastructure. This is a deliberate design choice for safety in production environments.

---

### Q: What foundation models power DevOps Agent?

**A:** DevOps Agent is powered by Amazon Bedrock foundation models. AWS does not publicly disclose the specific model(s) used internally, but the service leverages frontier-class models optimized for operational reasoning. Customer content is never used to train these models.

---

## 2. Architecture & Agent Spaces

### Q: What is an Agent Space?

**A:** An Agent Space is a **logical container that defines the scope and configuration for an individual agent instance**. Think of it as the agent's "workspace" -- it defines:

- Which AWS accounts and regions the agent can access
- Which third-party tools are connected (Datadog, Slack, GitHub, etc.)
- IAM roles that control permission boundaries
- Team or service ownership alignment

Multiple Agent Spaces can be created to match team structures or service boundaries.

---

### Q: How does the agent discover my resources?

**A:** DevOps Agent uses **Application Mapping** -- an automatic discovery feature that identifies applications, component services, and resources. It creates a dynamic, continuously updated topology by correlating live resource maps with telemetry, code, and deployment data. You can also configure tag-based discovery (e.g., `devopsagent=true`) to scope which resources the agent monitors.

---

### Q: Can one Agent Space span multiple AWS accounts?

**A:** Yes. Agent Spaces support **multi-account access** through IAM role configuration. A single Agent Space can retrieve operational data from multiple AWS Regions across all AWS accounts that have been granted access. This is how enterprise customers like CBA (1,700+ accounts) and United Airlines (500+ accounts) use the service.

---

### Q: Where is my data stored?

**A:** Data is stored in the **region where the Agent Space is created**. The agent can retrieve operational data from other regions, but investigation journals, configuration, and results are persisted in the Agent Space's home region.

---

### Q: How many Agent Spaces can I create?

**A:** The free trial includes up to 10 Agent Spaces. For GA, specific limits are not publicly documented but are expected to scale with enterprise needs. Contact your AWS account team for limit increases.

---

## 3. Capabilities & Supported Services

### Q: Which AWS services does DevOps Agent support?

**A:** DevOps Agent works with the broad AWS ecosystem. Demonstrated capabilities include:

| Service Category | Services |
|-----------------|----------|
| Compute | EC2, Lambda, ECS, EKS |
| Networking | VPC, ALB/NLB, Route53, VPN |
| Database | RDS, DynamoDB, Aurora |
| Storage | S3, EBS |
| CI/CD | CodePipeline, CodeBuild, CodeDeploy |
| Orchestration | Step Functions, EventBridge |
| Monitoring | CloudWatch (Metrics, Logs, Alarms, X-Ray) |
| Security | IAM, Inspector, CloudTrail |
| Infrastructure | CloudFormation |
| Messaging | SQS, SNS |
| API | API Gateway |

The service is designed to be **extensible** -- anything not natively supported can be integrated via MCP servers.

---

### Q: What telemetry sources can the agent access?

**A:** The agent queries:

- **CloudWatch Metrics** -- service and custom metrics
- **CloudWatch Logs** -- via Logs Insights queries
- **CloudWatch Alarms** -- correlated alarm state
- **Traces** -- distributed tracing (X-Ray)
- **CloudTrail** -- API activity and configuration changes
- **Deployment data** -- code diffs, deployment history
- **Code repositories** -- PR diffs, commit history
- **Third-party observability** -- Datadog, Dynatrace, New Relic, Splunk, Grafana, Prometheus

---

### Q: Can DevOps Agent analyze application logs, not just infrastructure?

**A:** Yes. The agent queries CloudWatch Logs using Logs Insights, which means any log data sent to CloudWatch (application logs, Lambda execution logs, container stdout/stderr) is searchable. It can also query third-party log platforms like Splunk and Datadog for application-level telemetry.

---

### Q: Does it support Kubernetes/EKS workloads?

**A:** Yes. DevOps Agent can investigate EKS cluster issues including add-on failures, pod health, node status, and container performance. It correlates Kubernetes events with CloudWatch Container Insights metrics and logs.

---

### Q: Can it read my source code to understand application behavior?

**A:** Yes. With GitHub, GitLab, or Azure DevOps integration, the agent can access code repositories, review recent commits, and correlate code changes with operational issues. This is particularly powerful for identifying deployment-induced regressions.

---

## 4. Integrations & Extensibility

### Q: What third-party integrations are available?

**A:**

| Category | Integrations |
|----------|-------------|
| Observability | Datadog, Dynatrace, New Relic, Splunk, Grafana, Prometheus |
| Code & CI/CD | GitHub, GitLab, Azure DevOps |
| Ticketing | ServiceNow, PagerDuty |
| Collaboration | Slack |
| Custom | MCP (Model Context Protocol) servers |

---

### Q: How does the Slack integration work?

**A:** You can interact with DevOps Agent directly in Slack channels. When an alarm fires, the agent can post its investigation findings to a designated channel. Team members can also ask the agent questions directly in Slack (on-demand SRE tasks) without switching to the AWS console.

---

### Q: What are MCP servers and why do they matter?

**A:** MCP (Model Context Protocol) servers are a standard for connecting AI agents to external tools and data sources. DevOps Agent supports both **private** and **remote** MCP servers, allowing you to:

- Connect to proprietary internal systems
- Query on-premises databases
- Access custom monitoring platforms
- Integrate with internal runbooks (e.g., Confluence)
- Extend the agent's capabilities beyond AWS-native services

This is critical for enterprises with hybrid environments or custom tooling.

---

### Q: Can DevOps Agent create tickets in ServiceNow or PagerDuty?

**A:** Yes. The agent integrates with ServiceNow and PagerDuty for incident management workflows. It can also create AWS Support cases directly from an investigation with one click, including full investigation context.

---

### Q: Can I trigger investigations from custom monitoring tools?

**A:** Yes. DevOps Agent supports **webhooks** as event sources. Any system that can send an HTTP webhook (custom monitoring, third-party alerting, CI/CD pipelines) can trigger an investigation.

---

## 5. Security & Compliance

### Q: Is my data used to train AI models?

**A:** **No.** AWS explicitly states that customer content is NOT used to train the underlying foundation models. Your operational data, logs, and investigation results remain private to your account.

---

### Q: How is data encrypted?

**A:** 
- **At rest:** AES-256 encryption with AWS-managed keys
- **Customer Managed Keys (CMK):** Supported for organizations requiring key control
- **In transit:** Standard AWS TLS encryption

---

### Q: How do I audit what the agent does?

**A:** Two mechanisms:

1. **Investigation Journals** -- Every reasoning step, query, and conclusion is logged in a detailed journal visible to operators
2. **AWS CloudTrail** -- All DevOps Agent API activities are automatically captured in CloudTrail for compliance and audit trails

---

### Q: What IAM permissions does the agent need?

**A:** The agent operates under IAM roles configured within each Agent Space. You define the scope -- it can only access what you explicitly grant. Best practice is to follow least-privilege principles:

- Read-only access to CloudWatch (metrics, logs, alarms)
- Read-only access to CloudTrail
- Read-only access to service-specific APIs (describe/list calls)
- No write/modify permissions needed for investigation

---

### Q: Can I restrict the agent to specific resources or accounts?

**A:** Yes. Agent Spaces provide isolation boundaries. You can:
- Create separate Agent Spaces per team, service, or environment
- Scope IAM roles to specific resource ARNs
- Use tag-based filtering to limit resource discovery
- Separate production vs. non-production investigations

---

### Q: Is DevOps Agent SOC2/HIPAA/FedRAMP compliant?

**A:** DevOps Agent inherits AWS's compliance certifications for the underlying infrastructure. Specific compliance attestations for the DevOps Agent service itself should be confirmed with your AWS account team, as these may vary by region and evolve post-GA.

---

## 6. Pricing & Cost

### Q: How is DevOps Agent priced?

**A:** Pay-as-you-go at **$0.0083 per agent-second** (approximately $0.50/minute or ~$30/hour of active investigation). You are only charged when the agent is actively working -- no charges when idle.

---

### Q: What does a typical monthly bill look like?

**A:**

| Team Size | Usage Pattern | Estimated Monthly Cost |
|-----------|--------------|----------------------|
| Small (5 engineers) | 10 investigations/month, 8 min avg | ~$40 |
| Medium (20 engineers) | 80 investigations + 100 chats/month | ~$344 |
| Enterprise (50+ engineers) | 500 incidents + 40 evaluations/month | ~$2,291 |

---

### Q: Are there additional charges beyond the agent-second rate?

**A:** Yes. Connected AWS services bill separately at standard rates:
- CloudWatch Logs Insights queries
- CloudWatch metric retrievals
- X-Ray trace retrievals
- CloudTrail data events (if enabled)

These are typically small relative to the agent-second charges.

---

### Q: Is there a free trial?

**A:** Yes. New DevOps Agent customers get a **2-month free trial** including:
- Up to 10 Agent Spaces
- 20 hours of investigations
- 15 hours of evaluations
- 20 hours of on-demand SRE tasks

---

### Q: How does the AWS Support credit work?

**A:** Monthly credits are applied based on your support tier and prior month's support charges:

| Support Tier | Credit Rate |
|-------------|-------------|
| Unified Operations | 100% |
| Enterprise Support | 75% |
| Business Support+ | 30% |

Credits expire monthly if unused. This effectively reduces or eliminates the cost for many Enterprise Support customers.

---

### Q: How does this compare to hiring an additional SRE?

**A:** A mid-level SRE costs $150K-$200K/year fully loaded. DevOps Agent at enterprise usage levels (~$2,300/month = ~$27,600/year) is roughly 15-18% of a single SRE's cost while providing 24/7 availability. Most customers position it as augmenting their existing team rather than replacing headcount.

---

## 7. Comparison with Other AWS Services

### Q: How is DevOps Agent different from Amazon Q Developer?

**A:**

| Aspect | DevOps Agent | Amazon Q Developer |
|--------|-------------|-------------------|
| Focus | Operations & incident management | Code development & IDE |
| Primary Users | SREs, DevOps, platform engineers | Software developers |
| Key Actions | Investigate incidents, correlate telemetry, RCA | Code suggestions, vulnerability scanning, transformation |
| Environment | Production infrastructure | IDE, console, CLI |
| Scope | Multi-cloud + on-premises | AWS-centric development |
| Trigger | Alarms, webhooks, manual | Developer queries, code context |

They are complementary -- Q Developer helps you write code, DevOps Agent helps you operate what you deployed.

---

### Q: How does it differ from CloudWatch Investigations?

**A:**

| Aspect | DevOps Agent | CloudWatch Investigations |
|--------|-------------|--------------------------|
| Scope | Multi-cloud, on-premises, third-party tools | AWS CloudWatch only |
| Cost | $0.0083/agent-second | No additional cost (included with CloudWatch) |
| Depth | Full autonomous investigation with RCA | Accelerated investigation within CloudWatch |
| Integrations | Slack, ServiceNow, GitHub, Datadog, etc. | CloudWatch ecosystem |
| Proactive | Yes (Evaluations mode) | No |

Use CloudWatch Investigations for quick AWS-only triage; use DevOps Agent for deep cross-service, cross-platform investigations.

---

### Q: Does DevOps Agent replace our existing monitoring tools?

**A:** No. DevOps Agent **consumes** telemetry from your existing tools -- it doesn't replace them. You still need CloudWatch, Datadog, or whatever observability stack you use. DevOps Agent adds an AI reasoning layer on top that correlates signals and identifies root causes faster than humans manually querying dashboards.

---

### Q: How does it compare to PagerDuty's AI features or Datadog's Watchdog?

**A:** Key differentiators:
- **Breadth:** DevOps Agent correlates across observability platforms, code repos, and AWS service APIs simultaneously
- **Depth:** It performs multi-step reasoning (not just anomaly detection) -- forming and testing hypotheses
- **AWS-native context:** Deep understanding of AWS service interactions, IAM, networking, and deployment patterns
- **Extensibility:** MCP servers allow custom integrations without vendor lock-in on the observability side

PagerDuty/Datadog AI features are complementary -- DevOps Agent can consume their data while adding deeper investigation capabilities.

---

## 8. Multi-Account & Enterprise

### Q: How do large enterprises use DevOps Agent?

**A:** Enterprise customers typically:
1. Create Agent Spaces aligned with service teams or business units
2. Configure cross-account IAM roles spanning hundreds of accounts
3. Integrate with existing incident management (ServiceNow, PagerDuty)
4. Connect to their observability stack (Datadog/Splunk alongside CloudWatch)
5. Use Slack for real-time collaboration with the agent

Examples: CBA (1,700+ accounts), United Airlines (500+ accounts), Rapyder (500+ accounts).

---

### Q: Can we use AWS Organizations with DevOps Agent?

**A:** Yes. Agent Spaces integrate with multi-account setups. You configure cross-account IAM roles that the Agent Space assumes to access resources in member accounts. This works naturally with AWS Organizations structure.

---

### Q: How do we handle different environments (dev/staging/prod)?

**A:** Best practice is to create **separate Agent Spaces** per environment:
- Prod Agent Space with full alerting and investigation triggers
- Staging Agent Space for pre-production validation
- Dev Agent Space for testing and familiarization

This ensures production investigations aren't polluted with dev noise, and permissions are properly scoped.

---

### Q: Can multiple team members interact with the same investigation?

**A:** Yes. Investigations are visible to all users with access to the Agent Space. Via Slack integration, entire teams can follow along and ask follow-up questions during an active investigation.

---

## 9. Setup & Prerequisites

### Q: What do I need to get started?

**A:** Minimum requirements:
1. AWS Account with administrator access
2. IAM roles for the Agent Space (read-only access to telemetry and services)
3. At least one trigger source (CloudWatch Alarm, webhook, or manual)

Optional but recommended:
- Third-party tool credentials (Datadog, Slack, GitHub)
- CloudTrail enabled for configuration change tracking
- X-Ray tracing enabled for distributed tracing
- Code repository connection for deployment correlation

---

### Q: How long does initial setup take?

**A:** Basic setup (Agent Space + CloudWatch integration): **15-30 minutes**
Full setup (multi-account + third-party integrations): **1-2 hours**
Enterprise deployment (Organizations-wide, multiple spaces): **1-2 days**

---

### Q: Do I need to instrument my application differently?

**A:** No. DevOps Agent works with your **existing telemetry**. If you already send logs to CloudWatch, have CloudWatch Alarms configured, and use standard AWS services, the agent can investigate immediately. Better instrumentation (X-Ray tracing, structured logs, custom metrics) gives the agent more signal to work with, but isn't required.

---

### Q: Which regions is DevOps Agent available in?

**A:** DevOps Agent is available in major AWS regions. The specific list should be checked on the AWS Regional Services page, as availability expands over time. The Agent Space can retrieve data from accounts in any region regardless of where the space itself is created.

---

## 10. Workshop-Specific Questions

### Q: Why does this workshop use tag-based discovery (`devopsagent=true`)?

**A:** Tag-based discovery is the recommended approach for scoping Agent Spaces to specific resources. By tagging workshop resources with `devopsagent=true`, the agent discovers only the relevant infrastructure without being distracted by other resources in the account. This mirrors production best practices where you'd tag resources by service or team ownership.

---

### Q: In Lab 1 (Build Failure / Lambda Timeout), how quickly does DevOps Agent identify the root cause?

**A:** Typically within **2-5 minutes** of the alarm firing. The agent:
1. Receives the alarm trigger
2. Queries CloudWatch Logs for the relevant CodeBuild/Lambda log group
3. Identifies the error pattern (pip failure / timeout)
4. Correlates with recent changes (source artifact / configuration)
5. Presents root cause with evidence

This compares to **15-60 minutes** for manual investigation depending on engineer experience.

---

### Q: For the CI/CD workshop Lab 5 (IAM Permission), how does the agent cross service boundaries?

**A:** This is one of the most powerful demonstrations. The agent:
1. Sees CodeBuild failure with generic "AccessDenied" error
2. Queries CloudTrail for recent IAM policy changes
3. Identifies the `PutRolePolicy` event that added the S3 Deny
4. Correlates the timeline: policy change happened before build failure
5. Presents the specific IAM policy statement causing the issue

Manual investigation of IAM issues often takes **hours** because engineers check the wrong service first.

---

### Q: For the Serverless workshop Lab 5 (EventBridge Misconfig), how does the agent detect a "silent failure"?

**A:** Silent failures are the hardest to detect. The agent:
1. Notices absence of expected downstream events (no SNS messages)
2. Checks EventBridge rule configuration and finds pattern mismatch
3. Compares current rule pattern (`order.service.v2`) against actual event source (`order.service`)
4. Correlates with CloudTrail showing the `PutRule` API call that changed the pattern
5. Identifies the discrepancy as root cause

This demonstrates the agent's ability to detect **absence of expected behavior**, not just presence of errors.

---

### Q: Can the workshop labs run simultaneously?

**A:** No. Labs should be run sequentially with rollback between each one. Each lab modifies the stack's operational state, and running multiple simultaneously would create confounding signals that make investigation results unclear. Always run `rollback.sh` before starting the next lab.

---

### Q: Why do some labs require traffic generation?

**A:** Labs 3-4 (CI/CD) and all serverless labs need traffic because:
- CloudWatch Alarms require data points to evaluate against thresholds
- Without traffic, metrics remain in `INSUFFICIENT_DATA` state
- The `generate-traffic.sh` script creates realistic load patterns that trigger alarm thresholds within 2-3 minutes

---

### Q: What's the cost to run this workshop?

**A:**

| Workshop | Cost Driver | Rate |
|----------|------------|------|
| Serverless | DynamoDB provisioned capacity | ~$1-2/hour |
| CI/CD Pipeline | 2x EC2 t3.micro + ALB | ~$2-3/hour |
| **Both** | Combined | **~$3-5/hour** |

Run `cleanup.sh` immediately after the workshop to avoid ongoing charges. Total cost for a 2-hour workshop session: ~$6-10.

---

### Q: Why does the CI/CD workshop use S3 as pipeline source instead of CodeCommit?

**A:** CodeCommit was deprecated by AWS in July 2024 (no new accounts can use it). The workshop uses S3 with versioning as the pipeline source, which is the recommended alternative for demos and workshops. It also simplifies the lab injection scripts -- uploading a modified `app.zip` triggers the pipeline automatically.

---

## 11. Limitations & Edge Cases

### Q: What can DevOps Agent NOT do?

**A:**
- **Cannot modify infrastructure** -- investigation and recommendation only, no automated remediation
- **Cannot access resources outside configured IAM scope** -- by design for security
- **Limited by telemetry available** -- if logs aren't sent to CloudWatch (or integrated tool), the agent can't analyze them
- **Not real-time streaming** -- queries telemetry in response to triggers, not continuous monitoring
- **No on-premises infrastructure discovery** -- requires explicit MCP server integration for non-AWS resources

---

### Q: What if my logs aren't in CloudWatch?

**A:** You have two options:
1. **Third-party integration** -- Connect Datadog, Splunk, New Relic, etc. directly to the Agent Space
2. **MCP server** -- Build a custom MCP server that exposes your log platform's API to the agent

The agent is most effective when it can access comprehensive telemetry. Log gaps reduce investigation accuracy.

---

### Q: Can DevOps Agent investigate issues in real-time during an ongoing incident?

**A:** Yes. You can trigger an investigation at any time -- during an active incident, after the fact, or proactively. The agent queries the current state of metrics, logs, and alarms. For ongoing incidents, it can be re-queried as new data becomes available.

---

### Q: What happens if the agent gives a wrong root cause?

**A:** The investigation journal provides full transparency into the agent's reasoning. If the root cause is incorrect, you can:
1. Review the journal to understand why the agent reached that conclusion
2. Provide additional context via chat (on-demand SRE task mode)
3. The agent learns from past investigations over time (continuous learning feature)

False positives decrease as the agent builds context about your environment through repeated investigations.

---

### Q: Does DevOps Agent work with serverless-only architectures (no EC2)?

**A:** Absolutely. The serverless workshop in this demo is entirely serverless (Lambda, API Gateway, Step Functions, DynamoDB, EventBridge). DevOps Agent works equally well with:
- Pure serverless
- Container-based (ECS/EKS)
- EC2-based
- Hybrid architectures

---

### Q: What about containers running on Fargate (no EC2 access)?

**A:** Fully supported. The agent accesses container telemetry through CloudWatch Container Insights, ECS/EKS APIs, and log groups. It doesn't need SSH/SSM access to instances -- it works at the API and telemetry layer.

---

## 12. Customer Success Stories

### Q: Who is using DevOps Agent in production?

**A:** Notable GA and preview customers:

| Customer | Scale | Result |
|----------|-------|--------|
| Western Governors University | Education | 77% MTTR reduction (2 hours to 28 minutes) |
| Commonwealth Bank of Australia | 1,700+ AWS accounts | Root cause in under 15 minutes |
| Deriv | FinTech | 40% MTTR reduction |
| RMIT University | Education | 4-7 hours reduced to under 30 minutes |
| Zenchef | SaaS | 75% investigation time reduction |
| United Airlines | 500+ accounts | Enterprise-scale operations |
| T-Mobile | Telecom | Multi-cloud with Splunk integration |
| Axrail (MSP) | Managed Services | 100% root cause accuracy, 50% MTTR reduction |
| Megazone Cloud (MSP) | Managed Services | 7-10x improvement in investigation time |

---

### Q: What's the typical MTTR improvement?

**A:** Based on public case studies: **40-77% reduction in Mean Time to Resolution**. The median improvement is approximately 60-70% reduction. Most dramatic improvements are seen with:
- Cross-service issues (IAM + compute + networking)
- Silent failures (no obvious error, requires correlation)
- Off-hours incidents (no experienced engineer available)

---

### Q: Are MSPs/partners using this for their customers?

**A:** Yes. MSPs are a strong use case:
- **Axrail** manages customer environments with DevOps Agent, achieving 100% root cause accuracy
- **Rapyder** (500+ accounts) uses it across their managed services portfolio  
- **Megazone Cloud** reported 7-10x faster investigations for their customers
- **Xtremax** uses it for multi-account management

The pay-per-use model makes it cost-effective for MSPs managing many accounts with variable incident volumes.

---

## Quick Reference Card

| Topic | Key Answer |
|-------|-----------|
| What is it? | Autonomous AI operations agent for incident investigation |
| GA Status | Generally Available |
| Pricing | $0.0083/agent-second (~$0.50/min) |
| Free Trial | 2 months, 20h investigations + 15h evaluations + 20h SRE tasks |
| Data Training | Customer data is NEVER used for model training |
| Multi-cloud | Yes (via third-party integrations + MCP servers) |
| Automated Remediation | No -- recommendation only (by design) |
| Key Differentiator | Autonomous multi-step reasoning across service boundaries |
| Typical MTTR Improvement | 40-77% reduction |
| Setup Time | 15-30 minutes (basic), 1-2 hours (full) |
| Workshop Cost | ~$3-5/hour for both demos combined |
