#!/bin/bash

# GLSL Paint App Launcher
# For thermal printer output (576px width)

echo "========================================="
echo "     GLSL Paint - Thermal Printer"
echo "========================================="
echo ""

# Check if Processing is installed
if ! command -v processing-java &> /dev/null; then
    echo "❌ Error: Processing is not installed or not in PATH"
    echo "Please install Processing from https://processing.org"
    exit 1
fi

# Check if Python3 is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Error: Python3 is not installed"
    echo "Please install Python3"
    exit 1
fi

# Check Python dependencies
echo "Checking Python dependencies..."
python3 -c "import escpos" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "⚠️  Warning: python-escpos not installed"
    echo "Installing required packages..."
    pip3 install python-escpos pillow pyusb
    if [ $? -ne 0 ]; then
        echo "Failed to install packages. Try:"
        echo "  sudo pip3 install python-escpos pillow pyusb"
    fi
fi

# Check and install The MidiBus library if needed
echo "Checking The MidiBus library..."
if [ ! -d ~/Documents/Processing/libraries/themidibus ]; then
    echo "⚠️  The MidiBus library not found"
    echo "Installing The MidiBus library..."
    
    # Create libraries directory if it doesn't exist
    mkdir -p ~/Documents/Processing/libraries
    
    # Download The MidiBus library
    cd ~/Documents/Processing/libraries
    git clone https://github.com/sparks/themidibus.git 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "✅ The MidiBus library installed successfully!"
    else
        echo "⚠️  Failed to install The MidiBus library automatically"
        echo "Please install manually from Processing IDE:"
        echo "  Sketch → Import Library → Manage Libraries → Search 'The MidiBus'"
    fi
    
    # Return to original directory
    cd - > /dev/null
else
    echo "✅ The MidiBus library is already installed"
fi

# Check if sketch exists
if [ ! -f "org_paint.pde" ]; then
    echo "❌ Error: org_paint.pde not found"
    echo "Please run this script from the project directory"
    exit 1
fi

echo ""
echo "✅ All checks passed!"
echo "Starting GLSL Paint App..."
echo "========================================="
echo ""

# Run Processing sketch
processing-java --sketch="$(pwd)" --run

# Check exit code
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Application closed successfully"
else
    echo ""
    echo "❌ Application exited with error"
fi