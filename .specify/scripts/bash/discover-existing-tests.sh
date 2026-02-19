#!/bin/bash
# Discovers existing tests and generates test-status.md
# Usage: ./discover-existing-tests.sh <FEATURE_DIR>

set -e

FEATURE_DIR="$1"
FEATURE_DOCS_DIR="$FEATURE_DIR/docs"
OUTPUT_FILE="$FEATURE_DOCS_DIR/test-status.md"

if [ -z "$FEATURE_DIR" ]; then
  echo "Error: FEATURE_DIR argument is required"
  echo "Usage: $0 <FEATURE_DIR>"
  exit 1
fi

if [ ! -d "$FEATURE_DIR" ]; then
  echo "Error: Feature directory does not exist: $FEATURE_DIR"
  exit 1
fi

if [ ! -d "$FEATURE_DOCS_DIR" ]; then
  echo "Error: docs/ directory does not exist: $FEATURE_DOCS_DIR"
  exit 1
fi

# Get repository root
if git -C "$FEATURE_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$FEATURE_DIR" rev-parse --show-toplevel)"
else
  dir="$FEATURE_DIR"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.git" ] || [ -d "$dir/.specify" ]; then
      REPO_ROOT="$dir"
      break
    fi
    dir="$(dirname "$dir")"
  done
fi

if [ -z "${REPO_ROOT:-}" ]; then
  echo "Error: Could not determine repository root from $FEATURE_DIR"
  exit 1
fi

echo "# Existing Test Inventory"
echo ""
echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo ""
echo "## Existing Test Inventory"
echo ""
echo "| Component      | Source File                          | Existing Test                       | Status  | Action   | Notes                  |"
echo "| -------------- | ------------------------------------ | ----------------------------------- | ------- | -------- | ---------------------- |"

# Function to check if test file exists and analyze it
check_test_status() {
  local source_file="$1"
  local test_file="$2"
  local component_name="$3"
  
  if [ ! -f "$source_file" ]; then
    return
  fi
  
  if [ ! -f "$test_file" ]; then
    echo "| $component_name | $source_file | NONE                                | MISSING | CREATE   | New component          |"
    return
  fi
  
  # Check if test file has tests
  if grep -q "test(" "$test_file" 2>/dev/null; then
    # Check for deprecated patterns
    if grep -q "Mockito\|when(\|verify(" "$test_file" 2>/dev/null; then
      echo "| $component_name | $source_file | $test_file | LEGACY  | REFACTOR | Uses old mock pattern  |"
    else
      # Check coverage (simple heuristic - count test cases vs methods)
      local test_count=$(grep -c "test(" "$test_file" 2>/dev/null || echo "0")
      if [ "$test_count" -lt 3 ]; then
        echo "| $component_name | $source_file | $test_file | PARTIAL | UPDATE   | Missing some tests     |"
      else
        echo "| $component_name | $source_file | $test_file | COMPLETE | VERIFY   | Full coverage          |"
      fi
    fi
  else
    echo "| $component_name | $source_file | $test_file | LEGACY  | REFACTOR | No test cases found   |"
  fi
}

# Scan for domain entities
if [ -d "$REPO_ROOT/lib/domain/entities" ]; then
  for entity_file in "$REPO_ROOT/lib/domain/entities"/*.dart; do
    if [ -f "$entity_file" ]; then
      entity_name=$(basename "$entity_file" .dart)
      test_file="$REPO_ROOT/test/domain/entities/${entity_name}_test.dart"
      check_test_status "$entity_file" "$test_file" "$entity_name"
    fi
  done
fi

# Scan for data models
if [ -d "$REPO_ROOT/lib/data/models" ]; then
  for model_file in "$REPO_ROOT/lib/data/models"/*.dart; do
    if [ -f "$model_file" ]; then
      model_name=$(basename "$model_file" .dart)
      test_file="$REPO_ROOT/test/data/models/${model_name}_test.dart"
      check_test_status "$model_file" "$test_file" "$model_name"
    fi
  done
fi

# Scan for data repositories
if [ -d "$REPO_ROOT/lib/data/repositories" ]; then
  for repo_file in "$REPO_ROOT/lib/data/repositories"/*.dart; do
    if [ -f "$repo_file" ]; then
      repo_name=$(basename "$repo_file" .dart)
      test_file="$REPO_ROOT/test/data/repositories/${repo_name}_test.dart"
      check_test_status "$repo_file" "$test_file" "$repo_name"
    fi
  done
fi

# Scan for presentation controllers
if [ -d "$REPO_ROOT/lib/presentation/controllers" ]; then
  for controller_file in "$REPO_ROOT/lib/presentation/controllers"/*.dart; do
    if [ -f "$controller_file" ]; then
      controller_name=$(basename "$controller_file" .dart)
      test_file="$REPO_ROOT/test/presentation/controllers/${controller_name}_test.dart"
      check_test_status "$controller_file" "$test_file" "$controller_name"
    fi
  done
fi

# Scan for presentation widgets
if [ -d "$REPO_ROOT/lib/presentation/widgets" ]; then
  for widget_file in "$REPO_ROOT/lib/presentation/widgets"/*.dart; do
    if [ -f "$widget_file" ]; then
      widget_name=$(basename "$widget_file" .dart)
      test_file="$REPO_ROOT/test/presentation/widgets/${widget_name}_test.dart"
      check_test_status "$widget_file" "$test_file" "$widget_name"
    fi
  done
fi

echo ""
echo "Status definitions:"
echo ""
echo "- MISSING: No test file exists"
echo "- PARTIAL: Test file exists but lacks coverage"
echo "- COMPLETE: Test file exists with full coverage"
echo "- LEGACY: Test exists but uses deprecated patterns"
