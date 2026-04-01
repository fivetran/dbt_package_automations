#!/usr/bin/env python3
"""
Run dbt test scenarios from YAML configuration
"""

import yaml
import json
import subprocess
import sys
import os
from pathlib import Path


def load_scenarios(config_file):
    """Load test scenarios from YAML file"""
    with open(config_file, 'r') as f:
        return yaml.safe_load(f)


def run_dbt_command(cmd, cwd=None):
    """Run a dbt command and handle errors"""
    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd)
    if result.returncode != 0:
        print(f"Command failed: {' '.join(cmd)}")
        return False
    return True


def main():
    if len(sys.argv) != 3:
        print("Usage: run_test_scenarios.py <target> <build_schema>")
        sys.exit(1)

    target = sys.argv[1]
    build_schema = sys.argv[2]

    # Load scenarios
    config_file = Path('ci/test_scenarios.yml')
    if not config_file.exists():
        print(f"Error: {config_file} not found")
        print("Fix: Create a test_scenarios.yml file in the integration_tests/ci/ directory")
        print("Example content:")
        print("schema_variable_name: \"your_package_schema_variable\"")
        print("test_scenarios:")
        print("  # Add test scenarios here")
        print("Note: schema_variable_name should be the name of your dbt variable, not the schema itself")
        sys.exit(1)

    config = load_scenarios(config_file)

    # Get the name of the dbt variable used to set schema
    schema_var_name = config.get('schema_variable_name')
    if not schema_var_name:
        print("Error: schema_variable_name not found in test_scenarios.yml")
        print(f"Fix: Add the name of your dbt schema variable to {config_file}")
        print("Example:")
        print("schema_variable_name: \"amazon_ads_schema\"")
        print("test_scenarios:")
        print("  # Your test scenarios here")
        print("Note: This should be the name of the dbt variable you use to set the schema,")
        print("      not the schema name itself (e.g., use 'amazon_ads_schema', not 'my_schema')")
        sys.exit(1)

    print(f"Running test scenarios for target: {target}")
    print(f"Schema variable: {schema_var_name} = {build_schema}")

    # Run initial dbt setup commands
    print(f"\n=== Initial dbt setup ===")

    # dbt deps
    if not run_dbt_command(['dbt', 'deps']):
        print("dbt deps failed")
        sys.exit(1)

    # dbt seed with schema variables
    vars_yaml = f"{{{schema_var_name}: {build_schema}}}"
    if not run_dbt_command(['dbt', 'seed', '--target', target, '--full-refresh', '--vars', vars_yaml]):
        print("dbt seed failed")
        sys.exit(1)

    # dbt compile with schema variables
    print(f"=== Running dbt compile ===")
    compile_cmd = ['dbt', 'compile', '--target', target, '--vars', vars_yaml]
    print(f"Running: {' '.join(compile_cmd)}")
    if not run_dbt_command(compile_cmd):
        print("dbt compile failed")
        sys.exit(1)
    print(f"✓ Successful compile")

    # Run test scenarios
    def run_scenario(scenario_vars, scenario_name, include_incremental=False):
        print(f"\n=== Running {scenario_name} ===")

        # Build vars dict
        vars_dict = scenario_vars.copy()
        if build_schema:
            vars_dict[schema_var_name] = build_schema

        # Build YAML format for dbt --vars
        vars_yaml_parts = []
        for key, value in vars_dict.items():
            if isinstance(value, str):
                vars_yaml_parts.append(f"{key}: {value}")
            else:
                vars_yaml_parts.append(f"{key}: {value}")
        vars_yaml = f"{{{', '.join(vars_yaml_parts)}}}"
        print(f"Variables: {vars_yaml}")
        print(f"Include incremental: {include_incremental}")

        # Always run full refresh first
        print(f"\n--- Full refresh run ---")
        run_cmd_full = ['dbt', 'run', '--target', target, '--vars', vars_yaml, '--full-refresh']
        test_cmd = ['dbt', 'test', '--target', target, '--vars', vars_yaml]

        # Execute full refresh run
        if not run_dbt_command(run_cmd_full):
            print(f"dbt run (full refresh) failed for {scenario_name}")
            sys.exit(1)

        if not run_dbt_command(test_cmd):
            print(f"dbt test failed for {scenario_name}")
            sys.exit(1)

        # Run incremental if requested
        if include_incremental:
            print(f"\n--- Incremental run ---")
            run_cmd_incremental = ['dbt', 'run', '--target', target, '--vars', vars_yaml]

            if not run_dbt_command(run_cmd_incremental):
                print(f"dbt run (incremental) failed for {scenario_name}")
                sys.exit(1)

            if not run_dbt_command(test_cmd):
                print(f"dbt test (after incremental) failed for {scenario_name}")
                sys.exit(1)

    # Run default scenario first (always full refresh)
    run_scenario({}, "default scenario", include_incremental=False)

    # Run additional test scenarios
    for i, scenario in enumerate(config.get('test_scenarios', []), 2):
        scenario_vars = scenario.get('vars', {})
        include_incremental = scenario.get('include_incremental', False)  # Default to false if not specified
        run_scenario(scenario_vars, f"test scenario {i}", include_incremental)

    print("\n=== All test scenarios completed successfully! ===")


if __name__ == "__main__":
    main()