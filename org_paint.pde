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

// Zoom state
boolean isSelectingZoom = false;  // Currently selecting zoom area
boolean isZoomed = false;  // Currently in zoomed view
PVector zoomSelectionStart = new PVector(-1, -1);
PVector zoomSelectionEnd = new PVector(-1, -1);
float zoomScale = 1.0;
float zoomOffsetX = 0;
float zoomOffsetY = 0;
boolean spaceKeyPressed = false;

// Mouse state for shader
PVector currentMouse = new PVector(-1, -1);
PVector prevMouse = new PVector(-1, -1);

// Undo/Redo state (single history)
ArrayList<PGraphics> undoChunkTextures;  // Store previous state
ArrayList<PGraphics> redoChunkTextures;  // Store state for redo
boolean hasUndo = false;
boolean hasRedo = false;
boolean captureUndoState = false;  // Flag to capture state before next paint
boolean pendingUndo = false;  // Defer undo to draw loop
boolean pendingRedo = false;  // Defer redo to draw loop
int undoRedrawFrames = 0;  // Counter to ensure proper screen update after undo/redo

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
  
  // Initialize undo/redo arrays
  undoChunkTextures = new ArrayList<PGraphics>();
  redoChunkTextures = new ArrayList<PGraphics>();
  
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
  println("  - Space: Hold to select zoom area, press again to exit zoom");
  println("  - Cmd+Z: Undo last action");
  println("  - Cmd+Shift+Z: Redo last action");
  if (midiConnected) {
    println("  - MIDI CC1: Brush size (1-8px)");
  }
}

// Save current canvas state for undo
void saveUndoState() {
  // Clear previous undo state
  for (PGraphics g : undoChunkTextures) {
    if (g != null) g.dispose();
  }
  undoChunkTextures.clear();
  
  // Copy all current chunks
  for (PGraphics chunk : chunkTextures) {
    PGraphics copy = createGraphics(chunk.width, chunk.height, P3D);
    copy.noSmooth();
    copy.beginDraw();
    copy.image(chunk, 0, 0);
    copy.endDraw();
    undoChunkTextures.add(copy);
  }
  
  hasUndo = true;
  hasRedo = false;  // Clear redo when new action is performed
  
  // Clear redo state
  for (PGraphics g : redoChunkTextures) {
    if (g != null) g.dispose();
  }
  redoChunkTextures.clear();
}

// Perform undo operation
void performUndo() {
  if (!hasUndo || undoChunkTextures.isEmpty()) return;
  
  // Save current state for redo
  for (PGraphics g : redoChunkTextures) {
    if (g != null) g.dispose();
  }
  redoChunkTextures.clear();
  
  for (PGraphics chunk : chunkTextures) {
    PGraphics copy = createGraphics(chunk.width, chunk.height, P3D);
    copy.noSmooth();
    copy.beginDraw();
    copy.image(chunk, 0, 0);
    copy.endDraw();
    redoChunkTextures.add(copy);
  }
  
  // Restore undo state
  for (int i = 0; i < min(chunkTextures.size(), undoChunkTextures.size()); i++) {
    PGraphics undoChunk = undoChunkTextures.get(i);
    PGraphics currentChunk = chunkTextures.get(i);
    currentChunk.beginDraw();
    currentChunk.image(undoChunk, 0, 0);
    currentChunk.endDraw();
  }
  
  hasRedo = true;
  hasUndo = false;
  needsRedraw = true;
}

// Perform redo operation
void performRedo() {
  if (!hasRedo || redoChunkTextures.isEmpty()) return;
  
  // Save current state for undo
  for (PGraphics g : undoChunkTextures) {
    if (g != null) g.dispose();
  }
  undoChunkTextures.clear();
  
  for (PGraphics chunk : chunkTextures) {
    PGraphics copy = createGraphics(chunk.width, chunk.height, P3D);
    copy.noSmooth();
    copy.beginDraw();
    copy.image(chunk, 0, 0);
    copy.endDraw();
    undoChunkTextures.add(copy);
  }
  
  // Restore redo state
  for (int i = 0; i < min(chunkTextures.size(), redoChunkTextures.size()); i++) {
    PGraphics redoChunk = redoChunkTextures.get(i);
    PGraphics currentChunk = chunkTextures.get(i);
    currentChunk.beginDraw();
    currentChunk.image(redoChunk, 0, 0);
    currentChunk.endDraw();
  }
  
  hasUndo = true;
  hasRedo = false;
  needsRedraw = true;
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
  
  // Check for pending undo/redo operations (must be done in draw loop for OpenGL)
  if (pendingUndo) {
    performUndo();
    pendingUndo = false;
    needsRedraw = true;
    undoRedrawFrames = 3;  // Ensure 3 frames of rendering
    // Don't return here - continue to render the frame
  }
  if (pendingRedo) {
    performRedo();
    pendingRedo = false;
    needsRedraw = true;
    undoRedrawFrames = 3;  // Ensure 3 frames of rendering
    // Don't return here - continue to render the frame
  }
  
  // Check for pending MIDI updates (thread-safe)
  if (pendingBrushSize > 0) {
    brushSize = pendingBrushSize;
    pendingBrushSize = -1;
    needsRedraw = true;
  }
  
  // OPTIMIZATION: Early return if nothing to update (but keep going if undo frames are active)
  if (!needsRedraw && !isDrawing && !isErasing && undoRedrawFrames == 0) return;
  
  // Calculate max scroll based on actual content
  float maxScroll = getMaxContentY() - SCREEN_HEIGHT;
  maxScroll = max(0, maxScroll);
  scrollY = constrain(scrollY, 0, maxScroll);
  
  // OPTIMIZATION: Only process painting when actively drawing (and not selecting zoom)
  if ((isDrawing || isErasing) && !isSelectingZoom) {
    // Capture undo state before first paint stroke
    if (captureUndoState) {
      saveUndoState();
      captureUndoState = false;
    }
    
    // Transform mouse coordinates based on zoom state
    float globalMouseX, globalMouseY;
    
    if (isZoomed) {
      // In zoomed mode, transform mouse from screen space to zoomed canvas space
      globalMouseX = (mouseX / displayScale - zoomOffsetX) / zoomScale;
      globalMouseY = (mouseY / displayScale - zoomOffsetY) / zoomScale + scrollY;
    } else {
      // Normal mode
      globalMouseX = mouseX / displayScale;
      globalMouseY = mouseY / displayScale + scrollY;
    }
    
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
  
  // Apply zoom transformation if zoomed
  if (isZoomed) {
    lowResCanvas.pushMatrix();
    lowResCanvas.translate(zoomOffsetX, zoomOffsetY);
    lowResCanvas.scale(zoomScale);
  }
  
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
  
  if (isZoomed) {
    lowResCanvas.popMatrix();
  }
  
  // Draw UI on low-res canvas (always on top, not zoomed)
  drawLowResUI();
  
  // Draw zoom selection rectangle if selecting
  if (isSelectingZoom && zoomSelectionStart.x >= 0) {
    lowResCanvas.noFill();
    lowResCanvas.stroke(100, 200, 255);
    lowResCanvas.strokeWeight(2);
    float x1 = min(zoomSelectionStart.x, zoomSelectionEnd.x);
    float y1 = min(zoomSelectionStart.y, zoomSelectionEnd.y);
    float x2 = max(zoomSelectionStart.x, zoomSelectionEnd.x);
    float y2 = max(zoomSelectionStart.y, zoomSelectionEnd.y);
    lowResCanvas.rect(x1, y1, x2 - x1, y2 - y1);
  }
  
  lowResCanvas.endDraw();
  
  // Scale up and display (fill screen)
  background(0);
  
  pushMatrix();
  scale(displayScale);
  image(lowResCanvas, 0, 0);
  popMatrix();
  
  // Reset redraw flag
  needsRedraw = false;
  
  // Handle undo/redo frame counter
  if (undoRedrawFrames > 0) {
    undoRedrawFrames--;
    needsRedraw = true;  // Keep rendering
    if (undoRedrawFrames == 0) {
      noLoop();  // Stop loop after undo/redo frames complete
    }
  }
}

void drawLowResUI() {
  // Draw UI directly on low-res canvas for pixel-perfect scaling
  
  // Brush preview (convert mouse position to low-res coordinates)
  float lowResMouseX = mouseX / displayScale;
  float lowResMouseY = mouseY / displayScale;
  
  // Transform brush position if zoomed
  if (isZoomed && !isSelectingZoom) {
    float canvasX = (lowResMouseX - zoomOffsetX) / zoomScale;
    float canvasY = (lowResMouseY - zoomOffsetY) / zoomScale;
    
    lowResCanvas.noFill();
    lowResCanvas.stroke(isErasing ? color(255, 100, 100) : color(100, 100, 255));
    lowResCanvas.strokeWeight(1);
    
    // Draw brush at zoomed position
    lowResCanvas.pushMatrix();
    lowResCanvas.translate(zoomOffsetX, zoomOffsetY);
    lowResCanvas.scale(zoomScale);
    lowResCanvas.ellipse(canvasX, canvasY, brushSize, brushSize);
    lowResCanvas.popMatrix();
  } else if (!isSelectingZoom) {
    // Normal brush preview
    lowResCanvas.noFill();
    lowResCanvas.stroke(isErasing ? color(255, 100, 100) : color(100, 100, 255));
    lowResCanvas.strokeWeight(1);
    lowResCanvas.ellipse(lowResMouseX, lowResMouseY, brushSize, brushSize);
  }
  
  // Info text - BLACK color for white background
  lowResCanvas.fill(0);  // Black text
  lowResCanvas.noStroke();
  lowResCanvas.textAlign(LEFT, TOP);
  lowResCanvas.textSize(8);  // Small pixel font size
  
  if (isSelectingZoom) {
    lowResCanvas.text("SELECTING ZOOM AREA", 2, 2);
  } else if (isZoomed) {
    lowResCanvas.text("ZOOMED: " + nf(zoomScale, 1, 1) + "x (SPACE to exit)", 2, 2);
  } else {
    lowResCanvas.text("MODE: " + (isErasing ? "ERASE" : "DRAW"), 2, 2);
  }
  
  lowResCanvas.text("BRUSH: " + (int)brushSize + "px", 2, 10);
  if (!isZoomed) {
    lowResCanvas.text("Y: " + (int)scrollY, 2, 18);
  }
  lowResCanvas.text("X: " + (int)lowResMouseX + "/" + CANVAS_WIDTH, 2, isZoomed ? 18 : 26);
  lowResCanvas.text("FPS: " + (int)frameRate, 2, isZoomed ? 26 : 34);
  if (midiConnected) {
    lowResCanvas.text("MIDI: ON", 2, isZoomed ? 34 : 42);
  }
}

void mousePressed() {
  // If selecting zoom, record start position
  if (isSelectingZoom) {
    zoomSelectionStart.set(mouseX / displayScale, mouseY / displayScale);
    zoomSelectionEnd.set(mouseX / displayScale, mouseY / displayScale);
    needsRedraw = true;
    loop();
    return;
  }
  
  // Don't allow painting while space is pressed (might be about to select zoom)
  if (spaceKeyPressed) {
    return;
  }
  
  if (mouseButton == LEFT) {
    // Mark that we need to save state before first paint
    captureUndoState = true;
    isDrawing = true;
    isErasing = false;
  } else if (mouseButton == RIGHT) {
    // Mark that we need to save state before first paint
    captureUndoState = true;
    isDrawing = true;
    isErasing = true;
  }
  
  // Adjust for scale and zoom
  if (isZoomed) {
    float canvasX = (mouseX / displayScale - zoomOffsetX) / zoomScale;
    float canvasY = (mouseY / displayScale - zoomOffsetY) / zoomScale + scrollY;
    prevMouse.set(canvasX, canvasY);
  } else {
    prevMouse.set(mouseX / displayScale, mouseY / displayScale + scrollY);
  }
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
  // If selecting zoom, update end position
  if (isSelectingZoom) {
    zoomSelectionEnd.set(mouseX / displayScale, mouseY / displayScale);
    needsRedraw = true;
    redraw();
    return;
  }
  
  // Keep rendering while dragging
  needsRedraw = true;
  redraw();
}

void mouseWheel(MouseEvent event) {
  // Disable scrolling when zoomed
  if (isZoomed) {
    return;
  }
  
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
  
  // Handle Cmd+Z for undo and Cmd+Shift+Z for redo
  boolean isMac = System.getProperty("os.name").toLowerCase().contains("mac");
  boolean cmdPressed = isMac ? (keyEvent.isMetaDown()) : (keyEvent.isControlDown());
  
  if (cmdPressed) {
    if (key == 'z' || key == 'Z') {
      if (keyEvent.isShiftDown()) {
        // Cmd+Shift+Z - Redo (deferred to draw loop)
        pendingRedo = true;
        needsRedraw = true;
        loop();  // Start rendering loop (will stop after frames complete)
      } else {
        // Cmd+Z - Undo (deferred to draw loop)
        pendingUndo = true;
        needsRedraw = true;
        loop();  // Start rendering loop (will stop after frames complete)
      }
      return;
    }
  }
  
  // Handle Space key for zoom
  if (key == ' ') {
    if (!spaceKeyPressed) {
      spaceKeyPressed = true;
      
      if (isZoomed) {
        // Exit zoom mode
        isZoomed = false;
        zoomScale = 1.0;
        zoomOffsetX = 0;
        zoomOffsetY = 0;
        needsRedraw = true;
        redraw();
      } else {
        // Enter zoom selection mode
        isSelectingZoom = true;
        zoomSelectionStart.set(-1, -1);
        zoomSelectionEnd.set(-1, -1);
        needsRedraw = true;
        loop();
      }
    }
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
    // Disable arrow key scrolling when zoomed
    if (isZoomed) {
      return;
    }
    
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

void keyReleased() {
  // Handle Space key release for zoom
  if (key == ' ') {
    spaceKeyPressed = false;
    
    if (isSelectingZoom && zoomSelectionStart.x >= 0) {
      // Calculate zoom from selection
      float x1 = min(zoomSelectionStart.x, zoomSelectionEnd.x);
      float y1 = min(zoomSelectionStart.y, zoomSelectionEnd.y);
      float x2 = max(zoomSelectionStart.x, zoomSelectionEnd.x);
      float y2 = max(zoomSelectionStart.y, zoomSelectionEnd.y);
      
      float selWidth = x2 - x1;
      float selHeight = y2 - y1;
      
      // Minimum selection size to zoom (20px)
      if (selWidth > 20 && selHeight > 20) {
        // Calculate zoom scale to fit selection to screen
        float scaleX = CANVAS_WIDTH / selWidth;
        float scaleY = SCREEN_HEIGHT / selHeight;
        zoomScale = min(scaleX, scaleY);
        
        // Limit zoom scale to reasonable range (1.5x - 10x)
        zoomScale = constrain(zoomScale, 1.5, 10.0);
        
        // Calculate offset to center the selection
        float centerX = (x1 + x2) / 2;
        float centerY = (y1 + y2) / 2;
        
        // Calculate offset so that zoomed area is centered
        zoomOffsetX = CANVAS_WIDTH / 2 - centerX * zoomScale;
        zoomOffsetY = SCREEN_HEIGHT / 2 - centerY * zoomScale;
        
        // Apply zoom
        isZoomed = true;
        isSelectingZoom = false;
        needsRedraw = true;
        redraw();
      } else {
        // Selection too small, cancel
        isSelectingZoom = false;
        needsRedraw = true;
        redraw();
      }
    } else {
      // No selection made, cancel
      isSelectingZoom = false;
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