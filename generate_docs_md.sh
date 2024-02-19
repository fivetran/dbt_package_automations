#!/bin/zsh

output_md="$1/models/docs.md"

# Remove the surrounding brackets and quotes from the fifth argument
table_string=$(echo $5 | tr -d '[]"' | tr -d "'")

# Split the string into an array
# In zsh, parentheses are used for array assignment
tables=(${(s:,:)table_string})

# Temporary file to hold unique columns
temp_file=$(mktemp /tmp/unique_columns.XXXXXX)

# Loop through each table in the array
for table in "${tables[@]}"; do
  # Debug: Show the cleaned table name
  echo "Generating $table docs"

  # Run the dbt command and clean up the output, then append to the temp file
  dbt run-operation dbt_package_automations.get_column_names_for_docs --args "{\"table_name\": \"$table\", \"schema_name\": \"$4\", \"database_name\":\"$3\", \"package_name\":\"$2\"}" | tail -n +4 | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}  //' >> "$output_md" >> "$temp_file"
done

# Sort the file, remove duplicates, and format as a Markdown list
awk '!seen[$0]++' "$temp_file" > "$output_md"

# Remove the temporary file
rm "$temp_file"

# Output the final path for confirmation
echo "Unique columns saved to $output_md"
