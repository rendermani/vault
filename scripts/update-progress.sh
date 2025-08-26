#!/bin/bash

# Quick progress update script for manual updates
# Usage: ./update-progress.sh "message" [phase] [progress_percent]

VAULT_DIR="/Users/mlautenschlager/cloudya/vault"
PROGRESS_FILE="$VAULT_DIR/progress.json"
MESSAGE="$1"
PHASE="$2"
PROGRESS="$3"

if [ -z "$MESSAGE" ]; then
    echo "Usage: $0 'update message' [phase] [progress_percent]"
    exit 1
fi

# Get current timestamp
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
TIME_ONLY=$(date '+%H:%M:%S')

# Create a Python script to update the JSON
python3 << EOF
import json
import sys
from datetime import datetime

try:
    # Load current progress
    with open('$PROGRESS_FILE', 'r') as f:
        data = json.load(f)
    
    # Update timestamp
    data['timestamp'] = '$TIMESTAMP'
    
    # Update phase if provided
    if '$PHASE':
        data['current_phase'] = '$PHASE'
    
    # Update progress if provided
    if '$PROGRESS':
        data['overall_progress'] = int('$PROGRESS')
    
    # Add new activity
    new_activity = {
        'time': '$TIME_ONLY',
        'message': '$MESSAGE'
    }
    
    # Insert at beginning and keep last 15
    activities = data.get('recent_activities', [])
    activities.insert(0, new_activity)
    data['recent_activities'] = activities[:15]
    
    # Write back to file
    with open('$PROGRESS_FILE', 'w') as f:
        json.dump(data, f, indent=2)
    
    print("Progress updated successfully")
    print(f"Message: $MESSAGE")
    if '$PHASE':
        print(f"Phase: $PHASE")
    if '$PROGRESS':
        print(f"Progress: $PROGRESS%")
        
except Exception as e:
    print(f"Error updating progress: {e}")
    sys.exit(1)
EOF