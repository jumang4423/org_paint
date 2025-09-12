// Infinite Canvas Painting App - GLSL Version (OPTIMIZED)
// For thermal printer output (576px width)
// ALL rendering done with GLSL shaders

import java.io.*;
import javax.sound.midi.*;

PShader paintShader;
ArrayList<PGraphics> chunkTextures;  // GPU textures
ArrayList<PGraphics> chunkBuffers;   // Ping-pong buffers
ArrayList<Integer> chunkPositions;

// Canvas settings
final int CANVAS_WIDTH = 576;
final int CHUNK_HEIGHT = 1024;
int SCREEN_HEIGHT = 324;  // Will be recalculated based on screen
final int MAX_CHUNKS = 20;  // Memory limit

// Drawing state
boolean isDrawing = false;
boolean isErasing = false;
float brushSize = 2.0;  // Default 2px
float scrollY = 0;
boolean needsRedraw = true;  // Optimization flag
boolean pendingSave = false;  // Flag for deferred save operation
boolean pendingPrint = false;  // Flag for print after save

// Mouse state for shader
PVector currentMouse = new PVector(-1, -1);
PVector prevMouse = new PVector(-1, -1);

// Scaling for display
PGraphics lowResCanvas;
float displayScale = 1.0;

// MIDI
MidiDevice midiDevice = null;
boolean midiConnected = false;
volatile float pendingBrushSize = -1;  // Thread-safe variable for MIDI updates
int lastMidiCheck = 0;
float lastKnownBrushSize = 2.0;  // Track last brush size to detect changes

void setup() {
  fullScreen(P3D);  // Fullscreen
  noSmooth();  // Disable antialiasing for pixel-perfect rendering
  
  // Calculate scale to fill screen width (prioritize full 576px width accessibility)
  displayScale = (float)width / CANVAS_WIDTH;
  
  // Calculate screen height based on actual window height
  SCREEN_HEIGHT = (int)(height / displayScale);
  
  // Create low-res canvas for actual drawing (full screen height)
  lowResCanvas = createGraphics(CANVAS_WIDTH, SCREEN_HEIGHT, P3D);
  lowResCanvas.noSmooth();  // No antialiasing on low-res canvas too
  
  // Initialize GPU texture arrays
  chunkTextures = new ArrayList<PGraphics>();
  chunkBuffers = new ArrayList<PGraphics>();
  chunkPositions = new ArrayList<Integer>();
  
  // Load final GLSL paint shader
  paintShader = loadShader("paint_final_frag.glsl");
  
  // Create initial chunk
  createGPUChunk(0);
  
  // Initialize MIDI
  initMIDI();
  
  // OPTIMIZATION: Only render when needed
  noLoop();
  
  println("GLSL-based infinite canvas initialized (optimized)");
  println("Canvas width: " + CANVAS_WIDTH + "px");
  println("On-demand GPU rendering enabled");
  println("Max chunks: " + MAX_CHUNKS);
  println("Controls:");
  println("  - Left click: Draw");
  println("  - Right click: Erase");
  println("  - Mouse wheel/Arrow keys: Scroll");
  println("  - Q/A: Brush size");
  println("  - P: Save and Print to thermal printer");
  if (midiConnected) {
    println("  - MIDI CC1: Brush size (1-8px)");
  }
}

void createGPUChunk(int yPos) {
  // Check if already exists
  for (int i = 0; i < chunkPositions.size(); i++) {
    if (chunkPositions.get(i) == yPos) return;
  }
  
  // OPTIMIZATION: Limit chunks to prevent memory bloat
  if (chunkPositions.size() >= MAX_CHUNKS) {
    println("Chunk limit reached (" + MAX_CHUNKS + " chunks max)");
    return;
  }
  
  // Create two GPU textures for ping-pong
  PGraphics texture = createGraphics(CANVAS_WIDTH, CHUNK_HEIGHT, P3D);
  PGraphics buffer = createGraphics(CANVAS_WIDTH, CHUNK_HEIGHT, P3D);
  
  // No antialiasing on chunks
  texture.noSmooth();
  buffer.noSmooth();
  
  // Initialize to white
  texture.beginDraw();
  texture.background(255);
  texture.endDraw();
  
  buffer.beginDraw();
  buffer.background(255);
  buffer.endDraw();
  
  chunkTextures.add(texture);
  chunkBuffers.add(buffer);
  chunkPositions.add(yPos);
}

int getChunkIndex(float globalY) {
  // Don't create chunks for negative positions
  if (globalY < 0) return -1;
  
  int chunkY = ((int)globalY / CHUNK_HEIGHT) * CHUNK_HEIGHT;
  
  // Ensure chunk exists
  createGPUChunk(chunkY);
  
  // Find chunk index
  for (int i = 0; i < chunkPositions.size(); i++) {
    if (chunkPositions.get(i) == chunkY) {
      return i;
    }
  }
  return -1;
}

void applyPaintToChunk(int chunkIndex, float globalMouseX, float globalMouseY,
                       float globalPrevX, float globalPrevY) {
  if (chunkIndex < 0) return;
  
  int chunkY = chunkPositions.get(chunkIndex);
  float localMouseY = globalMouseY - chunkY;
  float localPrevY = globalPrevY - chunkY;
  
  // Check if brush affects this chunk
  float brushRadius = brushSize * 0.5;
  if (localMouseY < -brushRadius - 10 || localMouseY > CHUNK_HEIGHT + brushRadius + 10) {
    return;
  }
  
  // Ping-pong: swap textures
  PGraphics currentTexture = chunkTextures.get(chunkIndex);
  PGraphics bufferTexture = chunkBuffers.get(chunkIndex);
  
  // Set shader uniforms
  paintShader.set("u_mouse", globalMouseX, localMouseY);
  paintShader.set("u_prevMouse", globalPrevX < 0 ? -1.0 : globalPrevX, 
                                 globalPrevX < 0 ? -1.0 : localPrevY);
  paintShader.set("u_brushSize", brushSize);
  paintShader.set("u_isErasing", isErasing ? 1.0 : 0.0);
  
  // Apply shader to buffer
  bufferTexture.beginDraw();
  bufferTexture.shader(paintShader);
  bufferTexture.image(currentTexture, 0, 0, CANVAS_WIDTH, CHUNK_HEIGHT);
  bufferTexture.endDraw();
  
  // Swap references
  chunkTextures.set(chunkIndex, bufferTexture);
  chunkBuffers.set(chunkIndex, currentTexture);
}

void draw() {
  // Check for pending save operation (must be done in draw loop for OpenGL)
  if (pendingSave) {
    saveAndPrint(pendingPrint);
    pendingSave = false;
    pendingPrint = false;
    return;  // Don't do other drawing this frame
  }
  
  // Check for pending MIDI updates (thread-safe)
  if (pendingBrushSize > 0) {
    brushSize = pendingBrushSize;
    pendingBrushSize = -1;
    needsRedraw = true;
  }
  
  // OPTIMIZATION: Early return if nothing to update
  if (!needsRedraw && !isDrawing && !isErasing) return;
  
  // Calculate max scroll based on actual content
  float maxScroll = getMaxContentY() - SCREEN_HEIGHT;
  maxScroll = max(0, maxScroll);
  scrollY = constrain(scrollY, 0, maxScroll);
  
  // OPTIMIZATION: Only process painting when actively drawing
  if (isDrawing || isErasing) {
    float globalMouseX = mouseX / displayScale;
    float globalMouseY = mouseY / displayScale + scrollY;
    
    // Find affected chunks
    int startChunk = (int)((globalMouseY - brushSize/2) / CHUNK_HEIGHT) * CHUNK_HEIGHT;
    int endChunk = (int)((globalMouseY + brushSize/2) / CHUNK_HEIGHT) * CHUNK_HEIGHT;
    
    for (int chunkY = startChunk; chunkY <= endChunk; chunkY += CHUNK_HEIGHT) {
      int idx = getChunkIndex(chunkY);
      if (idx >= 0) {
        applyPaintToChunk(idx, globalMouseX, globalMouseY, 
                         prevMouse.x, prevMouse.y);
      }
    }
    
    prevMouse.set(globalMouseX, globalMouseY);
  } else if (prevMouse.x >= 0) {
    // Reset when not drawing
    prevMouse.set(-1, -1);
  }
  
  // Render to low-res canvas first
  lowResCanvas.beginDraw();
  lowResCanvas.background(200);
  
  // Render visible chunks to low-res canvas
  int startChunkY = max(0, (int)(scrollY / CHUNK_HEIGHT) * CHUNK_HEIGHT);
  int endChunkY = (int)((scrollY + SCREEN_HEIGHT) / CHUNK_HEIGHT + 1) * CHUNK_HEIGHT;
  
  for (int chunkY = startChunkY; chunkY <= endChunkY; chunkY += CHUNK_HEIGHT) {
    for (int i = 0; i < chunkPositions.size(); i++) {
      if (chunkPositions.get(i) == chunkY) {
        PGraphics chunk = chunkTextures.get(i);
        float renderY = chunkY - scrollY;
        lowResCanvas.image(chunk, 0, renderY);
        break;
      }
    }
  }
  
  // Draw UI on low-res canvas
  drawLowResUI();
  
  lowResCanvas.endDraw();
  
  // Scale up and display (fill screen)
  background(0);
  
  pushMatrix();
  scale(displayScale);
  image(lowResCanvas, 0, 0);
  popMatrix();
  
  // Reset redraw flag
  needsRedraw = false;
}

void drawLowResUI() {
  // Draw UI directly on low-res canvas for pixel-perfect scaling
  
  // Brush preview (convert mouse position to low-res coordinates)
  float lowResMouseX = mouseX / displayScale;
  float lowResMouseY = mouseY / displayScale;
  
  lowResCanvas.noFill();
  lowResCanvas.stroke(isErasing ? color(255, 100, 100) : color(100, 100, 255));
  lowResCanvas.strokeWeight(1);  // 1px in low-res
  lowResCanvas.ellipse(lowResMouseX, lowResMouseY, brushSize, brushSize);
  
  // Info text - BLACK color for white background
  lowResCanvas.fill(0);  // Black text
  lowResCanvas.noStroke();
  lowResCanvas.textAlign(LEFT, TOP);
  lowResCanvas.textSize(8);  // Small pixel font size
  lowResCanvas.text("MODE: " + (isErasing ? "ERASE" : "DRAW"), 2, 2);
  lowResCanvas.text("BRUSH: " + (int)brushSize + "px", 2, 10);
  lowResCanvas.text("Y: " + (int)scrollY, 2, 18);
  lowResCanvas.text("X: " + (int)lowResMouseX + "/" + CANVAS_WIDTH, 2, 26);  // Debug X position
  lowResCanvas.text("FPS: " + (int)frameRate, 2, 34);
  if (midiConnected) {
    lowResCanvas.text("MIDI: ON", 2, 42);
  }
}

void mousePressed() {
  if (mouseButton == LEFT) {
    isDrawing = true;
    isErasing = false;
  } else if (mouseButton == RIGHT) {
    isDrawing = true;
    isErasing = true;
  }
  // Adjust for scale
  prevMouse.set(mouseX / displayScale, mouseY / displayScale + scrollY);
  loop();  // Start rendering
}

void mouseReleased() {
  isDrawing = false;
  isErasing = false;
  prevMouse.set(-1, -1);
  needsRedraw = true;
  redraw();  // Final frame
  noLoop();  // Stop rendering
}

void mouseMoved() {
  // Brush preview follows mouse
  needsRedraw = true;
  redraw();
}

void mouseDragged() {
  // Keep rendering while dragging
  needsRedraw = true;
  redraw();
}

void mouseWheel(MouseEvent event) {
  // OPTIMIZATION: Direct scroll, no velocity
  float maxScroll = getMaxContentY() - SCREEN_HEIGHT;
  scrollY += event.getCount() * 0.7;  // Back to trackpad-optimized speed
  scrollY = constrain(scrollY, 0, max(0, maxScroll));
  needsRedraw = true;
  redraw();
}

void keyPressed() {
  // Handle ESC key for clean exit
  if (key == ESC) {
    key = 0;  // Prevent default ESC behavior
    exit();   // Call our custom exit method
    return;
  }
  
  switch(key) {
    case 'q':
    case 'Q':
      brushSize = min(brushSize + 1, 8);  // Max 8px
      needsRedraw = true;
      redraw();
      break;
    case 'a':
    case 'A':
      brushSize = max(brushSize - 1, 1);  // Minimum 1px
      needsRedraw = true;
      redraw();
      break;
    case 'p':
    case 'P':
      // Defer save operation to draw loop (for OpenGL safety)
      pendingSave = true;
      pendingPrint = true;
      loop();  // Ensure draw() is called
      break;
  }
  
  if (key == CODED) {
    float maxScroll = getMaxContentY() - SCREEN_HEIGHT;
    if (keyCode == UP) {
      scrollY -= 20;
      scrollY = constrain(scrollY, 0, max(0, maxScroll));
      needsRedraw = true;
      redraw();
    }
    if (keyCode == DOWN) {
      scrollY += 20;
      scrollY = constrain(scrollY, 0, max(0, maxScroll));
      needsRedraw = true;
      redraw();
    }
  }
}

// Get the maximum Y position with actual content
float getMaxContentY() {
  if (chunkPositions.isEmpty()) return CHUNK_HEIGHT;  // Allow scrolling to see first chunk area
  
  int maxY = 0;
  for (int chunkY : chunkPositions) {
    maxY = max(maxY, chunkY + CHUNK_HEIGHT);
  }
  
  // Add one more chunk height to show the next gray area
  return maxY + CHUNK_HEIGHT;
}

void saveAndPrint(boolean printToReceipt) {
  if (chunkTextures.isEmpty()) {
    println("Nothing to save");
    return;
  }
  
  // Find bounds - only include chunks that have been drawn to
  int minY = Integer.MAX_VALUE;
  int maxY = Integer.MIN_VALUE;
  boolean hasContent = false;
  
  for (int i = 0; i < chunkPositions.size(); i++) {
    int chunkY = chunkPositions.get(i);
    // Always include all chunks for now
    minY = min(minY, chunkY);
    maxY = max(maxY, chunkY + CHUNK_HEIGHT);
    hasContent = true;
  }
  
  if (!hasContent) {
    println("No content to save");
    return;
  }
  
  // Create output image directly without using PGraphics
  PImage output = createImage(CANVAS_WIDTH, maxY - minY, RGB);
  output.loadPixels();
  
  // Fill with white background
  for (int i = 0; i < output.pixels.length; i++) {
    output.pixels[i] = color(255);
  }
  
  // Copy each chunk to the output
  for (int i = 0; i < chunkTextures.size(); i++) {
    int chunkY = chunkPositions.get(i);
    PGraphics chunk = chunkTextures.get(i);
    
    // Get the pixel data from the chunk
    chunk.loadPixels();
    
    // Copy pixels manually
    for (int y = 0; y < CHUNK_HEIGHT; y++) {
      int outputY = chunkY - minY + y;
      if (outputY >= 0 && outputY < output.height) {
        for (int x = 0; x < CANVAS_WIDTH; x++) {
          int chunkIndex = y * CANVAS_WIDTH + x;
          int outputIndex = outputY * CANVAS_WIDTH + x;
          if (chunkIndex < chunk.pixels.length && outputIndex < output.pixels.length) {
            output.pixels[outputIndex] = chunk.pixels[chunkIndex];
          }
        }
      }
    }
  }
  
  output.updatePixels();
  
  // Save main output file
  String filename = "output.png";
  output.save(filename);
  println("Saved: " + filename + " (" + CANVAS_WIDTH + "x" + (maxY-minY) + ")");
  
  // Also save timestamped copy
  String timestampedFilename = "glsl_paint_" + millis() + ".png";
  output.save(timestampedFilename);
  
  // Print to thermal printer if requested
  if (printToReceipt) {
    printToThermalPrinter(filename);
  }
}

void printToThermalPrinter(String filename) {
  println("Printing to thermal printer...");
  
  try {
    // Get absolute path to Python script
    String scriptPath = sketchPath("munbyn_printer.py");
    String imagePath = sketchPath(filename);
    
    // Run Python script to print
    ProcessBuilder pb = new ProcessBuilder("python3", scriptPath, imagePath);
    pb.redirectErrorStream(true);
    Process p = pb.start();
    
    // Read output
    BufferedReader reader = new BufferedReader(new InputStreamReader(p.getInputStream()));
    String line;
    while ((line = reader.readLine()) != null) {
      println("Printer: " + line);
    }
    
    int exitCode = p.waitFor();
    if (exitCode == 0) {
      println("Print job sent successfully!");
    } else {
      println("Print failed with exit code: " + exitCode);
    }
    
  } catch (Exception e) {
    println("Error printing: " + e.getMessage());
    e.printStackTrace();
  }
}

// MIDI Functions using Java's built-in MIDI
void initMIDI() {
  try {
    MidiDevice.Info[] infos = MidiSystem.getMidiDeviceInfo();
    
    println("\nAvailable MIDI devices:");
    for (int i = 0; i < infos.length; i++) {
      println("[" + i + "] " + infos[i].getName() + " - " + infos[i].getDescription());
    }
    
    // Find Arduino Leonardo
    for (MidiDevice.Info info : infos) {
      if (info.getName().contains("Arduino Leonardo")) {
        MidiDevice device = MidiSystem.getMidiDevice(info);
        
        // Check if it's an input device (has transmitter)
        if (device.getMaxTransmitters() != 0) {
          device.open();
          
          // Set up receiver
          Transmitter transmitter = device.getTransmitter();
          transmitter.setReceiver(new MidiReceiver());
          
          midiDevice = device;
          midiConnected = true;
          println("\nMIDI connected to: " + info.getName());
          break;
        }
      }
    }
    
    if (!midiConnected) {
      println("Arduino Leonardo MIDI device not found or not available as input");
    }
    
  } catch (Exception e) {
    println("MIDI initialization failed: " + e.getMessage());
    e.printStackTrace();
    midiConnected = false;
  }
}

// Custom MIDI receiver class
class MidiReceiver implements Receiver {
  public void send(MidiMessage message, long timeStamp) {
    if (message instanceof ShortMessage) {
      ShortMessage sm = (ShortMessage) message;
      
      // Check for Control Change message (0xB0)
      if (sm.getCommand() == ShortMessage.CONTROL_CHANGE) {
        int channel = sm.getChannel() + 1;  // MIDI channels are 0-based
        int ccNumber = sm.getData1();
        int value = sm.getData2();
        
        // Handle CC1 for brush size
        if (ccNumber == 1) {
          // Map MIDI value (0-127) to brush size (1-8px)
          float newBrushSize = map(value, 0, 127, 1, 8);
          newBrushSize = constrain(newBrushSize, 1, 8);
          
          // Set pending brush size (thread-safe)
          pendingBrushSize = newBrushSize;
          
          // Trigger redraw to update display
          redraw();
          
          // Visual feedback
          println("MIDI CC1: value=" + value + " → Brush size = " + (int)newBrushSize + "px");
        }
      }
    }
  }
  
  public void close() {
    // Cleanup if needed
  }
}

// Clean up on exit
void exit() {
  // Clean up MIDI device
  if (midiDevice != null && midiDevice.isOpen()) {
    try {
      midiDevice.close();
    } catch (Exception e) {
      // Ignore errors during shutdown
    }
  }
  
  // Call parent exit
  super.exit();
}