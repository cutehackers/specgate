#!/bin/bash
# Analyzes git changes to identify test focus areas
# Usage: ./analyze-changes.sh <FEATURE_DIR> [BASE_REF]

set -e

FEATURE_DIR="$1"
BASE_REF="${2:-"main"}"
FEATURE_DOCS_DIR="$FEATURE_DIR/docs"
OUTPUT_FILE="$FEATURE_DOCS_DIR/change-analysis.md"

if [ -z "$FEATURE_DIR" ]; then
  echo "Error: FEATURE_DIR argument is required"
  echo "Usage: $0 <FEATURE_DIR> [BASE_REF]"
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

echo "# Code Changes Detected"
echo ""
echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo ""
echo "## Code Changes Detected"
echo ""
echo "### Modified Files"
echo ""
echo "| File                          | Change Type | Lines Changed | Test Impact          |"
echo "| ----------------------------- | ----------- | ------------- | -------------------- |"

# Get changed files in lib/ directory
CHANGED_FILES=$(cd "$REPO_ROOT" && git diff --name-only "$BASE_REF"..HEAD -- lib/ 2>/dev/null || echo "")

if [ -z "$CHANGED_FILES" ]; then
  echo "No changes detected in lib/ directory"
  exit 0
fi

# Analyze each changed file
for file in $CHANGED_FILES; do
  if [ ! -f "$REPO_ROOT/$file" ]; then
    continue
  fi
  
  # Determine change type
  if git diff "$BASE_REF"..HEAD -- "$file" 2>/dev/null | grep -q "^+"; then
    if git diff "$BASE_REF"..HEAD -- "$file" 2>/dev/null | grep -q "^-"; then
      CHANGE_TYPE="MODIFIED"
    else
      CHANGE_TYPE="NEW"
    fi
  else
    CHANGE_TYPE="DELETED"
  fi
  
  # Count lines changed
  LINES_CHANGED=$(cd "$REPO_ROOT" && git diff "$BASE_REF"..HEAD -- "$file" 2>/dev/null | wc -l || echo "0")
  
  # Determine test impact
  TEST_IMPACT="Review changes"
  case "$file" in
    *entities/*)
      TEST_IMPACT="Add entity tests"
      ;;
    *models/*)
      TEST_IMPACT="Add model tests"
      ;;
    *repositories/*)
      TEST_IMPACT="Add repository tests"
      ;;
    *controllers/*)
      TEST_IMPACT="Add controller tests"
      ;;
    *widgets/*|*pages/*)
      TEST_IMPACT="Add widget tests"
      ;;
    *)
      TEST_IMPACT="Review changes"
      ;;
  esac
  
  echo "| $file | $CHANGE_TYPE | $LINES_CHANGED | $TEST_IMPACT |"
done

echo ""
echo "### Test Focus Areas"
echo ""
echo "- **Priority 1**: New public methods"
echo "- **Priority 2**: Modified behavior"
echo "- **Priority 3**: Unchanged code that interacts with changes"
echo ""
echo "### Change Status per Component"
echo ""
echo "| Component      | Change Status | Testing Priority |"
echo "| -------------- | ------------- | ---------------- |"

# Extract component names and determine change status
for file in $CHANGED_FILES; do
  if [ ! -f "$REPO_ROOT/$file" ]; then
    continue
  fi
  
  # Extract component name from file path
  component=$(basename "$file" .dart)
  
  # Determine change status
  if git diff "$BASE_REF"..HEAD -- "$file" 2>/dev/null | grep -q "^+"; then
    if git diff "$BASE_REF"..HEAD -- "$file" 2>/dev/null | grep -q "^-"; then
      CHANGE_STATUS="MODIFIED"
      PRIORITY="HIGH"
    else
      CHANGE_STATUS="NEW"
      PRIORITY="HIGH"
    fi
  else
    CHANGE_STATUS="DELETED"
    PRIORITY="SKIP"
  fi
  
  echo "| $component | $CHANGE_STATUS | $PRIORITY |"
done

echo ""
echo "## Testing Recommendations"
echo ""
echo "Based on the detected changes:"
echo ""
echo "1. **New Components**: Create full test suite with 100% coverage target"
echo "2. **Modified Components**: Add delta tests for changed behavior + regression tests for unchanged behavior"
echo "3. **Deleted Components**: Remove or update related tests"
echo "4. **Unchanged Components**: Skip testing unless coverage gap is identified"
echo ""
echo "## Next Steps"
echo ""
echo "1. Review the modified files above"
echo "2. Update test-spec.md with Change Status column"
echo "3. Run /test-specify to generate focused test tasks"
