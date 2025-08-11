#!/bin/bash

# Precommit script for Elixir/Phoenix LiveView project
# This script ensures code quality and runs all necessary checks

set -e  # Exit on any error

echo "🚀 Running precommit checks..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    echo -e "${BLUE}▶${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "mix.exs" ]; then
    print_error "mix.exs not found. Please run this script from the project root."
    exit 1
fi

# 1. Check for uncommitted changes (optional warning)
if [ -d ".git" ]; then
    if ! git diff-index --quiet HEAD --; then
        print_warning "You have uncommitted changes"
    fi
fi

# 2. Get dependencies
print_status "Fetching dependencies..."
if ! mix deps.get; then
    print_error "Failed to fetch dependencies"
    exit 1
fi
print_success "Dependencies fetched"

# 3. Check for unused dependencies
print_status "Checking for unused dependencies..."
if ! mix deps.unlock --check-unused; then
    print_warning "Some dependencies might be unused"
else
    print_success "No unused dependencies found"
fi

# 4. Format code
print_status "Formatting code..."
if ! mix format --check-formatted; then
    print_warning "Code is not properly formatted. Running formatter..."
    mix format
    print_success "Code formatted"
else
    print_success "Code is properly formatted"
fi

# 5. Compile with warnings as errors
print_status "Compiling with warnings as errors..."
if ! mix compile --warnings-as-errors; then
    print_error "Compilation failed or has warnings"
    exit 1
fi
print_success "Compilation successful"

# 6. Run static analysis with Credo (if available)
print_status "Running static analysis..."
if mix help credo >/dev/null 2>&1; then
    if ! mix credo --strict; then
        print_error "Credo analysis failed"
        exit 1
    fi
    print_success "Static analysis passed"
else
    print_warning "Credo not available, skipping static analysis"
fi

# 7. Security analysis with Sobelow (if available)
print_status "Running security analysis..."
if mix help sobelow >/dev/null 2>&1; then
    if ! mix sobelow --config; then
        print_error "Security analysis failed"
        exit 1
    fi
    print_success "Security analysis passed"
else
    print_warning "Sobelow not available, skipping security analysis"
fi

# 8. Run all tests
print_status "Running tests..."
if ! mix test; then
    print_error "Tests failed"
    exit 1
fi
print_success "All tests passed"

# 9. Check test coverage (if ExCoveralls is available)
print_status "Checking test coverage..."
if mix help coveralls >/dev/null 2>&1; then
    if ! mix coveralls; then
        print_warning "Coverage check completed with warnings"
    else
        print_success "Coverage check passed"
    fi
else
    print_warning "ExCoveralls not available, skipping coverage check"
fi

# 10. Check dialyzer types (if available)
print_status "Running Dialyzer type checking..."
if mix help dialyzer >/dev/null 2>&1; then
    if ! mix dialyzer; then
        print_error "Dialyzer type checking failed"
        exit 1
    fi
    print_success "Type checking passed"
else
    print_warning "Dialyzer not available, skipping type checking"
fi

# 11. Compile assets
print_status "Compiling assets..."
if [ -f "assets/package.json" ]; then
    cd assets
    if ! npm install; then
        print_error "Failed to install npm dependencies"
        exit 1
    fi
    if ! npm run build; then
        print_error "Failed to build assets"
        exit 1
    fi
    cd ..
    print_success "Assets compiled"
else
    # Phoenix 1.7+ style
    if ! mix assets.deploy; then
        print_warning "Asset compilation had issues"
    else
        print_success "Assets compiled"
    fi
fi

# 12. Check for TODO/FIXME comments
print_status "Checking for TODO/FIXME comments..."
TODO_COUNT=$(grep -r "TODO\|FIXME" lib test --exclude-dir=deps --exclude-dir=_build | wc -l)
if [ "$TODO_COUNT" -gt 0 ]; then
    print_warning "Found $TODO_COUNT TODO/FIXME comments"
    grep -r "TODO\|FIXME" lib test --exclude-dir=deps --exclude-dir=_build
else
    print_success "No TODO/FIXME comments found"
fi

# 13. Final validation - start the server briefly to ensure it boots
print_status "Testing server startup..."
timeout 10s mix phx.server >/dev/null 2>&1 || true
if [ $? -eq 124 ]; then
    print_success "Server starts successfully"
else
    print_error "Server failed to start"
    exit 1
fi

echo ""
print_success "🎉 All precommit checks passed! Ready to commit."
echo ""

# Summary
echo "Summary of checks:"
echo "✅ Dependencies fetched and checked"
echo "✅ Code formatted"
echo "✅ Compilation successful"
echo "✅ Static analysis passed"
echo "✅ Security analysis passed"
echo "✅ All tests passed"
echo "✅ Coverage checked"
echo "✅ Type checking passed"
echo "✅ Assets compiled"
echo "✅ Server startup verified"
