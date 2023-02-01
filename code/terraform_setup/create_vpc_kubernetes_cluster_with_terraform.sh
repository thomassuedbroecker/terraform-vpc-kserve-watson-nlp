#!/bin/bash

# **************** Global variables
source ./.env

#export TF_LOG=debug
export TF_VAR_flavor="bx2.4x16"
export TF_VAR_worker_count="2"
export TF_VAR_kubernetes_pricing="tiered-pricing"
export TF_VAR_resource_group=$GROUP
export TF_VAR_vpc_name="watson-nlp-kserve-tsued"
export TF_VAR_region=$REGION
export TF_VAR_kube_version="1.25.6"
export TF_VAR_cluster_name="watson-nlp-kserve-tsued"

# **************** logon with IBM Cloud CLI **************** 

echo "*********************************"
echo ""
echo "1. Logon with IBM Cloud CLI "
ibmcloud login --apikey $IC_API_KEY
ibmcloud resource groups
ibmcloud resource group-create $REGION
ibmcloud target -r $REGION
ibmcloud target -g $GROUP
ibmcloud plugin update
ibmcloud plugin list
ibmcloud is target --gen 2

# **************** install needed plugins **************** 
#ibmcloud plugin install vpc-infrastructure
#ibmcloud plugin install container-service

# **************** init **************** 

echo "*********************************"
echo ""
echo "2. Initialize Terraform on IBM Cloud"
terraform init

# **************** plan **************** 

echo "*********************************"
echo ""
echo "3. Generate a Terraform on IBM Cloud execution plan for the VPC infrastructure resources"
terraform plan

# **************** apply *************** 

echo "*********************************"
echo ""
echo "4. Apply a the Terraform on IBM Cloud execution plan for the VPC infrastructure resources"
terraform apply

echo "*********************************"
echo ""
echo "Verify the setup with the IBM Cloud CLI"

ibmcloud is vpcs
ibmcloud is subnets
ibmcloud is security-groups 
ibmcloud is keys
ibmcloud ks cluster ls

echo "*********************************"
echo ""
echo "5. Verify the created VPC instructure on IBM Cloud: https://cloud.ibm.com/vpc-ext/vpcLayout"
read ANYKEY

echo "*********************************"
echo ""
echo "6. Verify the created Kubernetes Cluster instance on IBM Cloud: https://cloud.ibm.com/kubernetes/clusters"
read ANYKEY

# **************** destroy ************* 
echo "*********************************"
echo ""
echo "7. Remove VPC infrastructure resources"
#terraform destroy
