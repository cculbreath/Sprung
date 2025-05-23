#!/bin/bash

# Database Reset Script for PhysCloudResume
# This script removes the corrupted database files to force a clean migration

DATABASE_PATH="/Users/cculbreath/Library/Containers/Physics-Cloud.PhysCloudResume/Data/Library/Application Support"

echo "🗄️ PhysCloudResume Database Reset"
echo "=================================="
echo ""

# Check if app is running
if pgrep -x "PhysCloudResume" > /dev/null; then
    echo "❌ PhysCloudResume is currently running. Please quit the app first."
    exit 1
fi

echo "📁 Database path: $DATABASE_PATH"
echo ""

# List current database files
echo "🔍 Current database files:"
if [ -d "$DATABASE_PATH" ]; then
    ls -la "$DATABASE_PATH"/*.store* "$DATABASE_PATH"/*.sqlite* 2>/dev/null || echo "No database files found"
else
    echo "Database directory does not exist yet"
fi
echo ""

# Confirm with user
read -p "⚠️  This will DELETE ALL DATA. Are you sure? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Operation cancelled"
    exit 0
fi

echo ""
echo "🗑️  Removing database files..."

# Remove the database files
if [ -d "$DATABASE_PATH" ]; then
    rm -f "$DATABASE_PATH"/default.store*
    rm -f "$DATABASE_PATH"/Model.sqlite*
    rm -f "$DATABASE_PATH"/*.db*
    echo "✅ Database files removed"
else
    echo "ℹ️  No database directory found (this is normal for a fresh install)"
fi

echo ""
echo "🎉 Database reset complete!"
echo ""
echo "Next steps:"
echo "1. Launch PhysCloudResume"
echo "2. The app will create a fresh database with the correct schema"
echo "3. Re-import any data you need"
echo ""