#!/bin/bash
# Updates checklist task status in a SpecGate execution document.
# Usage: ./update-task-status.sh <TASKS_FILE> <TASK_ID> <STATUS> [NOTES]

set -e

TASKS_FILE="$1"
TASK_ID="$2"
STATUS="$3"
NOTES="${4:-""}"

if [ -z "$TASKS_FILE" ] || [ -z "$TASK_ID" ] || [ -z "$STATUS" ]; then
  echo "Error: TASKS_FILE, TASK_ID, and STATUS arguments are required"
  echo "Usage: $0 <TASKS_FILE> <TASK_ID> <STATUS> [NOTES]"
  echo ""
  echo "STATUS options: pending|in-progress|complete"
  exit 1
fi

if [ ! -f "$TASKS_FILE" ]; then
  echo "Error: Tasks file does not exist: $TASKS_FILE"
  exit 1
fi

# Validate status
case "$STATUS" in
  pending|in-progress|complete)
    ;;
  *)
    echo "Error: Invalid STATUS '$STATUS'. Must be: pending, in-progress, or complete"
    exit 1
    ;;
esac

# Get current timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Update task checkbox and status
case "$STATUS" in
  pending)
    # Set checkbox to unchecked and status to pending
    sed -i.bak "s/^\- \[x\] $TASK_ID /- [ ] $TASK_ID /" "$TASKS_FILE"
    sed -i.bak "s/^\- \[ \] $TASK_ID /- [ ] $TASK_ID /" "$TASKS_FILE"
    STATUS_EMOJI="⬜ Pending"
    ;;
  in-progress)
    # Set checkbox to unchecked and status to in-progress
    sed -i.bak "s/^\- \[x\] $TASK_ID /- [ ] $TASK_ID /" "$TASKS_FILE"
    sed -i.bak "s/^\- \[ \] $TASK_ID /- [ ] $TASK_ID /" "$TASKS_FILE"
    STATUS_EMOJI="🔄 In Progress"
    ;;
  complete)
    # Set checkbox to checked and status to complete
    sed -i.bak "s/^\- \[ \] $TASK_ID /- [x] $TASK_ID /" "$TASKS_FILE"
    STATUS_EMOJI="✅ Complete"
    ;;
esac

# Update status field if it exists
if grep -q "Status:" "$TASKS_FILE"; then
  # Find the task block and update status
  awk -v task_id="$TASK_ID" -v status_emoji="$STATUS_EMOJI" -v timestamp="$TIMESTAMP" '
    BEGIN { in_task = 0; found_task = 0 }
    $0 ~ task_id { in_task = 1; found_task = 1 }
    in_task && /Status:/ {
      sub(/Status:.*/, "Status: " status_emoji)
      sub(/Started:.*/, "Started: " timestamp)
      if (status_emoji == "✅ Complete") {
        sub(/Completed:.*/, "Completed: " timestamp)
      }
    }
    in_task && /^- \[ / && $0 !~ task_id { in_task = 0 }
    { print }
  ' "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"
fi

# Add notes if provided
if [ -n "$NOTES" ]; then
  # Find the task block and add/update notes
  awk -v task_id="$TASK_ID" -v notes="$NOTES" '
    BEGIN { in_task = 0; found_task = 0 }
    $0 ~ task_id { in_task = 1; found_task = 1 }
    in_task && /Notes:/ {
      sub(/Notes:.*/, "Notes: " notes)
    }
    in_task && /^- \[ / && $0 !~ task_id { in_task = 0 }
    { print }
  ' "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"
fi

# Clean up backup files
rm -f "${TASKS_FILE}.bak"

# Recalculate dashboard stats
echo "Updating dashboard stats..."

# Count total tasks
TOTAL_TASKS=$(grep -c "^- \[" "$TASKS_FILE" 2>/dev/null || echo "0")

# Count completed tasks
COMPLETED_TASKS=$(grep -c "^- \[x\]" "$TASKS_FILE" 2>/dev/null || echo "0")

# Calculate percentage
if [ "$TOTAL_TASKS" -gt 0 ]; then
  PERCENTAGE=$((COMPLETED_TASKS * 100 / TOTAL_TASKS))
else
  PERCENTAGE=0
fi

# Update dashboard
awk -v total="$TOTAL_TASKS" -v completed="$COMPLETED_TASKS" -v percentage="$PERCENTAGE" -v timestamp="$TIMESTAMP" '
  BEGIN { in_dashboard = 0 }
  /Task Status Dashboard/ { in_dashboard = 1 }
  in_dashboard && /Overall Progress:/ {
    sub(/Overall Progress:.*/, "Overall Progress: [" completed "/" total "] tasks completed (" percentage "%)")
  }
  in_dashboard && /Last Updated:/ {
    sub(/Last Updated:.*/, "Last Updated: " timestamp)
  }
  { print }
' "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"

# Find next pending task (supports code/test task IDs)
NEXT_TASK=$(grep "^- \[ \]" "$TASKS_FILE" | head -1 | sed -E 's/.*(([A-Z]{1,2})?[0-9]{3,4}).*/\1/')

# Update execution context
awk -v next_task="$NEXT_TASK" '
  BEGIN { in_context = 0; found_context = 0 }
  /^##[[:space:]]*(Execution Context|Current Execution Context)/ {
    in_context = 1
    found_context = 1
    next
  }
  in_context && /^##[[:space:]]+/ { in_context = 0 }
  in_context && /Next Task/ {
    sub(/.*Next Task.*:\s*.*/, "- **Next Task**: " next_task)
  }
  { print }
' "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"

echo "Task $TASK_ID status updated to: $STATUS"
echo "Progress: $COMPLETED_TASKS/$TOTAL_TASKS tasks completed ($PERCENTAGE%)"
echo "Next task: $NEXT_TASK"
