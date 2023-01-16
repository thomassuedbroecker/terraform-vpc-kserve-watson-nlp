#!/bin/bash

# **************** Global variables
source ./.env

export HELM_RELASE_NAME=watson-nlp-kserve
export STORAGE_CONFIG="storage-config"
export MESH_NAMESPACE="modelmesh-serving"
export DEFAULT_NAMESPACE="default"

# **********************************************************************************
# Functions definition
# **********************************************************************************

function loginIBMCloud () {
    
    echo ""
    echo "*********************"
    echo "loginIBMCloud"
    echo "*********************"
    echo ""

    ibmcloud login --apikey $IC_API_KEY
    ibmcloud target -r $REGION
    ibmcloud target -g $GROUP
}

function connectToCluster () {

    echo ""
    echo "*********************"
    echo "connectToCluster"
    echo "*********************"
    echo ""

    ibmcloud ks cluster config -c $CLUSTER_ID
}

function createDockerCustomConfigFile () {

    echo ""
    echo "*********************"
    echo "createDockerCustomConfigFile"
    echo "*********************"
    echo ""

    sed "s+IBM_ENTITLEMENT_KEY+$IBM_ENTITLEMENT_KEY+g;s+IBM_ENTITLEMENT_EMAIL+$IBM_ENTITLEMENT_EMAIL+g" "$(pwd)/custom_config.json_template" > "$(pwd)/custom_config.json"
    IBM_ENTITLEMENT_SECRET=$(base64 -i "$(pwd)/custom_config.json")
    echo "IBM_ENTITLEMENT_SECRET: $IBM_ENTITLEMENT_SECRET"

    sed "s+IBM_ENTITLEMENT_SECRET+$IBM_ENTITLEMENT_SECRET+g" $(pwd)/charts/watson-nlp-kserve/values.yaml_template > $(pwd)/charts/watson-nlp-kserve/values.yaml
    cat $(pwd)/charts/watson-nlp-kserve/values.yaml
}

function installHelmChart () {

    echo ""
    echo "*********************"
    echo "installHelmChart"
    echo "*********************"
    echo ""

    TEMP_PATH_ROOT=$(pwd)
    cd $TEMP_PATH_ROOT/charts
    TEMP_PATH_EXECUTION=$(pwd)
    
    helm dependency update ./watson-nlp-kserve/
    helm install --dry-run --debug helm-test ./watson-nlp-kserve/

    helm lint
    helm install $HELM_RELASE_NAME ./watson-nlp-kserve

    kubectl patch serviceaccount default -p '{"imagePullSecrets": [{"name": "ibm-entitlement-key"}]}' -n $MESH_NAMESPACE
    kubectl patch serviceaccount modelmesh -p '{"imagePullSecrets": [{"name": "ibm-entitlement-key"}]}' -n $MESH_NAMESPACE
    kubectl patch serviceaccount modelmesh-controller -p '{"imagePullSecrets": [{"name": "ibm-entitlement-key"}]}' -n $MESH_NAMESPACE

    # Ensure the changes are applied
    # Restart the model controller
    echo "Scale down"
    kubectl scale deployment/modelmesh-controller --replicas=0 --all -n $MESH_NAMESPACE
    sleep 10
    echo "Scale up"
    kubectl scale deployment/modelmesh-controller --replicas=1 --all -n $MESH_NAMESPACE
    
    verifyPod
    verifyServingruntime

    kubectl get servingruntimes -n $MESH_NAMESPACE | grep watson-nlp-runtime  
    kubectl get inferenceservice -n $MESH_NAMESPACE
        
    echo ""
    echo "Verify output and press any key to move on:"
    echo ""

    read ANY_VALUE

    cd $TEMP_PATH_ROOT
}

function verifyMinioLoadbalancer () {

    echo ""
    echo "*********************"
    echo "verifyMinioLoadbalancer"
    echo "this could take up to 10 min"
    echo "*********************"
    echo ""

    verifyLoadbalancer

    TEMPFILE_1=tmp-storage-config-extract-01.json
    TEMPFILE_2=tmp-storage-config-extract-02.json
    SERVICE=minio-frontend-vpc-nlb

    EXTERNAL_IP=$(kubectl get svc $SERVICE -n $MESH_NAMESPACE | grep  $SERVICE | awk '{print $4;}')
    echo "EXTERNAL_IP: $EXTERNAL_IP"
    
    kubectl get secret $STORAGE_CONFIG --namespace=$MESH_NAMESPACE -o json > $(pwd)/$TEMPFILE_1
    cat $(pwd)/$TEMPFILE_1 | jq '.data.localMinIO' | sed 's/"//g' | base64 -d > $(pwd)/$TEMPFILE_2
    
    ACCESS_KEY_ID=$(cat $(pwd)/$TEMPFILE_2 | jq '.access_key_id' | sed 's/"//g')
    SECRET_KEY=$(cat $(pwd)/$TEMPFILE_2 | jq '.secret_access_key' | sed 's/"//g')

    echo "Access Key: $ACCESS_KEY_ID"
    echo "Secret Key: $SECRET_KEY"

    echo "Verify open minio"
    open "http://$EXTERNAL_IP:9000"

    echo ""
    echo "Verify output and press any key to move on:"
    echo ""

    read ANY_VALUE

    rm $(pwd)/$TEMPFILE_2
    rm $(pwd)/$TEMPFILE_1
}

function testModel () {

    echo ""
    echo "*********************"
    echo " testModel"
    echo "*********************"
    echo ""  

    verifyModelMeshLoadbalancer
    
    TEMP_PATH_ROOT=$(pwd)
    mkdir $TEMP_PATH_ROOT/tmp
    cd $TEMP_PATH_ROOT/tmp
    git clone https://github.com/IBM/ibm-watson-embed-clients
    cd $TEMP_PATH_ROOT/tmp/ibm-watson-embed-clients/watson_nlp/protos

    SERVICE=modelmash-vpc-nlb

    EXTERNAL_IP=$(kubectl get svc $SERVICE -n $MESH_NAMESPACE | grep  $SERVICE | awk '{print $4;}')
    echo "EXTERNAL_IP: $EXTERNAL_IP"

    grpcurl -plaintext -proto ./common-service.proto \
                             -H 'mm-vmodel-id: syntax-izumo-en' \
                             -d '{"parsers": ["TOKEN"],"rawDocument": {"text": "This is a test."}}' \
                             $EXTERNAL_IP:8033 watson.runtime.nlp.v1.NlpService.SyntaxPredict
    echo ""
    echo "Verify output and press any key to move on:"
    echo ""
    read ANY_VALUE

    cd $TEMP_PATH_ROOT
    rm -rf $TEMP_PATH_ROOT/tmp
}

function uninstallHelmChart () {

    echo ""
    echo "*********************"
    echo "uninstallHelmChart"
    echo "*********************"
    echo ""

    TEMP_PATH_ROOT=$(pwd)
    cd $TEMP_PATH_ROOT/charts
    TEMP_PATH_EXECUTION=$(pwd)

    helm uninstall $HELM_RELASE_NAME

    cd $TEMP_PATH_ROOT
}

# ********* internal functions **********

function verifyPod () {

    echo ""
    echo "*********************"
    echo "verifyPod could take up to 10 min"
    echo "*********************"
    echo ""

    export max_retrys=10
    j=0
    array=("modelmesh-controller")
    export STATUS_SUCCESS="1/1"
    for i in "${array[@]}"
        do
            echo ""
            echo "------------------------------------------------------------------------"
            echo "Check for ($i)"
            j=0
            export FIND=$i
            while :
            do     
            ((j++))
            echo "($j) from max retrys ($max_retrys)"
            STATUS_CHECK=$(kubectl get pods -n $MESH_NAMESPACE | grep $FIND | awk '{print $2;}')
            echo "Status: $STATUS_CHECK"
            if [ "$STATUS_CHECK" = "$STATUS_SUCCESS" ]; then
                    echo "$(date +'%F %H:%M:%S') Status: $FIND is created"
                    echo "------------------------------------------------------------------------"
                    break
                elif [[ $j -eq $max_retrys ]]; then
                    echo "$(date +'%F %H:%M:%S') Maybe a problem does exists!"
                    echo "------------------------------------------------------------------------"
                    exit 1              
                else
                    echo "$(date +'%F %H:%M:%S') Status: $FIND($STATUS_CHECK)"
                    echo "------------------------------------------------------------------------"
                fi
                sleep 30
            done
        done
}

function verifyLoadbalancer () {

    echo ""
    echo "*********************"
    echo "verifyLoadbalancer internal"
    echo "*********************"
    echo ""

    export max_retrys=10
    j=0
    array=("minio-frontend-vpc-nlb")
    export STATUS_SUCCESS=""
    for i in "${array[@]}"
        do
            echo ""
            echo "------------------------------------------------------------------------"
            echo "Check for $i"
            j=0
            export FIND=$i
            while :
            do      
            ((j++))
            echo "($j) from max retrys ($max_retrys)"
            STATUS_CHECK=$(kubectl get svc $FIND -n $MESH_NAMESPACE | grep $FIND | awk '{print $4;}')
            echo "Status: $STATUS_CHECK"
            if ([ "$STATUS_CHECK" != "$STATUS_SUCCESS" ] && [ "$STATUS_CHECK" != "<pending>" ]); then
                    echo "$(date +'%F %H:%M:%S') Status: $FIND is created ($STATUS_CHECK)"
                    echo "------------------------------------------------------------------------"
                    break
                elif [[ $j -eq $max_retrys ]]; then
                    echo "$(date +'%F %H:%M:%S') Maybe a problem does exists!"
                    echo "------------------------------------------------------------------------"
                    exit 1              
                else
                    echo "$(date +'%F %H:%M:%S') Status: $FIND($STATUS_CHECK)"
                    echo "------------------------------------------------------------------------"
                fi
                sleep 60
            done
        done
}

function verifyModelMeshLoadbalancer () {

    echo ""
    echo "*********************"
    echo " verifyModelMeshLoadbalancer internal"
    echo "*********************"
    echo ""

    export max_retrys=10
    j=0
    array=("modelmash-vpc-nlb")
    export STATUS_SUCCESS=""
    for i in "${array[@]}"
        do
            echo ""
            echo "------------------------------------------------------------------------"
            echo "Check for $i"
            j=0
            export FIND=$i
            while :
            do      
            ((j++))
            echo "($j) from max retrys ($max_retrys)"
            STATUS_CHECK=$(kubectl get svc $FIND -n $MESH_NAMESPACE | grep $FIND | awk '{print $4;}')
            echo "Status: $STATUS_CHECK"
            if ([ "$STATUS_CHECK" != "$STATUS_SUCCESS" ] && [ "$STATUS_CHECK" != "<pending>" ]); then
                    echo "$(date +'%F %H:%M:%S') Status: $FIND is created ($STATUS_CHECK)"
                    echo "------------------------------------------------------------------------"
                    break
                elif [[ $j -eq $max_retrys ]]; then
                    echo "$(date +'%F %H:%M:%S') Maybe a problem does exists!"
                    echo "------------------------------------------------------------------------"
                    exit 1              
                else
                    echo "$(date +'%F %H:%M:%S') Status: $FIND($STATUS_CHECK)"
                    echo "------------------------------------------------------------------------"
                fi
                sleep 60
            done
        done
}

function verifyServingruntime () {

    echo ""
    echo "*********************"
    echo "verifyServingruntime internal"
    echo "This can take up to 5 min, because"
    echo "of the scaling."
    echo "*********************"
    echo ""

    export max_retrys=20
    j=0
    array=("watson-nlp-runtime")
    export STATUS_SUCCESS="watson-nlp-runtime"
    for i in "${array[@]}"
        do
            echo ""
            echo "------------------------------------------------------------------------"
            echo "Check for $i"
            j=0
            export FIND=$i
            while :
            do    
            ((j++))
            echo "($j) from max retrys ($max_retrys)"
            STATUS_CHECK=$(kubectl get servingruntimes $FIND -n $MESH_NAMESPACE | grep $FIND | awk '{print $1;}')
            echo "Status: $STATUS_CHECK"
            if [ "$STATUS_CHECK" = "$STATUS_SUCCESS" ]; then
                    echo "$(date +'%F %H:%M:%S') Status: $FIND is created"
                    echo "------------------------------------------------------------------------"
                    break
                elif [[ $j -eq $max_retrys ]]; then
                    echo "$(date +'%F %H:%M:%S') Maybe a problem does exists!"
                    echo "------------------------------------------------------------------------"
                    exit 1              
                else
                    echo "$(date +'%F %H:%M:%S') Status: $FIND($STATUS_CHECK)"
                    echo "------------------------------------------------------------------------"
                fi
                sleep 20
            done
        done
}

#**********************************************************************************
# Execution
# *********************************************************************************

loginIBMCloud

connectToCluster

createDockerCustomConfigFile

installHelmChart

verifyMinioLoadbalancer

testModel

uninstallHelmChart
