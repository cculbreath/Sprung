#!/bin/bash

# Script to restore production database after testing
DB_PATH="/Users/cculbreath/Library/Containers/Physics-Cloud.PhysCloudResume/Data/Library/Application Support"

echo "🔄 Restoring production database..."

cd "$DB_PATH"

# Remove any test databases
rm -f default.store default.store-shm default.store-wal

# Restore production database
mv default.store.test_backup default.store
mv default.store-shm.test_backup default.store-shm  
mv default.store-wal.test_backup default.store-wal

echo "✅ Production database restored!"
echo "⚠️  Note: Your production database still has enum issues that need to be fixed separately"
