// Infinite Canvas Painting App - GLSL Version
// For thermal printer output (576px width)
// ALL rendering done with GLSL shaders

import java.io.*;

PShader paintShader;
ArrayList<PGraphics> chunkTextures;  // GPU textures
ArrayList<PGraphics> chunkBuffers;   // Ping-pong buffers
ArrayList<Integer> chunkPositions;

// Canvas settings
final int CANVAS_WIDTH = 576;
final int CHUNK_HEIGHT = 1024;
final int SCREEN_HEIGHT = 324;

// Drawing state
boolean isDrawing = false;
boolean isErasing = false;
float brushSize = 2.0;  // Default 2px
float scrollY = 0;
float scrollVelocity = 0;

// Mouse state for shader
PVector currentMouse = new PVector(-1, -1);
PVector prevMouse = new PVector(-1, -1);

// Scaling for display
PGraphics lowResCanvas;
float displayScale = 1.0;

void setup() {
  fullScreen(P3D);  // Fullscreen
  
  // Calculate scale to fill screen (use larger scale to fill entire screen)
  displayScale = max((float)width / CANVAS_WIDTH, (float)height / SCREEN_HEIGHT);
  
  // Create low-res canvas for actual drawing
  lowResCanvas = createGraphics(CANVAS_WIDTH, SCREEN_HEIGHT, P3D);
  
  // Initialize GPU texture arrays
  chunkTextures = new ArrayList<PGraphics>();
  chunkBuffers = new ArrayList<PGraphics>();
  chunkPositions = new ArrayList<Integer>();
  
  // Load final GLSL paint shader
  paintShader = loadShader("paint_final_frag.glsl");
  
  // Create initial chunk
  createGPUChunk(0);
  
  println("GLSL-based infinite canvas initialized");
  println("Canvas width: " + CANVAS_WIDTH + "px");
  println("All rendering on GPU with GLSL shaders");
  println("Controls:");
  println("  - Left click: Draw");
  println("  - Right click: Erase");
  println("  - Mouse wheel/Arrow keys: Scroll");
  println("  - Q/A: Brush size");
  println("  - P: Save and Print to thermal printer");
}

void createGPUChunk(int yPos) {
  // Check if already exists
  for (int i = 0; i < chunkPositions.size(); i++) {
    if (chunkPositions.get(i) == yPos) return;
  }
  
  // Create two GPU textures for ping-pong
  PGraphics texture = createGraphics(CANVAS_WIDTH, CHUNK_HEIGHT, P3D);
  PGraphics buffer = createGraphics(CANVAS_WIDTH, CHUNK_HEIGHT, P3D);
  
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
  // Calculate max scroll based on actual content
  float maxScroll = getMaxContentY() - SCREEN_HEIGHT;
  maxScroll = max(0, maxScroll);
  
  // Handle scrolling with limits
  if (abs(scrollVelocity) > 0.1) {
    scrollY += scrollVelocity;
    scrollY = constrain(scrollY, 0, maxScroll);
    scrollVelocity *= 0.9;
  }
  
  // Apply painting (adjust mouse coords for scaling)
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
  lowResCanvas.text("FPS: " + (int)frameRate, 2, 26);
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
}

void mouseReleased() {
  isDrawing = false;
  isErasing = false;
  prevMouse.set(-1, -1);
}

void mouseWheel(MouseEvent event) {
  scrollVelocity += event.getCount() * 0.7;  // トラックパッド用に最適化
}

void keyPressed() {
  switch(key) {
    case 'q':
    case 'Q':
      brushSize = min(brushSize + 5, 100);
      break;
    case 'a':
    case 'A':
      brushSize = max(brushSize - 5, 1);  // Minimum 1px
      break;
    case 'p':
    case 'P':
      saveAndPrint(true);  // Save and print to thermal printer
      break;
  }
  
  if (key == CODED) {
    if (keyCode == UP) scrollVelocity -= 20;
    if (keyCode == DOWN) scrollVelocity += 20;
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

void clearCanvas() {
  for (PGraphics chunk : chunkTextures) {
    chunk.beginDraw();
    chunk.background(255);
    chunk.endDraw();
  }
  for (PGraphics chunk : chunkBuffers) {
    chunk.beginDraw();
    chunk.background(255);
    chunk.endDraw();
  }
  println("GPU textures cleared");
}

void saveCanvas() {
  saveAndPrint(false);  // Just save, don't print
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
  
  // Create output with JAVA2D renderer for compatibility
  PGraphics output = createGraphics(CANVAS_WIDTH, maxY - minY, JAVA2D);
  output.beginDraw();
  output.background(255);
  
  // Copy each chunk to the output
  for (int i = 0; i < chunkTextures.size(); i++) {
    int chunkY = chunkPositions.get(i);
    PGraphics chunk = chunkTextures.get(i);
    
    // Get the pixel data from the chunk
    chunk.loadPixels();
    output.image(chunk, 0, chunkY - minY);
  }
  
  output.endDraw();
  
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