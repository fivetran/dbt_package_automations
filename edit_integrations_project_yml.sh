#!/bin/bash

# Arguments
PACKAGE_NAME=$1
DBT_PROJECT_FILE="../dbt_$PACKAGE_NAME/integration_tests/dbt_project.yml"

#!/bin/bash

# Check if the correct number of arguments are passed
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 package_name 'model1,model2,...'"
    exit 1
fi

# Arguments
PACKAGE_NAME=$1
MODELS_CSV=$2
DBT_PROJECT_FILE="../dbt_$PACKAGE_NAME/integration_tests/dbt_project.yml"

# Function to add a model to the dbt_project.yml
add_model() {
    local model=$1
    echo "    ${PACKAGE_NAME}_${model}_identifier: \"${model}_data\"" >> "$DBT_PROJECT_FILE"
}

# Check if 'vars' section already exists
if ! grep -q "vars:" "$DBT_PROJECT_FILE"; then
    echo "vars:" >> "$DBT_PROJECT_FILE"
fi

# Check if package section exists under 'vars'
if ! grep -q "  $PACKAGE_NAME:" "$DBT_PROJECT_FILE"; then
    echo "  $PACKAGE_NAME:" >> "$DBT_PROJECT_FILE"
fi

# Convert CSV string to newline separated and loop over each model
echo "$MODELS_CSV" | tr ',' '\n' | while read -r model; do
    if [ ! -z "$model" ]; then
        add_model "$model"
    fi
done

echo Updated integration_tests/dbt_project.yml with specific configs
