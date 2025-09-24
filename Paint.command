#!/bin/bash

cd "$(dirname "$0")"

echo "========================================="
echo "     Org Paint - Thermal Printer"
echo "========================================="
echo ""

if ! command -v processing-java &> /dev/null; then
    echo "❌ Error: Processing is not installed or not in PATH"
    echo "Please install Processing from https://processing.org"
    echo ""
    echo "Press any key to close..."
    read -n 1
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo "❌ Error: Python3 is not installed"
    echo "Please install Python3"
    echo ""
    echo "Press any key to close..."
    read -n 1
    exit 1
fi

echo "Checking Python dependencies..."
if python3 -c "import escpos" 2>/dev/null; then
    echo "✅ Python dependencies already installed"
else
    echo "⚠️  Warning: python-escpos not installed"
    echo "Installing required packages to the user site-packages..."

    if ! python3 -m pip --version >/dev/null 2>&1; then
        echo "pip for Python 3 not found, attempting to bootstrap it..."
        python3 -m ensurepip --upgrade >/dev/null 2>&1
    fi

    python3 -m pip install --user --upgrade python-escpos pillow pyusb

    if python3 -c "import escpos" 2>/dev/null; then
        echo "✅ Python dependencies installed"
    else
        echo "❌ Failed to install packages automatically"
        echo "Please run:"
        echo "  python3 -m pip install --user --upgrade python-escpos pillow pyusb"
        echo ""
        echo "Press any key to close..."
        read -n 1
        exit 1
    fi
fi

echo "Checking The MidiBus library..."
if [ ! -d ~/Documents/Processing/libraries/themidibus ]; then
    echo "⚠️  The MidiBus library not found"
    echo "Installing The MidiBus library..."
    
    mkdir -p ~/Documents/Processing/libraries
    
    cd ~/Documents/Processing/libraries
    git clone https://github.com/sparks/themidibus.git 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "✅ The MidiBus library installed successfully!"
    else
        echo "⚠️  Failed to install The MidiBus library automatically"
        echo "Please install manually from Processing IDE:"
        echo "  Sketch → Import Library → Manage Libraries → Search 'The MidiBus'"
    fi
    
    cd - > /dev/null
else
    echo "✅ The MidiBus library is already installed"
fi

if [ ! -f "org_paint.pde" ]; then
    echo "❌ Error: org_paint.pde not found"
    echo "Please run this script from the project directory"
    echo ""
    echo "Press any key to close..."
    read -n 1
    exit 1
fi

echo ""
echo "✅ All checks passed!"
echo "Starting Org Paint (CPU) App..."
echo "========================================="
echo ""

processing-java --sketch="$(pwd)" --run

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Application closed successfully"
else
    echo ""
    echo "❌ Application exited with error"
fi

echo ""
echo "Press any key to close..."
read -n 1
