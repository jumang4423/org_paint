#!/usr/bin/env python3
import base64
from escpos.printer import Usb, Network
from PIL import Image
import usb.core
import usb.util
import sys

class MUNBYNPrinter:
    """MUNBYN thermal receipt printer (80mm, ESC/POS compatible)"""
    
    def __init__(self, connection_type='usb', ip_address=None):
        """
        Initialize MUNBYN printer
        
        Args:
            connection_type: 'usb' or 'network'
            ip_address: IP address for network connection
        """
        self.connection_type = connection_type
        self.printer = None
        
        if connection_type == 'usb':
            self._connect_usb()
        elif connection_type == 'network' and ip_address:
            self._connect_network(ip_address)
        else:
            raise ValueError("Invalid connection type or missing IP address")
        
        # Set up Japanese encoding support
        if self.printer:
            self._setup_japanese_encoding()
    
    def _connect_usb(self):
        """Connect via USB - auto-detect MUNBYN printer"""
        try:
            # Common vendor/product IDs for thermal printers
            # MUNBYN often uses these standard ESC/POS IDs
            vendor_product_pairs = [
                (0x1FC9, 0x2016),  # MUNBYN printer (your printer)
                (0x0416, 0x5011),  # Common ESC/POS
                (0x0456, 0x0808),  # Another common ID
                (0x04b8, 0x0202),  # Epson compatible
                (0x0519, 0x0001),  # Generic thermal
            ]
            
            connected = False
            for vendor_id, product_id in vendor_product_pairs:
                try:
                    self.printer = Usb(vendor_id, product_id)
                    print(f"Connected to printer: VID={hex(vendor_id)}, PID={hex(product_id)}")
                    connected = True
                    break
                except:
                    continue
            
            if not connected:
                # Try to find any thermal printer
                print("Searching for thermal printers...")
                devices = usb.core.find(find_all=True)
                for device in devices:
                    try:
                        self.printer = Usb(device.idVendor, device.idProduct)
                        print(f"Connected to printer: VID={hex(device.idVendor)}, PID={hex(device.idProduct)}")
                        connected = True
                        break
                    except:
                        continue
            
            if not connected:
                raise Exception("No thermal printer found. Please check USB connection.")
            
            # Set printer profile for 80mm printer (576 pixels width)
            # This fixes the center alignment warning
            if self.printer:
                try:
                    # Update the existing media profile with actual values
                    # The library checks profile_data['media']['width']['pixels'] != "Unknown"
                    self.printer.profile.profile_data['media']['width']['pixels'] = 576
                    self.printer.profile.profile_data['media']['width']['mm'] = 80
                except:
                    pass  # If profile setup fails, continue anyway
                
        except Exception as e:
            print(f"USB connection error: {e}")
            print("\nTo find your printer's USB IDs, run:")
            print("  lsusb (on Linux/Mac)")
            print("  or check Device Manager on Windows")
            raise
    
    def _connect_network(self, ip_address):
        """Connect via network/LAN"""
        try:
            self.printer = Network(ip_address)
            print(f"Connected to printer at {ip_address}")
        except Exception as e:
            print(f"Network connection error: {e}")
            raise
    
    def _setup_japanese_encoding(self):
        """Set up Japanese character encoding support"""
        try:
            # Based on test_japanese_alt.py, raw ESC/POS commands work best
            # Initialize printer
            self.printer._raw(b'\x1b\x40')
            # Set CP932 (Shift-JIS Japanese)
            self.printer._raw(b'\x1b\x74\x0c')  # ESC t 12
            # Set Japan region
            self.printer._raw(b'\x1b\x52\x08')  # ESC R 8
            # Also set charcode for the library
            self.printer.charcode('CP932')
            print("Japanese encoding enabled (CP932/Shift-JIS)")
        except Exception as e:
            print(f"Warning: Could not set Japanese encoding: {e}")
            print("Printer may not support Japanese characters")
    
    def text(self, text, align='left', font='a', width=1, height=1, bold=False):
        """
        Print text with proper encoding support for Japanese
        
        Args:
            text: Text to print (Unicode string)
            align: 'left', 'center', or 'right'
            font: 'a' or 'b'
            width: Text width multiplier (1-8)
            height: Text height multiplier (1-8)
            bold: Bold text
        """
        if self.printer:
            # Set alignment
            if align == 'center':
                self.printer.set(align='center')
            elif align == 'right':
                self.printer.set(align='right')
            else:
                self.printer.set(align='left')
            
            # Set font and size
            self.printer.set(
                font=font,
                width=width,
                height=height,
                bold=bold
            )
            
            # Method 3 from test_japanese_alt.py - encode as Shift-JIS and send raw bytes
            try:
                # Check if text contains Japanese characters
                if any(ord(char) > 127 for char in text):
                    # Encode as Shift-JIS and send as raw bytes
                    encoded = text.encode('shift-jis', errors='replace')
                    self.printer._raw(encoded)
                else:
                    # For ASCII text, use normal method
                    self.printer.text(text)
            except Exception as e:
                # Fallback to normal text method
                self.printer.text(text)
            
            # Don't reset alignment - let each call set its own alignment
    
    def image(self, img_path, impl='bitImageRaster'):
        """
        Print image
        
        Args:
            img_path: Path to image file
            impl: Implementation method ('bitImageRaster' or 'graphics')
        """
        if self.printer:
            try:
                # Open and resize image for 80mm width
                img = Image.open(img_path)
                
                # 80mm at 203 DPI = ~640 pixels
                max_width = 576  # Slightly smaller for margins
                if img.width > max_width:
                    ratio = max_width / img.width
                    new_height = int(img.height * ratio)
                    img = img.resize((max_width, new_height), Image.Resampling.LANCZOS)
                
                # Convert to grayscale if needed
                if img.mode != 'L':
                    img = img.convert('L')
                
                # Print image - explicitly set center=False to avoid warning
                self.printer.image(img, impl=impl, center=False)
            except Exception as e:
                print(f"Image print error: {e}")
    
    def qr(self, content, size=4):
        """
        Print QR code
        
        Args:
            content: QR code content
            size: QR code size (1-16)
        """
        if self.printer:
            self.printer.qr(content, size=size)
    
    def barcode(self, code, bc='CODE128', height=64, width=3, pos='BELOW', font='A'):
        """
        Print barcode
        
        Args:
            code: Barcode content
            bc: Barcode type
            height: Barcode height
            width: Barcode width
            pos: Text position ('OFF', 'ABOVE', 'BELOW', 'BOTH')
            font: Font for text
        """
        if self.printer:
            self.printer.barcode(code, bc, height, width, pos, font)
    
    def cut(self, mode='FULL'):
        """
        Cut paper
        
        Args:
            mode: 'FULL' or 'PART' (partial cut)
        """
        if self.printer:
            self.printer.cut(mode=mode)
    
    def feed(self, lines=3):
        """Feed paper by number of lines"""
        if self.printer:
            self.printer.ln(lines)
    
    def cash_drawer(self, pin=2):
        """Open cash drawer"""
        if self.printer:
            self.printer.cashdraw(pin)
    
    def close(self):
        """Close printer connection"""
        if self.printer:
            self.printer.close()

# Main function to print the painting
if __name__ == "__main__":
    import os
    from datetime import datetime
    
    # Check if image file exists
    img_path = "output.png"
    if len(sys.argv) > 1:
        img_path = sys.argv[1]
    
    if not os.path.exists(img_path):
        print(f"Error: {img_path} not found")
        sys.exit(1)
    
    try:
        # Initialize printer
        printer = MUNBYNPrinter(connection_type='usb')
        
        # Print header
        printer.text("== GLSL Paint ==\n", align='center', width=2, height=2)
        printer.text(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n", align='center')
        printer.feed(1)
        
        # Print the image
        printer.image(img_path)
        
        # Print footer
        printer.feed(1)
        printer.text("Generated with Processing + GLSL\n", align='center', font='b')
        printer.text("576px thermal printer width\n", align='center', font='b')
        
        # Cut paper
        printer.feed(3)
        printer.cut()
        
        # Close connection
        printer.close()
        
        print(f"Successfully printed {img_path}")
        
    except Exception as e:
        print(f"Printing failed: {e}")
        sys.exit(1)