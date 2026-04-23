"""
Run dbt test scenarios from YAML configuration

This script automates running multiple dbt test scenarios with different variable configurations.
It loads test scenarios from a YAML file and runs dbt commands (deps, seed, compile, run, test)
for each scenario to ensure the dbt package works correctly under different conditions.
"""

import yaml
import subprocess
import sys
from pathlib import Path


def load_scenarios(config_file):
    """Load test scenarios from YAML file

    Returns the parsed YAML content containing:
    - schema_variable_name: The dbt variable name used for setting schema
    - test_scenarios: List of scenarios with different variable configurations
    """
    try:
        with open(config_file, 'r') as f:
            return yaml.safe_load(f)
    except yaml.YAMLError as e:
        print(f"Error: Malformed YAML in {config_file}")
        print(f"YAML parsing error: {e}")
        print("Fix: Check YAML syntax (indentation, colons, quotes)")
        print("Common issues:")
        print("  - Inconsistent indentation (mix of spaces/tabs)")
        print("  - Missing colons after keys")
        print("  - Unquoted strings with special characters")
        print("  - Missing quotes around string values")
        sys.exit(1)
    except Exception as e:
        print(f"Error: Could not read {config_file}")
        print(f"Error details: {e}")
        sys.exit(1)


def run_dbt_command(cmd, cwd=None):
    """Run a dbt command and handle errors with full output capture

    Args:
        cmd: List of command parts (e.g., ['dbt', 'run', '--target', 'dev'])
        cwd: Working directory to run command in (optional)

    Returns:
        True if command succeeded (return code 0)
        False if command failed (non-zero return code)
    """
    print(f"\n=== Running: {' '.join(cmd)}")

    # Capture stdout and stderr for error debugging
    result = subprocess.run(
        cmd,
        cwd=cwd,
        capture_output=True,  # Capture both stdout and stderr streams
        text=True             # Return strings instead of bytes
    )

    if result.returncode != 0:
        print(f"Command failed: {' '.join(cmd)}")
        print(f"Exit code: {result.returncode}")

        # Display actual dbt error messages instead of just "command failed"
        if result.stdout.strip():
            print("\n--- Command Output ---")
            print(result.stdout)

        if result.stderr.strip():
            print("\n--- Error Output ---")
            print(result.stderr)

        return False

    return True


def main():
    # === COMMAND LINE ARGUMENT VALIDATION ===
    # Script expects exactly 2 arguments: target (e.g., 'postgres', 'bigquery') and build_schema (schema name)
    if len(sys.argv) != 3:
        print("Usage: run_test_scenarios.py <target> <build_schema>")
        sys.exit(1)

    target = sys.argv[1]        # dbt target profile to use
    build_schema = sys.argv[2]  # Schema name where test data will be created

    # === CONFIGURATION FILE LOADING ===
    # Load test scenarios configuration from YAML file
    config_file = Path('ci/test_scenarios.yml')
    if not config_file.exists():
        # Provide helpful error message and example if config file is missing
        print(f"Error: {config_file} not found")
        print("Fix: Create a test_scenarios.yml file in the integration_tests/ci/ directory")
        print("Example content:")
        print("schema_variable_name: \"your_package_schema_variable\"")
        print("default_include_incremental: false  # Optional: whether default scenario should test incremental runs")
        print("test_scenarios:")
        print("  - name: \"warehouse validation\"  # Optional: custom scenario name (\"test:\" will be prepended)")
        print("    vars: {}")
        print("    include_incremental: false")
        print("Note: schema_variable_name should be the name of your dbt variable, not the schema itself")
        sys.exit(1)

    config = load_scenarios(config_file)

    # === SCHEMA VARIABLE VALIDATION ===
    # Extract the dbt variable name that controls which schema to use
    # This is the variable name (e.g., 'amazon_ads_schema'), not the actual schema value
    schema_var_name = config.get('schema_variable_name')
    if not schema_var_name:
        # Provide helpful error message if schema variable name is missing
        print("Error: schema_variable_name not found in test_scenarios.yml")
        print(f"Fix: Add the name of your dbt schema variable to {config_file}")
        print("Example:")
        print("schema_variable_name: \"amazon_ads_schema\"")
        print("default_include_incremental: false  # Optional: whether default scenario should test incremental runs")
        print("test_scenarios:")
        print("  - name: \"warehouse validation\"  # Optional: custom scenario name (\"test:\" will be prepended)")
        print("    vars: {}")
        print("    include_incremental: false")
        print("Note: This should be the name of the dbt variable you use to set the schema,")
        print("      not the schema name itself (e.g., use 'amazon_ads_schema', not 'my_schema')")
        sys.exit(1)

    print(f"\n=== Target: {target}")
    print(f"Schema variable: {schema_var_name} = {build_schema}")

    # === INITIAL DBT SETUP COMMANDS ===
    # These commands prepare the dbt environment before running test scenarios
    print(f"\n=== dbt setup ===")

    # Install dbt package dependencies from packages.yml
    # if not run_dbt_command(...): This checks if the command FAILED
    # run_dbt_command returns False when a command fails (non-zero exit code)
    # So "if not" means "if the command failed, then exit the script"
    if not run_dbt_command(['dbt', 'deps']):
        print("dbt deps failed")
        sys.exit(1)

    # Load seed data (CSV files) into the database with the specified schema
    # Format dbt variables as YAML: {variable_name: value}
    vars_yaml = f"{{{schema_var_name}: {build_schema}}}"
    if not run_dbt_command(['dbt', 'seed', '--target', target, '--full-refresh', '--vars', vars_yaml]):
        print("dbt seed failed")
        sys.exit(1)

    # Compile dbt models to verify SQL syntax without running them
    # This catches compilation errors early before attempting to run scenarios
    print(f"\n=== Test compile ===")
    compile_cmd = ['dbt', 'compile', '--target', target, '--full-refresh', '--vars', vars_yaml]
    if not run_dbt_command(compile_cmd):
        print("dbt compile failed")
        sys.exit(1)
    print(f"=== ✓ Successful compile")

    # === TEST SCENARIO EXECUTION FUNCTION ===
    # This nested function runs a single test scenario with specific variable configurations
    def run_scenario(scenario_vars, scenario_name, include_incremental=False):
        """
        Run a single test scenario with specified variables

        Args:
            scenario_vars: Dictionary of dbt variables for this scenario
            scenario_name: Human-readable name for logging
            include_incremental: Whether to test incremental runs after full refresh
        """
        print(f"\n=== Running {scenario_name} ===")

        # === VARIABLE PREPARATION ===
        # Merge scenario-specific variables with the schema variable
        vars_dict = scenario_vars.copy()
        vars_dict[schema_var_name] = build_schema

        # Convert Python dict to dbt YAML variable format: {key1: value1, key2: value2}
        vars_yaml_parts = []
        for key, value in vars_dict.items():
            vars_yaml_parts.append(f"{key}: {value}")
        vars_yaml = f"{{{', '.join(vars_yaml_parts)}}}"
        print(f"Variables: {vars_yaml}")
        print(f"Include incremental: {include_incremental}")

        # === FULL REFRESH RUN ===
        # Always start with a full refresh to ensure clean state
        # This rebuilds all models from scratch, ignoring any existing incremental state
        print(f"\n== Full refresh run ==")
        run_cmd_full = ['dbt', 'run', '--target', target, '--vars', vars_yaml, '--full-refresh']
        test_cmd = ['dbt', 'test', '--target', target, '--vars', vars_yaml]

        # Execute full refresh run and exit if it fails
        # if not run_dbt_command(...): means "if the command failed"
        if not run_dbt_command(run_cmd_full):
            print(f"dbt run (full refresh) failed for {scenario_name}")
            sys.exit(1)

        # Run tests to validate the data after full refresh
        if not run_dbt_command(test_cmd):
            print(f"dbt test failed for {scenario_name}")
            sys.exit(1)

        # === INCREMENTAL RUN (OPTIONAL) ===
        # Test incremental behavior if requested - this simulates subsequent runs
        # where only new/changed data is processed (important for incremental models)
        if include_incremental:
            print(f"\n== Incremental run ==")
            run_cmd_incremental = ['dbt', 'run', '--target', target, '--vars', vars_yaml]

            # Run without --full-refresh to test incremental logic
            if not run_dbt_command(run_cmd_incremental):
                print(f"dbt run (incremental) failed for {scenario_name}")
                sys.exit(1)

            # Validate that incremental run produced correct results
            if not run_dbt_command(test_cmd):
                print(f"dbt test (after incremental) failed for {scenario_name}")
                sys.exit(1)

    # === EXECUTE ALL TEST SCENARIOS ===

    # Run default scenario first (baseline test with no custom variables)
    # This ensures the package works with default settings before testing edge cases
    # Default scenario always has a fixed name since it represents the baseline with no variables
    default_include_incremental = config.get('default_include_incremental', False)
    run_scenario({}, "test: default", include_incremental=default_include_incremental)

    # Run additional test scenarios defined in the YAML configuration
    # Each scenario can have custom variables, names, and incremental testing settings
    for i, scenario in enumerate(config.get('test_scenarios', []), 2): # Start counter at 2 since default scenario is considered scenario 1
        # Check if scenario is allowed for this warehouse
        allowed_warehouses = scenario.get('warehouses', None)
        if allowed_warehouses and target not in allowed_warehouses:
            base_name = scenario.get('name', f'scenario {i}')
            print(f"\n=== Skipping test: {base_name} ===")
            print(f"Not configured for {target} (test only runs on: {', '.join(allowed_warehouses)})")
            continue

        scenario_vars = scenario.get('vars', {})  # Custom variables for this scenario
        include_incremental = scenario.get('include_incremental', False)  # Whether to test incremental runs
        # Add "test:" prefix to scenario name (avoid double "test" for default names)
        base_name = scenario.get('name', f'scenario {i}')  # Custom name or default without "test"
        scenario_name = f"test: {base_name}"
        run_scenario(scenario_vars, scenario_name, include_incremental)

    print("\n=== All test scenarios completed successfully! ===")


# === SCRIPT ENTRY POINT ===
# This ensures main() only runs when the script is executed directly
# (not when imported as a module by another Python script)
if __name__ == "__main__":
    main()