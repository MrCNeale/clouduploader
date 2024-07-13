#!/bin/bash

# Initialize variables
overwrite=false
generate_link=false
files=()

# Parse options
while getopts "ogf:" opt; do
    case $opt in
        o) overwrite=true ;;
        g) generate_link=true ;;
        f) IFS=',' read -ra files <<< "$OPTARG" ;;
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    esac
done

# Print the values (for testing purposes)
echo "overwrite: $overwrite"
echo "generate_link: $generate_link"
echo "files: ${files[@]}"

# function to  authenticate with SPN
authenticate_with_service_principal() {
	echo "Autheticating with Azure.."

	local app_id=$AZ_APP_ID 
	local password=$AZ_PASSWORD
	local tenant_id=$AZ_TENANT_ID 

    # Check variables exist
    if [[ -z "$app_id" || -z "$password" ||  -z "$tenant_id" ]]; then
        echo "Missing login details, please check environment variables"
        exit 1
    fi

    # Login with the service principal 
    az login --service-principal -u "$app_id" -p "$password" --tenant "$tenant_id" > /dev/null 2>&1
    if [ $? -ne 0 ]; then  
        echo "Authentication failed"
        exit 1
    fi 

}

upload_file_to_blob() {
    local file_location=$1
    local blob_container=clouduploader
    local blob_name=$(basename "$file_location")
    local storage_account=clouduploadercn 
    
	echo "Uploading file to Azure Blob Storage..." 

    # Capture the standard error output & upload the file

    if [ "$overwrite" = true ]; then
        error_message=$(az storage blob upload \
            --account-name "$storage_account" \
            --container-name "$blob_container" \
            --file "$file_location" \
            --name "$blob_name" \
            --overwrite \
            --auth-mode login 2>&1 >/dev/null) 
    else
        error_message=$(az storage blob upload \
            --account-name "$storage_account" \
            --container-name "$blob_container" \
            --file "$file_location" \
            --name "$blob_name" \
            --auth-mode login 2>&1 >/dev/null) 
    fi
        # Check the exit status of the previous command  

        if [ $? -ne 0 ]; then 
            echo "File upload failed"
            echo "Error: $error_message"
        else 
            if [[ "$generate_link" == true ]]; then

                shareable_link=$(generate_sas_url "$storage_account" "$blob_container" "$blob_name")
                echo "Shareble Link: $shareable_link"
            fi
        fi 
}

generate_sas_url() {
    local storage_account=$1
    local container_name=$2
    local blob_name=$3

    local sas_token=$(az storage blob generate-sas \
                      --account-name "$storage_account" \
                      --container-name "$container_name" \
                      --name "$blob_name" \
                      --permissions r \
                      --expiry $(date -u -d "1 day" '+%Y-%m-%dT%H:%MZ') \
		      --auth-mode login \
		      --as-user \
                      --output tsv 2>&1)

    if [ -z "$sas_token" ] || [[ $sas_token == *"ERROR"* ]];then
        echo "Failed to generate a shareable link for $blob_name.Error: $sas_token"        
	return 1
    fi

    echo "https://${storage_account}.blob.core.windows.net/${container_name}/${blob_name}?${sas_token}"
}

#Login with SPN first if not already connected
ACCOUNT_INFO=$(az account show 2> /dev/null)

if [[ -z "$ACCOUNT_INFO" ]]; then
    echo "Not connected to any Azure subscription."
    echo "attempting to login with SPN environment variables"
    authenticate_with_service_principal
else
    echo "Connected to Azure subscription:"
    echo "$ACCOUNT_INFO"
fi

#Loop around input variables and upload each one
for file in "${files[@]}"; do
    if [ -f $file ]; then
        upload_file_to_blob "$file"
    else
        echo "Error: File $file does not exist or is a directory"
    fi
done