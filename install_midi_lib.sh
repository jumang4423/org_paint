#!/bin/bash

echo "Installing The MidiBus library for Processing..."
echo ""

# Create libraries directory if it doesn't exist
mkdir -p ~/Documents/Processing/libraries

# Download The MidiBus library
cd ~/Documents/Processing/libraries

if [ -d "themidibus" ]; then
    echo "The MidiBus library already exists. Removing old version..."
    rm -rf themidibus
fi

echo "Downloading The MidiBus library..."
git clone https://github.com/sparks/themidibus.git

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ The MidiBus library installed successfully!"
    echo ""
    echo "The library is now available in Processing."
    echo "You may need to restart Processing if it's currently running."
else
    echo ""
    echo "❌ Failed to install The MidiBus library"
    echo ""
    echo "Manual installation:"
    echo "1. Open Processing"
    echo "2. Go to Sketch → Import Library → Manage Libraries"
    echo "3. Search for 'The MidiBus'"
    echo "4. Click Install"
fi