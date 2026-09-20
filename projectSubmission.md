Trend Store — Jenkins CI/CD on AWS EKS

Project Overview

This project demonstrates an end-to-end DevOps deployment of the Trend Store application using Docker, Jenkins, Docker Hub, Terraform, Kubernetes, and Amazon EKS.

The application is containerized with Docker, pushed to Docker Hub by Jenkins, and automatically deployed to an Amazon EKS cluster. A Kubernetes LoadBalancer Service exposes the application through an AWS Elastic Load Balancer.

A GitHub webhook automatically triggers the Jenkins pipeline whenever code is pushed to the main branch.

Architecture

GitHub
  │
  │ Push Webhook
  ▼
Jenkins EC2 (t3.micro)
  │
  ├── Docker Build
  │
  ├── Docker Hub Push
  │
  └── AWS IAM Role
          │
          ▼
       Amazon EKS
          │
          ▼
   EKS Node (t3.small)
          │
          ▼
    Trend App Pod
          │
          ▼
 Kubernetes LoadBalancer
          │
          ▼
    AWS Load Balancer
          │
          ▼
       Browser

Technologies

GitHub

Jenkins

Jenkins Declarative Pipeline

Docker

Docker Hub

Terraform

Kubernetes

Amazon EKS

Amazon EC2

Amazon VPC

IAM

AWS Elastic Load Balancer

AWS CLI

kubectl

Nginx

Repository

GitHub:

https://github.com/s1u2n3/Sundar_TrendStore

Project Structure

Sundar_TrendStore/
├── dist/
├── terraform/
│   ├── main.tf
│   └── outputs.tf
├── K8s/
│   ├── deployment.yaml
│   └── service.yaml
├── dockerfile
├── Jenkinsfile
├── .dockerignore
├── .gitignore
└── README.md

The Kubernetes directory is named K8s. Linux is case-sensitive, so Jenkins uses K8s/....

1. Docker

The application is served using Nginx.

FROM nginx:alpine

COPY dist/ /usr/share/nginx/html/

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]

Local test:

docker build -t trend-app .
docker run -d -p 3000:80 --name trend-app-container trend-app

The application is available locally at:

http://localhost:3000

2. Docker Hub

Docker Hub repository:

sund123/trend-store-app

Image:

sund123/trend-store-app:latest

Jenkins credential:

dockerhub-creds

The Docker Hub access token is stored securely in Jenkins and is not committed to GitHub.

3. Terraform Infrastructure

Terraform provisions the AWS infrastructure.

VPC

VPC: trendstore-vpc

CIDR: 10.0.0.0/16

Internet Gateway: trendstore-igw

Public subnet: trendstore-public-subnet

Second public subnet: trendstore-public-subnet-2

Route table: trendstore-public-rt

Jenkins

EC2: trendstore-jenkins

Instance type: t3.micro

Security group: trendstore-jenkins-sg

IAM role: trendstore-jenkins-role

EKS

Cluster: trend-eks

Cluster IAM role: trendstore-eks-cluster-role

Node IAM role: trendstore-eks-node-role

Managed node group: trend-node-group

Worker type: t3.small

Desired nodes: 1

Minimum nodes: 1

Maximum nodes: 1

The Jenkins IAM role is authorized to access the EKS cluster through an EKS access entry and cluster access policy.

Terraform commands

terraform init
terraform fmt
terraform validate
terraform plan
terraform apply

4. Jenkins

Jenkins runs on the Terraform-created EC2 instance.

Configured components include:

Jenkins

Git

Docker

AWS CLI

kubectl

Docker Pipeline support

Kubernetes-related Jenkins plugins

GitHub integration

Jenkins has Docker access through the docker group.

AWS authentication uses the EC2 IAM role rather than static AWS access keys.

Verified with:

aws sts get-caller-identity

5. Jenkins Job

Job:

Trend-CI-CD

SCM:

Git

Repository:

https://github.com/s1u2n3/Sundar_TrendStore.git

Branch:

*/main

Script:

Jenkinsfile

GitHub repository is public, so no GitHub credential is required for checkout.

6. CI/CD Pipeline

The Jenkins Declarative Pipeline contains these stages:

Checkout

Checks out the main branch.

Build Docker Image

docker build -t sund123/trend-store-app:latest .

Login to Docker Hub

Uses the Jenkins dockerhub-creds credential.

Push Docker Image

docker push sund123/trend-store-app:latest

Deploy to EKS

aws eks update-kubeconfig   --region ap-south-1   --name trend-eks

kubectl apply -f K8s/deployment.yaml
kubectl apply -f K8s/service.yaml

kubectl rollout status deployment/trend-app --timeout=180s

7. Kubernetes Deployment

K8s/deployment.yaml deploys one application replica:

apiVersion: apps/v1
kind: Deployment
metadata:
  name: trend-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: trend-app
  template:
    metadata:
      labels:
        app: trend-app
    spec:
      containers:
        - name: trend-app
          image: sund123/trend-store-app:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "200m"
              memory: "128Mi"

8. Kubernetes Service

K8s/service.yaml exposes the application through an AWS Load Balancer:

apiVersion: v1
kind: Service
metadata:
  name: trend-app-service
spec:
  type: LoadBalancer
  selector:
    app: trend-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80

9. EKS Verification

EKS access was configured from Jenkins with:

aws eks update-kubeconfig   --region ap-south-1   --name trend-eks

Node verification:

kubectl get nodes

Application verification:

kubectl get pods
kubectl get pods -A

Service verification:

kubectl get svc

Final verified state:

EKS Node       → Ready
Trend Pod      → 1/1 Running
Service        → LoadBalancer
AWS LoadBalancer → Provisioned
Application    → Accessible externally

The deployed Trend application was successfully opened through the AWS Load Balancer.

The Load Balancer hostname observed during the completed deployment was:

a99dd7ee2079d4dff96549e4b8cf66e4-1222049691.ap-south-1.elb.amazonaws.com

10. GitHub Webhook

A GitHub webhook is configured for push events.

Jenkins trigger:

GitHub hook trigger for GITScm polling

Webhook endpoint:

http://<JENKINS_PUBLIC_IP>:8080/github-webhook/

The webhook was tested successfully: a push to main automatically triggered the Jenkins pipeline.

Automated flow:

Git Push
   ↓
GitHub Webhook
   ↓
Jenkins
   ↓
Docker Build
   ↓
Docker Hub Push
   ↓
EKS Deployment
   ↓
Application Update

11. Troubleshooting

Kubernetes Pod initially remained Pending

The initial t3.micro EKS worker had insufficient pod capacity/resources after the Kubernetes system components were scheduled. Kubernetes reported:

Too many pods
NodeHasInsufficientMemory
NodeHasInsufficientPID

The managed node group was changed to one t3.small worker:

desired = 1
min     = 1
max     = 1

After recreation of the node group, the application successfully reached:

1/1 Running

Kubernetes folder case

The repository uses:

K8s/

rather than k8s/. Linux is case-sensitive, so the Jenkinsfile correctly references:

kubectl apply -f K8s/deployment.yaml
kubectl apply -f K8s/service.yaml

12. Security

Docker Hub token is stored as a Jenkins credential.

AWS access uses the Jenkins EC2 IAM role.

No AWS access keys are stored in GitHub.

Terraform state files are excluded by .gitignore.

.env files are excluded.

Jenkins IAM permissions are broad for this assignment; production should use least-privilege policies.

Public Jenkins/SSH access was used for the assignment and should be restricted in production.

13. Submission Screenshots

Recommended evidence:

Terraform apply completed

AWS VPC

AWS subnets

Internet Gateway

Route table

Jenkins EC2

Jenkins security group

IAM roles

EKS cluster

EKS node group

kubectl get nodes

kubectl get pods

kubectl get svc

Trend Store application through Load Balancer

Successful Jenkins pipeline

GitHub webhook

Automatic Jenkins build after GitHub push

Successful EKS deployment

14. Useful Verification Commands

kubectl get nodes
kubectl get pods
kubectl get pods -A
kubectl get svc
kubectl rollout status deployment/trend-app
kubectl describe deployment trend-app
kubectl describe pod -l app=trend-app
kubectl get events --sort-by=.lastTimestamp

15. Final Result

The project successfully implements a complete automated CI/CD workflow:

GitHub
   ↓
GitHub Webhook
   ↓
Jenkins
   ↓
Docker Build
   ↓
Docker Hub
   ↓
Amazon EKS
   ↓
Kubernetes Deployment
   ↓
AWS Load Balancer
   ↓
Trend Store Application

Project status: Completed successfully.
